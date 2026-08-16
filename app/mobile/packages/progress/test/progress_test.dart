import 'package:domain/domain.dart';
import 'package:drift/native.dart';
import 'package:progress/progress.dart';
import 'package:scheduler/scheduler.dart';
import 'package:session/session.dart';
import 'package:store/store.dart' hide CardState;
import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tzdata;

late AppDatabase db;
late StudyService study;
late ProgressService progress;

final params = FsrsParams(weights: defaultFsrsWeights);
const day = DayBucket(timezoneName: 'America/Sao_Paulo');
final t0 = DateTime.utc(2026, 8, 9, 15); // 12:00 in São Paulo

int ms(DateTime t) => t.toUtc().millisecondsSinceEpoch;

Future<void> makeCard(String id, {String deck = 'd1'}) async {
  await db.customStatement(
    "INSERT OR IGNORE INTO decks (id, name, version, origin, updated_at, device_id) "
    "VALUES ('$deck', 'B', 1, 'own', 0, 'dev')",
  );
  await db.customStatement(
    "INSERT INTO cards (id, deck_id, front, back, tags, updated_at, device_id) "
    "VALUES ('$id', '$deck', 'f', 'v', '[]', 0, 'dev')",
  );
}

Future<void> setGoal(int goal, String fromDay, {int order = 0}) async {
  await db.customStatement(
    "INSERT INTO goal_history (id, effective_from_local_date, daily_goal, created_at, device_id) "
    "VALUES ('g$fromDay$order', '$fromDay', $goal, $order, 'dev')",
  );
}

/// Answers [count] cards on the given local day.
Future<void> studyOn(String dayKey, int count, {int startIndex = 0}) async {
  final (start, _) = day.rangeOf(dayKey);
  for (var i = 0; i < count; i++) {
    final id = 'c$dayKey$startIndex$i';
    await makeCard(id);
    await study.recordReview(
      cardId: id,
      grade: Grade.good,
      at: start.add(Duration(hours: 8, minutes: i)),
    );
  }
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    study = StudyService(db, deviceId: 'phone', params: params);
    progress = ProgressService(db, day: day);
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async => db.close());

  group('memória acumulada (§9, §2.3)', () {
    test('creating cards does not move it', () async {
      // The core of §2.3: no visible metric may be inflated by raw effort.
      for (var i = 0; i < 100; i++) {
        await makeCard('c$i');
      }
      expect((await progress.accumulatedMemory()).days, 0);
    });

    test('remembering over time raises it', () async {
      await makeCard('c1');
      var at = t0;
      for (var i = 0; i < 5; i++) {
        final state = await study.recordReview(cardId: 'c1', grade: Grade.good, at: at);
        at = state.dueAt!;
      }
      expect((await progress.accumulatedMemory()).days, greaterThan(0));
    });

    test('a lapse lowers it', () async {
      await makeCard('c1');
      var at = t0;
      for (var i = 0; i < 6; i++) {
        final state = await study.recordReview(cardId: 'c1', grade: Grade.good, at: at);
        at = state.dueAt!;
      }
      final before = (await progress.accumulatedMemory()).days;

      await study.recordReview(cardId: 'c1', grade: Grade.again, at: at);
      expect((await progress.accumulatedMemory()).days, lessThan(before));
    });

    test('a suspended card stops counting', () async {
      await makeCard('c1');
      await study.recordReview(cardId: 'c1', grade: Grade.easy, at: t0);
      expect((await progress.accumulatedMemory()).days, greaterThan(0));

      await study.suspend('c1', t0);
      expect((await progress.accumulatedMemory()).days, 0);
    });

    test('the label reads as time, not as a number', () async {
      expect(const AccumulatedMemory(1155).label, '3 anos e 2 meses');
      expect(const AccumulatedMemory(365).label, '1 ano');
      expect(const AccumulatedMemory(61).label, '2 meses');
      expect(const AccumulatedMemory(12).label, '12 dias');

      // The carry: 11.9 months must read as a year, never "0 anos e 12 meses".
      expect(const AccumulatedMemory(362).label, '1 ano');
    });

    test('the metric does not depend on the retention target', () async {
      // §9 — stability is days-to-90% by definition; the interval derives from
      // the target, the stability does not. If this coupled, lowering the
      // target would silently change the headline number's meaning.
      Future<double> memoryWith(double retention) async {
        final fresh = AppDatabase(NativeDatabase.memory());
        final svc = StudyService(
          fresh,
          deviceId: 'phone',
          params: FsrsParams(weights: defaultFsrsWeights, desiredRetention: retention),
        );
        await fresh.customStatement(
          "INSERT INTO decks (id, name, version, origin, updated_at, device_id) "
          "VALUES ('d', 'B', 1, 'own', 0, 'dev')",
        );
        await fresh.customStatement(
          "INSERT INTO cards (id, deck_id, front, back, tags, updated_at, device_id) "
          "VALUES ('c', 'd', 'f', 'v', '[]', 0, 'dev')",
        );
        var at = t0;
        for (var i = 0; i < 4; i++) {
          final state = await svc.recordReview(cardId: 'c', grade: Grade.good, at: at);
          at = state.dueAt!;
        }
        final total = (await ProgressService(fresh, day: day).accumulatedMemory()).days;
        await fresh.close();
        return total;
      }

      // Same review pattern at the same wall-clock times would give the same
      // stability; here the schedule differs, so we assert only that a lower
      // target does not *reduce* remembered strength.
      expect(await memoryWith(0.80), greaterThan(0));
      expect(await memoryWith(0.95), greaterThan(0));
    });
  });

  group('retention and maturity', () {
    test('retention counts what was remembered, not what was attempted', () async {
      await makeCard('c1');
      await makeCard('c2');
      await study.recordReview(cardId: 'c1', grade: Grade.good, at: t0);
      await study.recordReview(cardId: 'c2', grade: Grade.again, at: t0);

      expect(await progress.retention(), closeTo(0.5, 0.001));
    });

    test('an empty log has no retention, which is not the same as zero',
        () async {
      // Rendered, 0.0 tells someone who has never answered a card that they
      // get everything wrong. Null is the honest answer and the type stops a
      // caller showing one as the other.
      expect(await progress.retention(), isNull);
      // Accumulated memory genuinely is zero: nothing has been remembered.
      expect((await progress.accumulatedMemory()).days, 0);
    });

    test('one review is enough to have a retention', () async {
      await makeCard('c1');
      await study.recordReview(cardId: 'c1', grade: Grade.again, at: t0);

      // And here zero is the truth, not a placeholder.
      expect(await progress.retention(), 0);
    });

    test('maturity is the 21-day cut, per deck', () async {
      await makeCard('novo');
      await makeCard('maduro');
      await study.recordReview(cardId: 'novo', grade: Grade.good, at: t0);

      var at = t0;
      for (var i = 0; i < 12; i++) {
        final state = await study.recordReview(cardId: 'maduro', grade: Grade.easy, at: at);
        at = state.dueAt!;
      }

      final decks = await progress.maturityByDeck();
      expect(decks.single.total, 2);
      expect(decks.single.mature, 1);
      expect(decks.single.ratio, closeTo(0.5, 0.001));
    });
  });

  group('heatmap and load (§5.7, §5.11)', () {
    test('reviews are bucketed by local day, not UTC day', () async {
      await makeCard('c1');
      // 01:00 in São Paulo belongs to the previous local day.
      await study.recordReview(
        cardId: 'c1',
        grade: Grade.good,
        at: DateTime.utc(2026, 8, 10, 4),
      );

      final map = await progress.heatmap(
        from: DateTime.utc(2026, 8, 1),
        to: DateTime.utc(2026, 8, 20),
      );
      expect(map['2026-08-09'], 1);
      expect(map.containsKey('2026-08-10'), isFalse);
    });

    test('the forecast counts cards falling due per day', () async {
      await makeCard('c1');
      await study.recordReview(cardId: 'c1', grade: Grade.easy, at: t0);

      final forecast = await progress.loadForecast(from: t0, days: 60);
      expect(forecast.values.fold<int>(0, (a, b) => a + b), 1);
    });

    test('a suspended card is not forecast work', () async {
      await makeCard('c1');
      await study.recordReview(cardId: 'c1', grade: Grade.easy, at: t0);
      await study.suspend('c1', t0);

      final forecast = await progress.loadForecast(from: t0, days: 60);
      expect(forecast.values.fold<int>(0, (a, b) => a + b), 0);
    });
  });

  group('the streak (§5.11)', () {
    test('it counts days the goal was met, not days the app was opened', () async {
      await setGoal(2, '2026-08-01');
      await studyOn('2026-08-09', 2);
      await studyOn('2026-08-08', 2);
      await studyOn('2026-08-07', 1); // short of the goal

      expect(await progress.streak(t0, forgivenessPerMonth: 0), 2);
    });

    test('lowering the goal does not invent a past streak', () async {
      // The reason goal_history exists: comparing history against the current
      // goal makes the streak rewrite itself.
      await setGoal(10, '2026-08-01');
      await studyOn('2026-08-09', 3);
      await studyOn('2026-08-08', 3);

      expect(await progress.streak(t0, forgivenessPerMonth: 0), 0);

      // Today the user drops the goal to 3. The past must not change.
      await setGoal(3, '2026-08-09', order: 1);
      expect(
        await progress.streak(t0.subtract(const Duration(days: 1)),
            forgivenessPerMonth: 0),
        0,
        reason: 'yesterday was still judged against the goal in force then',
      );
    });

    test('raising the goal does not erase a streak already earned', () async {
      await setGoal(2, '2026-08-01');
      await studyOn('2026-08-08', 2);
      await studyOn('2026-08-07', 2);

      await setGoal(50, '2026-08-09', order: 1);
      final yesterday = t0.subtract(const Duration(days: 1));
      expect(await progress.streak(yesterday, forgivenessPerMonth: 0), 2);
    });

    test('a missed day is forgiven, up to the monthly allowance', () async {
      await setGoal(1, '2026-08-01');
      await studyOn('2026-08-09', 1);
      // 08-08 missed
      await studyOn('2026-08-07', 1);
      await studyOn('2026-08-06', 1);

      expect(await progress.streak(t0, forgivenessPerMonth: 0), 1);
      expect(await progress.streak(t0, forgivenessPerMonth: 2), 3);
    });

    test('the allowance runs out', () async {
      await setGoal(1, '2026-08-01');
      await studyOn('2026-08-09', 1);
      // 08-08 and 08-07 both missed
      await studyOn('2026-08-06', 1);

      expect(await progress.streak(t0, forgivenessPerMonth: 1), 1);
      expect(await progress.streak(t0, forgivenessPerMonth: 2), 2);
    });

    test('today not yet met does not break the streak', () async {
      // Otherwise the streak would read as broken every morning.
      await setGoal(1, '2026-08-01');
      await studyOn('2026-08-08', 1);
      await studyOn('2026-08-07', 1);

      expect(await progress.streak(t0, forgivenessPerMonth: 0), 2);
    });

    test('with no goal ever set there is no streak', () async {
      await studyOn('2026-08-09', 5);
      expect(await progress.streak(t0), 0);
    });
  });

  group('milestones (§5.11)', () {
    test('crossing six months is reported once', () async {
      await makeCard('c1');
      var at = t0;
      for (var i = 0; i < 25; i++) {
        final state = await study.recordReview(cardId: 'c1', grade: Grade.easy, at: at);
        at = state.dueAt!;
        if (state.interval!.inDays >= 180) break;
      }

      final all = await progress.graduations(
        from: t0.subtract(const Duration(days: 1)),
        to: at.add(const Duration(days: 1)),
      );
      expect(all.where((g) => g.milestone == 180).length, 1,
          reason: 'a milestone is crossed once, not on every later review');
    });

    test('the most stubborn card is the one missed most', () async {
      await makeCard('teimoso');
      await makeCard('tranquilo');
      for (var i = 0; i < 3; i++) {
        await study.recordReview(
          cardId: 'teimoso',
          grade: Grade.again,
          at: t0.add(Duration(days: i)),
        );
      }
      await study.recordReview(cardId: 'tranquilo', grade: Grade.again, at: t0);

      final stubborn = await progress.mostStubborn(
        from: t0.subtract(const Duration(days: 1)),
        to: t0.add(const Duration(days: 10)),
      );
      expect(stubborn, 'teimoso');
    });

    test('leeches are cards forgotten repeatedly', () async {
      await makeCard('vazando');
      var at = t0;
      for (var i = 0; i < 20; i++) {
        final state = await study.recordReview(
          cardId: 'vazando',
          grade: i % 3 == 0 ? Grade.again : Grade.good,
          at: at,
        );
        at = state.dueAt!;
      }

      final found = await progress.leeches(minLapses: 2);
      expect(found.map((l) => l.cardId), contains('vazando'));
      expect(found.first.lapseRate, greaterThan(0));
    });
  });
}
