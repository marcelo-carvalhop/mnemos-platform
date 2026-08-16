@Tags(['live'])
library;

import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:authoring/authoring.dart';
import 'package:domain/domain.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:store/store.dart';
import 'package:sync_client/sync_client.dart';
import 'package:test/test.dart';

/// Against a running stack. Excluded from CI by its tag:
///
///     dart test --tags live --run-skipped
///
/// Everything else in this package is proved with a scripted transport. This
/// exists because the two halves of §6 were built separately, and the gap that
/// found — the server not saying which sequence each row got — was invisible
/// to both suites.
void main() {
  // Two in-memory databases in one process, each with its own executor: they
  // are two devices, which is the entire point of the test.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final baseUrl = Uri.parse(
    Platform.environment['API_BASE_URL'] ?? 'http://localhost:8000',
  );

  test('a real round trip empties the outbox and brings the rows back', () async {
    final tokens = MemoryTokenStore();
    final api = Api(baseUrl: baseUrl, tokens: tokens);
    final deviceId = Uuid7.generate();

    await AuthApi(api, tokens).registerDevice(deviceId: deviceId, platform: 'android');
    expect(await tokens.readAccess(), isNotNull);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final authoring = AuthoringService(db, deviceId: deviceId);
    final now = DateTime.now().toUtc();
    final deckId = await authoring.createDeck(name: 'Ida e volta', at: now);
    await authoring.createCard(
      deckId: deckId,
      front: 'O que prova este teste?',
      back: 'Que as duas metades do §6 concordam de verdade.',
      at: now,
    );

    final client = SyncClient(db, HttpSyncApi(api));
    expect(await client.outboxDepth(), greaterThan(0));

    await client.syncNow();

    // The whole point: without the per-row sequences this stays where it was.
    expect(await client.outboxDepth(), 0);

    // A second device, starting empty, must receive what the first wrote.
    final second = AppDatabase(NativeDatabase.memory());
    addTearDown(second.close);
    await SyncClient(second, HttpSyncApi(api)).syncNow();

    final decks = await second.select(second.decks).get();
    final cards = await second.select(second.cards).get();
    expect(decks.map((d) => d.name), contains('Ida e volta'));
    expect(cards.map((c) => c.front), contains('O que prova este teste?'));

    api.close();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
