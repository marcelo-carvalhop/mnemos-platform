import 'dart:io' show Platform;

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_client/sync_client.dart';

import 'providers.dart';
import 'sync/keychain_token_store.dart';
import 'sync/sync_controller.dart';

/// Composition for §6 and §8 (§4.4).

/// Overridden per flavour at build time. The default is the local stack, so a
/// fresh clone with `docker compose up` works without configuration.
///
/// 10.0.2.2 is how the Android emulator reaches the host; a physical device
/// needs the machine's LAN address, which is why this is a provider and not a
/// constant.
final apiBaseUrlProvider = Provider<Uri>((ref) {
  const fromEnvironment = String.fromEnvironment('API_BASE_URL');
  if (fromEnvironment.isNotEmpty) return Uri.parse(fromEnvironment);
  if (kDebugMode && Platform.isAndroid) return Uri.parse('http://10.0.2.2:8000');
  return Uri.parse('http://localhost:8000');
});

final tokenStoreProvider = Provider<TokenStore>((ref) => const KeychainTokenStore());

final apiProvider = Provider<Api>((ref) {
  final api = Api(
    baseUrl: ref.watch(apiBaseUrlProvider),
    tokens: ref.watch(tokenStoreProvider),
  );
  ref.onDispose(api.close);
  return api;
});

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(apiProvider), ref.watch(tokenStoreProvider)),
);

final accountApiProvider = Provider<AccountApi>((ref) => AccountApi(ref.watch(apiProvider)));

final generationApiProvider =
    Provider<GenerationApi>((ref) => GenerationApi(ref.watch(apiProvider)));

final terminalApiProvider =
    Provider<TerminalApi>((ref) => TerminalApi(ref.watch(apiProvider)));

final syncClientProvider = Provider<SyncClient>(
  (ref) => SyncClient(ref.watch(databaseProvider), HttpSyncApi(ref.watch(apiProvider))),
);

final syncControllerProvider = StateNotifierProvider<SyncController, SyncState>((ref) {
  final tokens = ref.watch(tokenStoreProvider);
  return SyncController(
    ref.watch(syncClientProvider),
    isSignedIn: () async => await tokens.readAccess() != null,
  );
});

/// §5.13's indicator. A cache of the server's answer, never the authority —
/// enforcement is server-side, and this is only what the button shows.
final quotaProvider = FutureProvider<({int remaining, int limit, String plan})>((ref) async {
  try {
    return await ref.watch(generationApiProvider).quota();
  } on Offline {
    // Offline, the honest answer is "we do not know", and the app must not
    // guess in the user's favour or against them.
    return (remaining: -1, limit: -1, plan: 'unknown');
  }
});

/// Gerações que ainda devem uma resposta (§7.8).
///
/// A tela de progresso promete que dá para sair e voltar. Este provider é o
/// que torna a promessa verdadeira: o servidor sabe o que está pendente, e o
/// app pergunta em vez de guardar um `jobId` local que some junto com o
/// aplicativo.
final openGenerationsProvider = FutureProvider<List<OpenGeneration>>((ref) async {
  try {
    return await ref.watch(generationApiProvider).open();
  } on Offline {
    // Offline não é erro. O aviso simplesmente não aparece.
    return const [];
  } on ApiException {
    return const [];
  }
});

/// First launch: an anonymous account bound to this device (§8.1).
///
/// Called once during bootstrap. It is allowed to fail — the whole app works
/// offline, and a device that cannot register yet simply syncs later.
Future<void> ensureRegistered(WidgetRef ref) async {
  final tokens = ref.read(tokenStoreProvider);
  if (await tokens.readAccess() != null) return;

  final deviceId = await ref.read(deviceIdProvider.future);
  final auth = ref.read(authApiProvider);

  try {
    // The attestation itself comes from the platform (Play Integrity /
    // App Attest) and is not wired yet — that needs a Play Console account
    // and a real device, which is a human gate. Until then the server runs
    // with REQUIRE_ATTESTATION off in development and refuses to boot in
    // production without it, so this cannot ship silently unattested.
    await auth.registerDevice(
      deviceId: deviceId,
      platform: Platform.isIOS ? 'ios' : 'android',
    );
  } on Offline {
    // Ordinary on a plane. Nothing is lost.
  } on ApiException {
    // Attestation refused, or the server is unhappy. Local study is
    // unaffected; the app will try again next launch.
  }
}
