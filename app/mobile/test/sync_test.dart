import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:drift/native.dart';
import 'package:flashcards/providers.dart';
import 'package:flashcards/sync/sync_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store/store.dart';
import 'package:sync_client/sync_client.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// The app's half of §6, at the seam where the packages meet.
///
/// `sync_client` proves the ordering and cursor rules and `api_client` proves
/// the transport; what is left is the behaviour the user actually feels —
/// that being offline costs nothing, and that nothing syncs twice at once.

/// A transport that can be told to fail, and counts what it was asked.
class ScriptedApi implements SyncApi {
  ScriptedApi();

  Object? failWith;
  int pushes = 0;
  int pulls = 0;
  int nextSeq = 1;

  @override
  Future<PushResult> push(
    String table,
    List<Map<String, Object?>> rows,
    String idempotencyKey,
  ) async {
    pushes++;
    if (failWith != null) throw failWith!;
    return PushResult(
      applied: rows.length,
      assignedSeqs: {
        for (final row in rows)
          (row[table == 'card_flags'
                  ? 'card_id'
                  : table == 'user_settings'
                      ? 'key'
                      : 'id']!)
              .toString(): nextSeq++,
      },
    );
  }

  @override
  Future<({List<Map<String, Object?>> rows, int cursor, bool hasMore})> pull(
    String table,
    int since,
    int limit,
  ) async {
    pulls++;
    if (failWith != null) throw failWith!;
    return (rows: <Map<String, Object?>>[], cursor: since, hasMore: false);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  late ScriptedApi api;
  late SyncClient client;
  final now = DateTime.utc(2026, 8, 9, 15);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedIfEmpty(db, 'test-device', now);
    api = ScriptedApi();
    client = SyncClient(db, api);
  });

  tearDown(() => db.close());

  SyncController controller({bool signedIn = true}) =>
      SyncController(client, isSignedIn: () async => signedIn);

  test('a first launch with no account does not talk to the server', () async {
    // Registering can fail, and a device that has not registered yet must not
    // spray 401s at a server it has no business calling.
    final sut = controller(signedIn: false);

    await sut.syncNow();

    expect(api.pushes, 0);
    expect(api.pulls, 0);
    // The count is still honest: the seeded rows are waiting.
    expect(sut.state.pending, greaterThan(0));
  });

  test('a successful sync empties the outbox', () async {
    final sut = controller();
    expect(await client.outboxDepth(), greaterThan(0));

    await sut.syncNow();

    expect(sut.state.phase, SyncPhase.idle);
    expect(sut.state.pending, 0, reason: 'the assigned sequences cleared it');
    expect(sut.state.lastSuccess, isNotNull);
  });

  test('offline costs nothing: the outbox is exactly where it was', () async {
    // §2.2 — the server is a backup and a meeting point, not the source of
    // truth. Losing the network must be uneventful.
    final before = await client.outboxDepth();
    api.failWith = const Offline('no route to host');
    final sut = controller();

    await sut.syncNow();

    expect(sut.state.phase, SyncPhase.offline);
    expect(sut.state.pending, before);
    expect(await db.select(db.decks).get(), isNotEmpty, reason: 'nothing was lost');
  });

  test('offline is not the failure state', () async {
    api.failWith = const Offline(SocketException('down'));
    final sut = controller();

    await sut.syncNow();

    expect(sut.state.phase, isNot(SyncPhase.failed));
  });

  test('a server error is transient, a rejection is not', () async {
    api.failWith = const ApiException(503);
    final transient = controller();
    await transient.syncNow();
    expect(transient.state.phase, SyncPhase.offline, reason: '503 is worth retrying');

    api.failWith = const ApiException(403, code: 'forbidden');
    final rejected = controller();
    await rejected.syncNow();
    expect(rejected.state.phase, SyncPhase.failed);
    expect(rejected.state.message, 'forbidden');
  });

  test('an unexpected failure is shown, not swallowed', () async {
    // Sync runs fire-and-forget, so anything that escapes the controller goes
    // nowhere. A pull that died on an unknown column did exactly that: the
    // badge reported nothing pending while the sync had stopped working.
    api.failWith = StateError('algo inesperado');
    final sut = controller();

    await sut.syncNow();

    expect(sut.state.phase, SyncPhase.failed);
    expect(sut.state.message, contains('inesperado'));
  });

  test('two callers at once produce one sync, not two', () async {
    // A session ending while a resume-triggered sync is still in flight is an
    // ordinary sequence of events, and doubling the pushes would double the
    // requests for no reason.
    final sut = controller();

    await Future.wait([sut.syncNow(), sut.syncNow(), sut.syncNow()]);

    // Seven tables, pushed once each, and only for tables holding rows.
    expect(api.pulls, kPullOrder.length, reason: 'one pass, not three');
  });

  test('a resync is reported rather than looking like a hang', () async {
    // §6.3 — the cursor predates the tombstone horizon and everything is
    // pulled again, which takes a moment.
    var thrown = false;
    api.failWith = null;
    final sut = SyncController(
      _ResyncOnce(db, api, onFirst: () => thrown = true),
      isSignedIn: () async => true,
    );

    await sut.syncNow();

    expect(thrown, isTrue);
    expect(sut.state.phase, SyncPhase.idle, reason: 'the second pass succeeded');
  });

  test('a count read while syncing does not overwrite the result', () async {
    // Both fire at the end of a session. Whichever finished second used to
    // win, and a count read before the push landed claimed changes were
    // waiting that the server already had — visible on a real device as
    // "4 mudanças para enviar" with all four already on the server.
    // The interleaving is forced rather than hoped for. On a device the
    // count's read is slow enough that a whole push finishes inside it; with
    // an in-memory fake it is not, and a test that relies on timing here
    // passes with the bug present — this one was written that way first, and
    // did.
    final gate = Completer<int>();
    final gated = _GatedDepth(client, gate.future);
    final sut = SyncController(gated, isSignedIn: () async => true);

    final counting = sut.refreshPending();
    await sut.syncNow();
    expect(sut.state.pending, 0, reason: 'the push cleared it');

    gate.complete(4);
    await counting;

    expect(sut.state.pending, 0, reason: 'a stale read must not put it back');
  });

  test('the pending count refreshes without touching the network', () async {
    final sut = controller();

    await sut.refreshPending();

    expect(api.pushes, 0);
    expect(api.pulls, 0);
    expect(sut.state.pending, greaterThan(0));
  });
}

/// Throws [ResyncRequired] the first time and then behaves.
class _ResyncOnce implements SyncClient {
  _ResyncOnce(this.db, this.api, {required this.onFirst});

  @override
  final AppDatabase db;
  @override
  final SyncApi api;
  final void Function() onFirst;
  bool _thrown = false;

  @override
  int get chunkSize => 200;

  @override
  Future<({int pushed, int pulled})> syncNow() async {
    if (!_thrown) {
      _thrown = true;
      onFirst();
      throw const ResyncRequired('cursor too old');
    }
    return (pushed: 0, pulled: 0);
  }

  @override
  Future<int> outboxDepth() async => 0;

  @override
  Future<int> cursorFor(String table) async => 0;

  @override
  Future<int> pushAll() async => 0;

  @override
  Future<int> pullAll() async => 0;
}


/// Holds `outboxDepth` open until the test says otherwise, so the ordering
/// that only happens over a real network can be reproduced exactly.
class _GatedDepth implements SyncClient {
  _GatedDepth(this._inner, this._gate);

  final SyncClient _inner;
  final Future<int> _gate;
  bool _first = true;

  @override
  Future<int> outboxDepth() {
    if (_first) {
      _first = false;
      return _gate;
    }
    return _inner.outboxDepth();
  }

  @override
  AppDatabase get db => _inner.db;
  @override
  SyncApi get api => _inner.api;
  @override
  int get chunkSize => _inner.chunkSize;
  @override
  Future<({int pushed, int pulled})> syncNow() => _inner.syncNow();
  @override
  Future<int> cursorFor(String table) => _inner.cursorFor(table);
  @override
  Future<int> pushAll() => _inner.pushAll();
  @override
  Future<int> pullAll() => _inner.pullAll();
}
