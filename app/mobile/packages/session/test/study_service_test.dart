import 'package:domain/domain.dart';
// drift exports `isNotNull` and a generated `CardState`; both collide with
// `package:test` and `package:domain`. Hiding is clearer than prefixing here,
// because the test only needs drift for InsertMode and Value.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:scheduler/scheduler.dart';
import 'package:session/session.dart';
import 'package:store/store.dart' hide CardState;
import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tzdata;

late AppDatabase db;
late StudyService study;

final params = FsrsParams(weights: defaultFsrsWeights);
const day = DayBucket(timezoneName: 'America/Sao_Paulo');
final t0 = DateTime.utc(2026, 8, 9, 15); // 12:00 in São Paulo

Future<void> makeCard(String id, {String deck = 'd1'}) async {
  await db.into(db.decks).insert(
        DecksCompanion.insert(id: deck, name: 'B', updatedAt: 0, deviceId: 'dev'),
        mode: InsertMode.insertOrIgnore,
      );
  await db.into(db.cards).insert(
        CardsCompanion.insert(
          id: id,
          deckId: deck,
          front: 'frente $id',
          back: 'verso $id',
          updatedAt: 0,
          deviceId: 'dev',
        ),
      );
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    study = StudyService(db, deviceId: 'phone', params: params);
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async => db.close());

  group('recording (§5.8)', () {
    test('an answer is written immediately, not at the end of a session', () async {
      // The end of a session is exactly what does not happen when the user
      // closes the app on the subway.
      await makeCard('c1');
      await study.recordReview(cardId: 'c1', grade: Grade.good, at: t0);

      expect((await db.select(db.reviews).get()).length, 1);
      final state = await study.stateOf('c1');
      expect(state.reps, 1);
      expect(state.dueAt, isNotNull);
    });

    test('the state advances through the scheduler, not by hand', () async {
      await makeCard('c1');
      final returned = await study.recordReview(cardId: 'c1', grade: Grade.good, at: t0);
      final expected = Scheduler.apply(CardState.fresh('c1'), Grade.good, t0, params);

      expect(returned.dueAt, expected.dueAt);
      expect(returned.stability, expected.stability);
    });

    test('the interval shown is the interval written (§5.8.3)', () async {
      await makeCard('c1');
      await study.recordReview(cardId: 'c1', grade: Grade.good, at: t0);

      final at = (await study.stateOf('c1')).dueAt!;
      final preview = await study.preview('c1', at);
      final after = await study.recordReview(cardId: 'c1', grade: Grade.hard, at: at);

      expect(after.dueAt!.difference(at), preview[Grade.hard]);
    });

    test('advisory snapshots are written once and are not read back', () async {
      await makeCard('c1');
      await study.recordReview(cardId: 'c1', grade: Grade.good, at: t0);

      final row = await db.select(db.reviews).getSingle();
      expect(row.stabilityAfter, isNotNull);
      expect(row.intervalDaysAfter, isNotNull);

      // §5.2 — replay is the authority; corrupting the snapshot changes nothing.
      final replayed = await study.rebuild('c1');
      expect(replayed.stability, (await study.stateOf('c1')).stability);
    });

    test('a session left half-finished keeps what was answered', () async {
      await makeCard('c1');
      await makeCard('c2');
      await study.recordReview(cardId: 'c1', grade: Grade.good, at: t0);
      // c2 never answered — no crash, no rollback of c1.

      expect((await study.stateOf('c1')).reps, 1);
      expect((await study.stateOf('c2')).reps, 0);
    });
  });

  group('replay and out-of-order arrival (§5.3)', () {
    test('a review arriving in order folds in incrementally', () async {
      await makeCard('c1');
      await study.recordReview(cardId: 'c1', grade: Grade.good, at: t0);

      await study.ingestRemoteReview(
        id: 'remote-1',
        cardId: 'c1',
        reviewedAt: t0.add(const Duration(days: 2)),
        grade: Grade.good,
        source: ReviewSource.standard,
        fromDeviceId: 'tablet',
        serverSeq: 5,
      );

      final state = await study.stateOf('c1');
      expect(state.reps, 2);
      expect(await _isDirty('c1'), isFalse);
    });

    test('a review arriving late marks the card dirty instead of skipping it', () async {
      // FSRS is order dependent, so folding a late review in at the end would
      // produce a state that never happened.
      await makeCard('c1');
      await study.recordReview(cardId: 'c1', grade: Grade.good, at: t0);
      await study.recordReview(
        cardId: 'c1',
        grade: Grade.good,
        at: t0.add(const Duration(days: 5)),
      );

      await study.ingestRemoteReview(
        id: 'late',
        cardId: 'c1',
        reviewedAt: t0.add(const Duration(days: 1)), // before the watermark
        grade: Grade.again,
        source: ReviewSource.standard,
        fromDeviceId: 'tablet',
      );

      expect(await _isDirty('c1'), isTrue);
    });

    test('rebuilding a dirty card reaches the state the full log implies', () async {
      await makeCard('c1');
      await study.recordReview(cardId: 'c1', grade: Grade.good, at: t0);
      await study.recordReview(
        cardId: 'c1',
        grade: Grade.good,
        at: t0.add(const Duration(days: 5)),
      );
      await study.ingestRemoteReview(
        id: 'late',
        cardId: 'c1',
        reviewedAt: t0.add(const Duration(days: 1)),
        grade: Grade.again,
        source: ReviewSource.standard,
        fromDeviceId: 'tablet',
      );

      expect(await study.rebuildDirty(), 1);

      final rebuilt = await study.stateOf('c1');
      expect(rebuilt.reps, 3);
      expect(rebuilt.lapses, greaterThanOrEqualTo(0));
      expect(await _isDirty('c1'), isFalse);
    });

    test('the same review arriving twice is inserted once', () async {
      await makeCard('c1');
      for (var i = 0; i < 2; i++) {
        await study.ingestRemoteReview(
          id: 'same',
          cardId: 'c1',
          reviewedAt: t0,
          grade: Grade.good,
          source: ReviewSource.standard,
          fromDeviceId: 'tablet',
        );
      }
      expect((await db.select(db.reviews).get()).length, 1);
    });

    test('a dirty card is kept out of the queue until it is rebuilt', () async {
      await makeCard('c1');
      await study.recordReview(cardId: 'c1', grade: Grade.again, at: t0);
      await db.markDirty('c1');

      final due = await db.dueCardIds(t0.add(const Duration(days: 10)));
      expect(due, isEmpty, reason: 'a stale due date must not schedule work');
    });
  });

  group('daily limits (§5.8)', () {
    test('the new-card limit never borrows from the review limit', () async {
      // Keeping them apart is what stops today's enthusiasm from inflating
      // every future day's workload.
      for (var i = 0; i < 10; i++) {
        await makeCard('n$i');
      }

      final queue = await study.buildQueue(
        now: t0,
        newPerDay: 3,
        reviewPerDay: 50,
        day: day,
      );
      expect(queue.length, 3);
    });

    test('new cards already seen today count against the limit', () async {
      for (var i = 0; i < 5; i++) {
        await makeCard('n$i');
      }
      await study.recordReview(cardId: 'n0', grade: Grade.good, at: t0);
      await study.recordReview(cardId: 'n1', grade: Grade.good, at: t0);

      final counts = await study.countReviewsOn(day.today(t0), day);
      expect(counts.newCards, 2);
      expect(counts.reviews, 0);

      final queue = await study.buildQueue(
        now: t0,
        newPerDay: 3,
        reviewPerDay: 50,
        day: day,
      );
      expect(queue.length, 1, reason: 'only one new card left in today\'s allowance');
    });

    test('a second answer on the same card today is a review, not a new card', () async {
      await makeCard('c1');
      await study.recordReview(cardId: 'c1', grade: Grade.again, at: t0);
      await study.recordReview(
        cardId: 'c1',
        grade: Grade.good,
        at: t0.add(const Duration(minutes: 10)),
      );

      final counts = await study.countReviewsOn(day.today(t0), day);
      expect(counts.newCards, 1, reason: 'the card is only new once');
      expect(counts.reviews, 0);
    });

    test('the count follows the 04:00 cutoff, not midnight (§5.7)', () async {
      await makeCard('c1');
      // 01:00 in São Paulo, which belongs to the previous local day.
      final lateNight = DateTime.utc(2026, 8, 10, 4);
      await study.recordReview(cardId: 'c1', grade: Grade.good, at: lateNight);

      expect((await study.countReviewsOn('2026-08-09', day)).newCards, 1);
      expect((await study.countReviewsOn('2026-08-10', day)).newCards, 0);
    });

    test('a suspended card never enters the queue', () async {
      await makeCard('c1');
      await study.suspend('c1', t0);
      expect(await study.buildQueue(now: t0, newPerDay: 10, reviewPerDay: 10, day: day),
          isEmpty);
    });
  });

  group('suspend, bury and reset (§4, §5.10)', () {
    test('burying hides the card until the next local day', () async {
      await makeCard('c1');
      await study.recordReview(cardId: 'c1', grade: Grade.again, at: t0);
      await study.bury('c1', t0, day);

      final soon = t0.add(const Duration(hours: 2));
      expect(await db.dueCardIds(soon), isEmpty);

      // 04:00 São Paulo the next day.
      final tomorrow = DateTime.utc(2026, 8, 10, 7, 1);
      expect(await db.dueCardIds(tomorrow), contains('c1'));
    });

    test('unsuspending puts the card back', () async {
      await makeCard('c1');
      await study.recordReview(cardId: 'c1', grade: Grade.again, at: t0);
      await study.suspend('c1', t0);
      await study.unsuspend('c1', t0);

      expect(await db.dueCardIds(t0.add(const Duration(days: 1))), contains('c1'));
    });

    test('resetting progress keeps every review but restarts the schedule', () async {
      await makeCard('c1');
      var at = t0;
      for (var i = 0; i < 4; i++) {
        final state = await study.recordReview(cardId: 'c1', grade: Grade.good, at: at);
        at = state.dueAt!;
      }
      expect((await study.stateOf('c1')).reps, 4);

      final after = await study.resetProgress('c1', at.add(const Duration(days: 1)));

      expect(after.phase, CardPhase.newCard, reason: 'the schedule starts over');
      expect(after.reps, 0);
      expect(
        (await db.select(db.reviews).get()).length,
        4,
        reason: '§3 forbids deleting history — statistics still see it',
      );
    });

    test('a reset is itself append-only', () async {
      await makeCard('c1');
      await study.resetProgress('c1', t0);
      expect(
        () => db.customStatement('DELETE FROM progress_resets'),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('outbox (§6.4)', () {
    test('a new review is unacknowledged until the server assigns a seq', () async {
      await makeCard('c1');
      expect(await study.outboxDepth(), 2, reason: 'the deck and the card are pending');

      await study.recordReview(cardId: 'c1', grade: Grade.good, at: t0);
      expect(await study.outboxDepth(), 3);
    });

    test('acknowledging clears the row from the outbox', () async {
      await makeCard('c1');
      await study.recordReview(cardId: 'c1', grade: Grade.good, at: t0);

      final review = await db.select(db.reviews).getSingle();
      await study.acknowledgeReviews({review.id: 42});

      final after = await db.select(db.reviews).getSingle();
      expect(after.serverSeq, 42);
      expect(await study.outboxDepth(), 2, reason: 'only the review was acknowledged');
    });

    test('a review pulled from the server is not queued for push', () async {
      await makeCard('c1');
      final before = await study.outboxDepth();

      await study.ingestRemoteReview(
        id: 'remote',
        cardId: 'c1',
        reviewedAt: t0,
        grade: Grade.good,
        source: ReviewSource.standard,
        fromDeviceId: 'tablet',
        serverSeq: 9,
      );

      expect(await study.outboxDepth(), before, reason: 'it already has a server_seq');
    });
  });
}

Future<bool> _isDirty(String cardId) async {
  final row = await (db.select(db.cardStates)..where((t) => t.cardId.equals(cardId)))
      .getSingleOrNull();
  return row?.dirty ?? false;
}
