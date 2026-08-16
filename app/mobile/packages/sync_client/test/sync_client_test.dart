import 'package:drift/native.dart';
import 'package:store/store.dart' hide CardState;
import 'package:sync_client/sync_client.dart';
import 'package:test/test.dart';

/// A server that behaves like §6 says the real one does: it assigns the
/// sequence, merges history by union and entities by last-writer-wins.
///
/// The interesting failures in this loop are ordering and idempotency, not
/// HTTP, so the fake keeps those semantics and drops the transport.
class FakeServer implements SyncApi {
  final Map<String, Map<String, Map<String, Object?>>> tables = {};
  final List<String> pushOrder = [];
  final Set<String> seenKeys = {};
  int _seq = 0;

  /// Set to make the next pull raise §6.3's forced resync.
  bool demandResync = false;

  int get seq => _seq;

  @override
  Future<PushResult> push(
    String table,
    List<Map<String, Object?>> rows,
    String idempotencyKey,
  ) async {
    pushOrder.add(table);

    if (!seenKeys.add(idempotencyKey)) {
      // A replay: acknowledge what is already stored, insert nothing.
      final store = tables[table] ?? {};
      return PushResult(
        applied: 0,
        assignedSeqs: {
          for (final row in rows)
            if (store.containsKey(_key(table, row)))
              _key(table, row): store[_key(table, row)]!['server_seq'] as int,
        },
      );
    }

    final store = tables.putIfAbsent(table, () => {});
    final assigned = <String, int>{};
    var applied = 0;

    for (final row in rows) {
      final id = _key(table, row);
      final isHistory =
          table == 'reviews' || table == 'progress_resets' || table == 'goal_history';

      if (store.containsKey(id)) {
        if (isHistory) {
          assigned[id] = store[id]!['server_seq'] as int;
          continue; // union: never overwritten
        }
        final incoming = row['updated_at'] as int;
        final current = store[id]!['updated_at'] as int;
        if (incoming < current) {
          assigned[id] = store[id]!['server_seq'] as int;
          continue; // stale
        }
      }

      _seq++;
      store[id] = {...row, 'server_seq': _seq};
      assigned[id] = _seq;
      applied++;
    }

    return PushResult(applied: applied, assignedSeqs: assigned);
  }

  @override
  Future<({List<Map<String, Object?>> rows, int cursor, bool hasMore})> pull(
    String table,
    int since,
    int limit,
  ) async {
    if (demandResync && since > 0) {
      throw const ResyncRequired('cursor predates the tombstone horizon');
    }

    final rows = (tables[table] ?? {})
        .values
        .where((r) => (r['server_seq'] as int) > since)
        .toList()
      ..sort((a, b) => (a['server_seq'] as int).compareTo(b['server_seq'] as int));

    final page = rows.take(limit).toList();
    return (
      rows: page,
      cursor: page.isEmpty ? since : page.last['server_seq'] as int,
      hasMore: rows.length > limit,
    );
  }

  String _key(String table, Map<String, Object?> row) => switch (table) {
        'card_flags' => row['card_id'] as String,
        'user_settings' => row['key'] as String,
        _ => row['id'] as String,
      };
}

late AppDatabase db;
late FakeServer server;
late SyncClient sync;

Future<void> makeDeck(String id, {int at = 1000, String device = 'phone'}) =>
    db.customStatement(
      "INSERT INTO decks (id, name, version, origin, updated_at, device_id) "
      "VALUES ('$id', 'Baralho', 1, 'own', $at, '$device')",
    );

Future<void> makeCard(String id, String deck, {int at = 1000, String front = 'f'}) =>
    db.customStatement(
      "INSERT INTO cards (id, deck_id, front, back, tags, updated_at, device_id) "
      "VALUES ('$id', '$deck', '$front', 'v', '[]', $at, 'phone')",
    );

void main() {
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    server = FakeServer();
    sync = SyncClient(db, server);
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async => db.close());

  group('push (§6.4)', () {
    test('a deck goes before the card that references it', () async {
      // The other order makes the server reject the card for a deck it has
      // never seen.
      await makeDeck('d1');
      await makeCard('c1', 'd1');
      await sync.pushAll();

      expect(
        server.pushOrder.indexOf('decks'),
        lessThan(server.pushOrder.indexOf('cards')),
      );
    });

    test('history is pushed after the cards it points at', () async {
      await makeDeck('d1');
      await makeCard('c1', 'd1');
      await db.customStatement(
        "INSERT INTO reviews (id, card_id, reviewed_at, grade, source, device_id) "
        "VALUES ('r1', 'c1', 2000, 3, 'standard', 'phone')",
      );
      await sync.pushAll();

      expect(
        server.pushOrder.indexOf('cards'),
        lessThan(server.pushOrder.indexOf('reviews')),
      );
    });

    test('acknowledged rows leave the outbox', () async {
      await makeDeck('d1');
      await makeCard('c1', 'd1');
      expect(await sync.outboxDepth(), 2);

      await sync.pushAll();
      expect(await sync.outboxDepth(), 0);
    });

    test('a replayed push inserts nothing and is not an error', () async {
      await makeDeck('d1');
      await sync.pushAll();

      // Force the rows back into the outbox, as a lost response would.
      await db.customStatement('UPDATE decks SET server_seq = NULL');
      await sync.pushAll();

      expect(server.tables['decks']!.length, 1);
      expect(await sync.outboxDepth(), 0, reason: 'the retry still acknowledges');
    });

    test('ten offline edits are one push, not ten', () async {
      // Coalescing is free because the outbox is the row itself: it carries
      // its current state rather than a log of intermediate edits.
      await makeDeck('d1');
      for (var i = 0; i < 10; i++) {
        await db.customStatement("UPDATE decks SET name = 'v$i', updated_at = ${2000 + i}");
      }
      await sync.pushAll();

      expect(server.tables['decks']!.length, 1);
      expect(server.tables['decks']!['d1']!['name'], 'v9');
    });

    test('nothing to push is not a request', () async {
      await sync.pushAll();
      expect(server.pushOrder, isEmpty);
    });
  });

  group('pull (§6.1, §6.2)', () {
    test('a row from another device lands locally', () async {
      server.tables['decks'] = {
        'remote': {
          'id': 'remote',
          'name': 'De outro aparelho',
          'version': 1,
          'origin': 'own',
          'updated_at': 5000,
          'device_id': 'tablet',
          'server_seq': 1,
        }
      };
      server._seq = 1;

      expect(await sync.pullAll(), 1);
      final row = await db.select(db.decks).getSingle();
      expect(row.name, 'De outro aparelho');
    });

    test('a pulled row does not re-enter the outbox', () async {
      // It already has a server_seq, which is exactly what the outbox tests
      // for.
      server.tables['decks'] = {
        'remote': {
          'id': 'remote',
          'name': 'B',
          'version': 1,
          'origin': 'own',
          'updated_at': 5000,
          'device_id': 'tablet',
          'server_seq': 1,
        }
      };
      server._seq = 1;

      await sync.pullAll();
      expect(await sync.outboxDepth(), 0);
    });

    test('the cursor advances so the next pull is a delta', () async {
      server.tables['decks'] = {
        'a': {
          'id': 'a',
          'name': 'A',
          'version': 1,
          'origin': 'own',
          'updated_at': 1,
          'device_id': 'tablet',
          'server_seq': 1,
        }
      };
      server._seq = 1;

      await sync.pullAll();
      expect(await sync.cursorFor('decks'), 1);
      expect(await sync.pullAll(), 0, reason: 'nothing new to fetch');
    });

    test('a newer remote edit wins', () async {
      await makeDeck('d1', at: 1000);
      await sync.pushAll();

      server.tables['decks']!['d1'] = {
        ...server.tables['decks']!['d1']!,
        'name': 'Renomeado no tablet',
        'updated_at': 9000,
        'device_id': 'tablet',
        'server_seq': 99,
      };
      server._seq = 99;
      await db.delete(db.syncState).go();

      await sync.pullAll();
      expect((await db.select(db.decks).getSingle()).name, 'Renomeado no tablet');
    });

    test('a stale remote edit is ignored', () async {
      // Both sides evaluate the same rule, so they converge rather than
      // trusting whoever spoke last.
      await makeDeck('d1', at: 9000);
      await sync.pushAll();

      server.tables['decks']!['d1'] = {
        ...server.tables['decks']!['d1']!,
        'name': 'Antigo',
        'updated_at': 1000,
        'device_id': 'tablet',
        'server_seq': 99,
      };
      server._seq = 99;
      await db.delete(db.syncState).go();

      await sync.pullAll();
      expect((await db.select(db.decks).getSingle()).name, 'Baralho');
    });

    test('history merges by union and never overwrites', () async {
      await makeDeck('d1');
      await makeCard('c1', 'd1');
      await db.customStatement(
        "INSERT INTO reviews (id, card_id, reviewed_at, grade, source, device_id) "
        "VALUES ('r1', 'c1', 2000, 3, 'standard', 'phone')",
      );
      await sync.pushAll();
      await db.delete(db.syncState).go();

      // The server hands the same review back with a different grade; the
      // local row must not change, because history is append-only (§3).
      server.tables['reviews']!['r1'] = {
        ...server.tables['reviews']!['r1']!,
        'grade': 1,
      };

      await sync.pullAll();
      expect((await db.select(db.reviews).getSingle()).grade, 3);
    });
  });

  group('forced resync (§6.3)', () {
    test('a cursor past the horizon rebuilds from zero without losing local work',
        () async {
      await makeDeck('d1');
      await sync.pushAll();
      await sync.pullAll();
      expect(await sync.cursorFor('decks'), greaterThan(0));

      // A deck created while offline, still unpushed.
      await makeDeck('offline', at: 7000);
      server.demandResync = true;

      await sync.pullAll();

      expect(
        server.tables['decks']!.containsKey('offline'),
        isTrue,
        reason: 'the outbox is pushed before the mirror is discarded',
      );
      expect(await sync.outboxDepth(), 0);
    });
  });

  group('syncNow', () {
    test('pushes before pulling, and its own row coming back is harmless', () async {
      // The cursor is still 0 after a first push, so the row does come back.
      // That is correct and self-limiting: advancing the cursor to the seq the
      // server just assigned would skip anything another device wrote at a
      // lower seq, which is a much worse failure than one redundant row.
      //
      // What has to hold is that the round trip changes nothing.
      await makeDeck('d1', at: 1000);
      final result = await sync.syncNow();

      expect(result.pushed, 1);

      final row = await db.select(db.decks).getSingle();
      expect(row.updatedAt, 1000, reason: 'the echo must not overwrite');
      expect(row.serverSeq, isNotNull);
      expect(await sync.outboxDepth(), 0, reason: 'and must not re-queue it');

      // The cursor has advanced, so the next sync is quiet.
      expect((await sync.syncNow()).pulled, 0);
    });

    test('two devices converge', () async {
      await makeDeck('do-phone', at: 1000);
      await sync.pushAll();

      // A second device with its own database, same server.
      final other = AppDatabase(NativeDatabase.memory());
      final otherSync = SyncClient(other, server);
      await other.customSelect('SELECT 1').get();
      await other.customStatement(
        "INSERT INTO decks (id, name, version, origin, updated_at, device_id) "
        "VALUES ('do-tablet', 'B', 1, 'own', 2000, 'tablet')",
      );

      await otherSync.syncNow();
      await sync.syncNow();

      final here = (await db.select(db.decks).get()).map((d) => d.id).toSet();
      final there = (await other.select(other.decks).get()).map((d) => d.id).toSet();
      expect(here, there);
      expect(here, {'do-phone', 'do-tablet'});

      await other.close();
    });
  });

  // -------------------------------------------------------------------------
  // A client several versions behind (§5.3)
  // -------------------------------------------------------------------------

  test('a column this build has never heard of is ignored, not fatal', () async {
    // §5.3 — schema changes are additive and devices run months behind, so
    // the server routinely sends fields a client does not know. Passing them
    // into an INSERT throws inside a background sync, where nothing sees it:
    // on a real device the pull of `reviews` died on `scheduler_version` and
    // the only trace was a line in logcat.
    const deck = 'deck-do-futuro';
    server.tables['decks'] = {
      deck: {
        'id': deck,
        'name': 'Do futuro',
        'updated_at': 1,
        'device_id': 'outro',
        'server_seq': 1,
        'origin': 'own',
        'version': 1,
        'uma_coluna_que_ainda_nao_existe': 'ignore-me',
      }
    };

    await sync.pullAll();

    final rows = await db.select(db.decks).get();
    expect(rows.map((d) => d.name), contains('Do futuro'));
  });

  test('the row still arrives complete apart from what was unknown', () async {
    const deck = 'deck-parcial';
    const card = 'card-parcial';
    server.tables['decks'] = {
      deck: {
        'id': deck,
        'name': 'Baralho',
        'updated_at': 1,
        'device_id': 'outro',
        'server_seq': 1,
        'origin': 'own',
        'version': 1,
      }
    };
    server.tables['cards'] = {
      card: {
        'id': card,
        'deck_id': deck,
        'front': 'Frente',
        'back': 'Verso',
        'updated_at': 2,
        'device_id': 'outro',
        'server_seq': 2,
        'tags': '[]',
        'campo_desconhecido': 42,
      }
    };

    await sync.pullAll();

    final row = await (db.select(db.cards)..where((t) => t.id.equals(card))).getSingle();
    expect(row.front, 'Frente');
    expect(row.serverSeq, 2);
  });
}