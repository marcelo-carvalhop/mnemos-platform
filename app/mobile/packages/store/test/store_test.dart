import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:store/store.dart';
import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tzdata;

late AppDatabase db;

int ms(DateTime t) => t.toUtc().millisecondsSinceEpoch;

Future<void> insertCard(
  String id, {
  String deck = 'd1',
  String front = 'frente',
  String back = 'verso',
}) async {
  await db.into(db.decks).insert(
        DecksCompanion.insert(
          id: deck,
          name: 'Baralho',
          updatedAt: 0,
          deviceId: 'dev',
        ),
        mode: InsertMode.insertOrIgnore,
      );
  await db.into(db.cards).insert(
        CardsCompanion.insert(
          id: id,
          deckId: deck,
          front: front,
          back: back,
          updatedAt: 0,
          deviceId: 'dev',
        ),
      );
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get(); // forces onCreate
  });

  tearDown(() async => db.close());

  group('append-only history (§5.2)', () {
    test('reviews reject UPDATE and DELETE', () async {
      await insertCard('c1');
      await db.into(db.reviews).insert(
            ReviewsCompanion.insert(
              id: 'r1',
              cardId: 'c1',
              reviewedAt: 1000,
              grade: 3,
              source: 'standard',
              deviceId: 'dev',
            ),
          );

      expect(
        () => db.customStatement("UPDATE reviews SET grade = 1 WHERE id = 'r1'"),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => db.customStatement("DELETE FROM reviews WHERE id = 'r1'"),
        throwsA(isA<SqliteException>()),
      );
    });

    test('progress_resets are immutable too', () async {
      await insertCard('c1');
      await db.into(db.progressResets).insert(
            ProgressResetsCompanion.insert(
              id: 'p1',
              cardId: 'c1',
              resetAt: 1000,
              deviceId: 'dev',
            ),
          );
      expect(
        () => db.customStatement("DELETE FROM progress_resets WHERE id = 'p1'"),
        throwsA(isA<SqliteException>()),
      );
    });

    test('sync bookkeeping may be written, historical facts may not', () async {
      // §6.4 — server_seq arrives after the fact and is how the client learns
      // the row was accepted. A blanket UPDATE ban would make the outbox
      // impossible to clear, so the trigger guards the event, not the row.
      await insertCard('c1');
      await db.into(db.reviews).insert(
            ReviewsCompanion.insert(
              id: 'r1',
              cardId: 'c1',
              reviewedAt: 1000,
              grade: 3,
              source: 'standard',
              deviceId: 'dev',
            ),
          );

      await db.customStatement("UPDATE reviews SET server_seq = 7 WHERE id = 'r1'");
      expect((await db.select(db.reviews).getSingle()).serverSeq, 7);

      for (final mutation in [
        "UPDATE reviews SET grade = 1 WHERE id = 'r1'",
        "UPDATE reviews SET reviewed_at = 2000 WHERE id = 'r1'",
        "UPDATE reviews SET card_id = 'outro' WHERE id = 'r1'",
        "UPDATE reviews SET source = 'multiple_choice' WHERE id = 'r1'",
      ]) {
        expect(
          () => db.customStatement(mutation),
          throwsA(isA<SqliteException>()),
          reason: mutation,
        );
      }
    });

    test('inserting more history is always allowed', () async {
      await insertCard('c1');
      for (var i = 0; i < 5; i++) {
        await db.into(db.reviews).insert(
              ReviewsCompanion.insert(
                id: 'r$i',
                cardId: 'c1',
                reviewedAt: 1000 + i,
                grade: 3,
                source: 'standard',
                deviceId: 'dev',
              ),
            );
      }
      expect((await db.select(db.reviews).get()).length, 5);
    });
  });

  group('search (§5.10)', () {
    test('finds accented words typed without accents', () async {
      // Without `remove_diacritics 2` this returns nothing and the feature
      // reads as broken to every Portuguese speaker.
      await insertCard('c1', front: 'O que é uma função?', back: 'Uma relação.');

      expect(await db.searchCardIds('funcao'), ['c1']);
      expect(await db.searchCardIds('função'), ['c1']);
      expect(await db.searchCardIds('relacao'), ['c1']);
    });

    test('searches the back as well as the front', () async {
      await insertCard('c1', front: 'Pergunta', back: 'Revolução Gloriosa');
      expect(await db.searchCardIds('gloriosa'), ['c1']);
    });

    test('an edited card is reindexed', () async {
      await insertCard('c1', front: 'antigo');
      await (db.update(db.cards)..where((t) => t.id.equals('c1')))
          .write(const CardsCompanion(front: Value('trocado')));

      expect(await db.searchCardIds('antigo'), isEmpty);
      expect(await db.searchCardIds('trocado'), ['c1']);
    });

    test('a deleted card leaves the index', () async {
      await insertCard('c1', front: 'sumindo');
      await (db.delete(db.cards)..where((t) => t.id.equals('c1'))).go();
      expect(await db.searchCardIds('sumindo'), isEmpty);
    });

    test('an empty query returns nothing rather than everything', () async {
      await insertCard('c1');
      expect(await db.searchCardIds('   '), isEmpty);
    });
  });

  group("today's queue (§5.8)", () {
    final now = DateTime.utc(2026, 8, 9, 12);

    Future<void> giveState(String cardId, {required DateTime due, bool dirty = false}) {
      return db.into(db.cardStates).insert(
            CardStatesCompanion.insert(
              cardId: cardId,
              dueAt: Value(ms(due)),
              dirty: Value(dirty),
            ),
          );
    }

    test('returns cards that are due', () async {
      await insertCard('c1');
      await giveState('c1', due: now.subtract(const Duration(hours: 1)));
      expect(await db.dueCardIds(now), ['c1']);
    });

    test('skips cards not yet due', () async {
      await insertCard('c1');
      await giveState('c1', due: now.add(const Duration(days: 1)));
      expect(await db.dueCardIds(now), isEmpty);
    });

    test('skips suspended cards (§4)', () async {
      await insertCard('c1');
      await giveState('c1', due: now.subtract(const Duration(hours: 1)));
      await db.into(db.cardFlags).insert(
            CardFlagsCompanion.insert(
              cardId: 'c1',
              status: const Value('suspended'),
              updatedAt: 0,
              deviceId: 'dev',
            ),
          );
      expect(await db.dueCardIds(now), isEmpty);
    });

    test('skips a card still buried, and returns it once the burial lapses', () async {
      await insertCard('c1');
      await giveState('c1', due: now.subtract(const Duration(hours: 1)));
      await db.into(db.cardFlags).insert(
            CardFlagsCompanion.insert(
              cardId: 'c1',
              buriedUntil: Value(ms(now.add(const Duration(hours: 6)))),
              updatedAt: 0,
              deviceId: 'dev',
            ),
          );

      expect(await db.dueCardIds(now), isEmpty);
      expect(await db.dueCardIds(now.add(const Duration(hours: 7))), ['c1']);
    });

    test('skips a dirty card rather than scheduling from a stale state', () async {
      // §5.3 — a card awaiting full replay has no trustworthy due date.
      await insertCard('c1');
      await giveState('c1', due: now.subtract(const Duration(hours: 1)), dirty: true);
      expect(await db.dueCardIds(now), isEmpty);
    });

    test('skips deleted cards', () async {
      await insertCard('c1');
      await giveState('c1', due: now.subtract(const Duration(hours: 1)));
      await (db.update(db.cards)..where((t) => t.id.equals('c1')))
          .write(CardsCompanion(deletedAt: Value(ms(now))));
      expect(await db.dueCardIds(now), isEmpty);
    });

    test('orders by how overdue the card is', () async {
      await insertCard('c1');
      await insertCard('c2');
      await giveState('c1', due: now.subtract(const Duration(hours: 1)));
      await giveState('c2', due: now.subtract(const Duration(days: 3)));
      expect(await db.dueCardIds(now), ['c2', 'c1']);
    });
  });

  group('day bucketing (§5.7)', () {
    const sp = DayBucket(timezoneName: 'America/Sao_Paulo');

    test('studying at 01:00 still counts as the previous day', () async {
      // The whole reason for a 04:00 cutoff: midnight would break the streak
      // of exactly the people who study late.
      final lateNight = DateTime.utc(2026, 8, 10, 4, 0); // 01:00 in SP
      expect(sp.keyFor(lateNight), '2026-08-09');
    });

    test('studying at 05:00 counts as the new day', () async {
      final morning = DateTime.utc(2026, 8, 10, 8, 0); // 05:00 in SP
      expect(sp.keyFor(morning), '2026-08-10');
    });

    test('the cutoff itself starts the new day', () async {
      final exactly = DateTime.utc(2026, 8, 10, 7, 0); // 04:00 in SP
      expect(sp.keyFor(exactly), '2026-08-10');
    });

    test('the timezone is the stored one, not the device', () async {
      // Same instant, two accounts: the bucket follows the setting. Reading the
      // device would rewrite the heatmap when the user travels.
      final instant = DateTime.utc(2026, 8, 10, 6, 0);
      const lisbon = DayBucket(timezoneName: 'Europe/Lisbon');
      expect(sp.keyFor(instant), isNot(lisbon.keyFor(instant)));
    });

    test('a range covers exactly its own day', () async {
      final (start, end) = sp.rangeOf('2026-08-09');
      expect(sp.keyFor(start), '2026-08-09');
      expect(sp.keyFor(end), '2026-08-10');
      expect(sp.keyFor(end.subtract(const Duration(milliseconds: 1))), '2026-08-09');
    });

    test('a DST transition gives a short day, not a shifted boundary', () async {
      // Lisbon springs forward at 01:00 on 2026-03-29 — before the 04:00
      // cutoff, so the *short* day is the 28th: it starts at 04:00 WET and
      // ends at 04:00 WEST, 23 hours later. Adding 24 hours to the start would
      // move the boundary into the previous day; adding a day to the key does
      // not.
      const lisbon = DayBucket(timezoneName: 'Europe/Lisbon');
      final (start, end) = lisbon.rangeOf('2026-03-28');

      expect(lisbon.keyFor(start), '2026-03-28');
      expect(lisbon.keyFor(end), '2026-03-29');
      expect(end.difference(start), const Duration(hours: 23));
    });

    test('an autumn transition gives a long day', () async {
      // The mirror case: Lisbon falls back on 2026-10-25, so that day is 25
      // hours. Both directions matter — a fixed 24-hour arithmetic breaks one
      // of them whichever way it is written.
      const lisbon = DayBucket(timezoneName: 'Europe/Lisbon');
      final (start, end) = lisbon.rangeOf('2026-10-24');
      expect(end.difference(start), const Duration(hours: 25));
    });

    test('endOfDay is when a burial lapses (§4)', () async {
      final buried = DateTime.utc(2026, 8, 9, 20); // 17:00 in SP
      expect(sp.keyFor(sp.endOfDay(buried)), '2026-08-10');
    });
  });
}
