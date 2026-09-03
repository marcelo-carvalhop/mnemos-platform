import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:authoring/authoring.dart';
import 'package:domain/domain.dart';
import 'package:drift/native.dart';
import 'package:flashcards/device/terminal_local_store.dart';
import 'package:flashcards/notifications.dart';
import 'package:flashcards/providers.dart';
import 'package:flashcards/providers_sync.dart';
import 'package:flashcards/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scheduler/scheduler.dart';
import 'package:session/session.dart';
import 'package:store/store.dart';
import 'package:timezone/timezone.dart' as tz;

/// Where the PNGs land, relative to this directory.
const outDir = '../../../screenshots/mobile';

/// A mid-range phone in logical pixels; the PNG comes out at 2x this.
const surface = Size(400, 880);
const pixelRatio = 2.0;

/// Pinned so every run produces the same dates, counts and intervals.
final fixedNow = DateTime.utc(2026, 8, 31, 18);
const seedDeviceId = 'screenshot-device';

// ---------------------------------------------------------------------------
// Fonts
// ---------------------------------------------------------------------------

/// `flutter test` ships no glyphs, so text would render as empty boxes.
/// Roboto and the Material icon font are in the SDK cache; load them so the
/// screenshots show the real interface rather than its silhouette.
Future<void> loadRealFonts() async {
  final root = _flutterRoot();
  if (root == null) return;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;

  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    var added = 0;
    for (final name in files) {
      final file = File('${dir.path}/$name');
      if (!file.existsSync()) continue;
      added++;
      loader.addFont(
        file.readAsBytes().then((b) => ByteData.view(Uint8List.fromList(b).buffer)),
      );
    }
    if (added > 0) await loader.load();
  }

  await load('Roboto', const [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-light.ttf',
    'roboto-italic.ttf',
  ]);
  await load('MaterialIcons', const ['materialicons-regular.otf']);

  await _loadBundledFonts();
}

/// As três famílias do design, lidas de `assets/fonts/`.
///
/// Declarar em `pubspec.yaml` basta para o aplicativo, mas não para o
/// `flutter test`: o binding de teste não monta o manifesto de fontes do
/// bundle, então sem isto os títulos saem como tarjas pretas — que foi
/// exatamente o que a primeira rodada de capturas mostrou.
Future<void> _loadBundledFonts() async {
  final dir = Directory('assets/fonts');
  if (!dir.existsSync()) return;

  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    var added = 0;
    for (final file in files) {
      final f = File('${dir.path}/$file');
      if (!f.existsSync()) continue;
      added++;
      loader.addFont(
        f.readAsBytes().then((b) => ByteData.view(Uint8List.fromList(b).buffer)),
      );
    }
    if (added > 0) await loader.load();
  }

  await family('Literata', const [
    'Literata-Regular.ttf',
    'Literata-SemiBold.ttf',
  ]);
  await family('Public Sans', const [
    'PublicSans-Regular.ttf',
    'PublicSans-Medium.ttf',
    'PublicSans-SemiBold.ttf',
  ]);
  await family('JetBrains Mono', const [
    'JetBrainsMono-Regular.ttf',
    'JetBrainsMono-Medium.ttf',
  ]);
}

String? _flutterRoot() {
  final fromEnv = Platform.environment['FLUTTER_ROOT'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  // <flutter>/bin/cache/dart-sdk/bin/dart(.exe)
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 4; i++) {
    dir = dir.parent;
  }
  return dir.existsSync() ? dir.path : null;
}

// ---------------------------------------------------------------------------
// Fakes for everything that is not the interface
// ---------------------------------------------------------------------------

/// Signed in, without touching the platform keychain.
class FakeTokenStore implements TokenStore {
  @override
  Future<String?> readAccess() async => 'screenshot-access-token';
  @override
  Future<String?> readRefresh() async => 'screenshot-refresh-token';
  @override
  Future<void> write({required String access, required String refresh}) async {}
  @override
  Future<void> clear() async {}
}

/// The notification plugin does not exist in a test binding.
class SilentReminderSink implements ReminderSink {
  @override
  Future<void> initialise() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime at,
  }) async {}
}

/// A backend that always answers, so the screens show their populated state
/// instead of their offline one.
http.Client mockBackend({
  ({int remaining, int limit, String plan}) quota = (remaining: 1, limit: 1, plan: 'free'),
  Map<String, Object?>? job,
  Map<String, Object?>? approvalQueue,
  Map<String, Object?>? terminalSummary,
}) {
  return MockClient((request) async {
    final path = request.url.path;
    Map<String, Object?>? body;

    if (path.startsWith('/v1/quota')) {
      body = {'remaining': quota.remaining, 'limit': quota.limit, 'plan': quota.plan};
    } else if (path.endsWith('/queue')) {
      body = approvalQueue;
    } else if (path.startsWith('/v1/generation/jobs/')) {
      body = job;
    } else if (path.endsWith('/summary')) {
      body = terminalSummary;
    }

    if (body == null) return http.Response('{"detail":"not mocked"}', 404);
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

List<Override> appOverrides({
  required AppDatabase db,
  DateTime? now,
  http.Client? backend,
}) {
  final tokens = FakeTokenStore();
  return [
    databaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(() => now ?? fixedNow),
    tokenStoreProvider.overrideWithValue(tokens),
    remindersProvider.overrideWithValue(StudyReminders(SilentReminderSink())),
    if (backend != null)
      apiProvider.overrideWith(
        (ref) => Api(
          baseUrl: Uri.parse('http://localhost:8000'),
          tokens: tokens,
          client: backend,
        ),
      ),
  ];
}

// ---------------------------------------------------------------------------
// Seed data
// ---------------------------------------------------------------------------

const redesDeck = 'Redes de Computadores';
const direitoDeck = 'Direito Constitucional';

const _direitoCards = [
  (
    'O que são cláusulas pétreas?',
    'Núcleos da Constituição que não podem ser abolidos por emenda: a forma federativa de Estado, o voto direto secreto universal e periódico, a separação dos Poderes e os direitos e garantias individuais.',
  ),
  (
    'Qual a diferença entre controle difuso e concentrado de constitucionalidade?',
    'No difuso, qualquer juiz aprecia a constitucionalidade no caso concreto, com efeitos entre as partes; no concentrado, o STF julga a lei em tese, com efeito erga omnes.',
  ),
  (
    'O que é o princípio da reserva legal?',
    'A exigência de que determinadas matérias só possam ser disciplinadas por lei em sentido formal, editada pelo Poder Legislativo.',
  ),
  (
    'Quem pode propor ação direta de inconstitucionalidade?',
    'Os legitimados do art. 103 da Constituição, entre eles o Presidente da República, as Mesas do Senado e da Câmara, o Procurador-Geral da República, o Conselho Federal da OAB e os partidos políticos com representação no Congresso.',
  ),
  (
    'O que significa o princípio da anterioridade tributária?',
    'A vedação de cobrar tributo no mesmo exercício financeiro em que foi publicada a lei que o instituiu ou aumentou.',
  ),
  (
    'O que é habeas data?',
    'Remédio constitucional para assegurar o conhecimento ou a retificação de informações relativas à pessoa do impetrante constantes de registros de entidades governamentais ou de caráter público.',
  ),
];

/// A database that looks like it has been in use for three weeks: two decks,
/// sixteen cards and a review log with a streak, a couple of missed days and
/// a realistic mix of grades.
Future<AppDatabase> seedDatabase({bool withHistory = true}) async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.customSelect('SELECT 1').get();

  await seedIfEmpty(db, seedDeviceId, fixedNow.subtract(const Duration(days: 21)));

  final authoring = AuthoringService(db, deviceId: seedDeviceId);
  final direitoId = await authoring.createDeck(
    name: direitoDeck,
    at: fixedNow.subtract(const Duration(days: 12)),
  );
  for (final (front, back) in _direitoCards) {
    await authoring.createCard(
      deckId: direitoId,
      front: front,
      back: back,
      at: fixedNow.subtract(const Duration(days: 12)),
    );
  }

  if (!withHistory) return db;

  final study = StudyService(
    db,
    deviceId: seedDeviceId,
    params: const FsrsParams(weights: defaultFsrsWeights),
  );

  final cards = await db.select(db.cards).get();
  var seed = 20260831;
  int next(int mod) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed % mod;
  }

  // Two gaps, so the heatmap is a record rather than a wall of green and the
  // streak is a real number.
  const missed = {13, 8};
  for (var daysAgo = 20; daysAgo >= 0; daysAgo--) {
    if (missed.contains(daysAgo)) continue;
    final at = fixedNow.subtract(Duration(days: daysAgo)).add(const Duration(hours: 2));
    final count = 21 + next(12);
    for (var i = 0; i < count; i++) {
      final roll = next(100);
      final grade = roll < 12
          ? Grade.again
          : roll < 30
              ? Grade.hard
              : roll < 88
                  ? Grade.good
                  : Grade.easy;
      await study.recordReview(
        cardId: cards[next(cards.length)].id,
        grade: grade,
        at: at.add(Duration(minutes: i * 3)),
      );
    }
  }

  return db;
}

/// The deck the screens that take one are pointed at.
Future<({String id, String name})> firstDeck(AppDatabase db) async {
  final decks = await db.select(db.decks).get();
  final deck = decks.firstWhere((d) => d.name == redesDeck, orElse: () => decks.first);
  return (id: deck.id, name: deck.name);
}

// ---------------------------------------------------------------------------
// Capture
// ---------------------------------------------------------------------------

/// The app's own theme, with a font family named where the theme installs a
/// `DefaultTextStyle` outright instead of merging into one.
///
/// On a phone those styles inherit the platform font and look right. A test
/// binding has no platform font, so they fall through to the glyph-less test
/// font and render as black boxes — which would be a screenshot of the
/// harness rather than of the app.
ThemeData screenshotTheme() {
  final base = buildTheme();
  const family = 'Roboto';

  return base.copyWith(
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle:
          (base.appBarTheme.titleTextStyle ?? const TextStyle()).copyWith(fontFamily: family),
      toolbarTextStyle: base.appBarTheme.toolbarTextStyle?.copyWith(fontFamily: family),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll(
          base.filledButtonTheme.style?.textStyle?.resolve({})?.copyWith(fontFamily: family),
        ),
      ),
    ),
  );
}

/// Renders [home] and writes `<outDir>/<name>.png`.
///
/// `settle` is false for the screens that poll or animate forever — there the
/// frame is pumped a fixed number of times instead of waiting for quiescence.
Future<void> shoot(
  WidgetTester tester,
  String name,
  Widget home, {
  required List<Override> overrides,
  bool settle = true,
  Future<void> Function(WidgetTester tester)? act,
}) async {
  tester.view.physicalSize = surface * pixelRatio;
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: screenshotTheme(),
        home: home,
      ),
    ),
  );

  await rest(tester, settle: settle);
  if (act != null) {
    await act(tester);
    await rest(tester, settle: settle);
  }

  await expectLater(find.byType(MaterialApp), matchesGoldenFile('$outDir/$name.png'));

  // Unmount before the test ends: the polling screens hold a periodic timer
  // that only their dispose cancels.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> rest(WidgetTester tester, {required bool settle}) async {
  if (settle) {
    await tester.pumpAndSettle();
    return;
  }
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

// ---------------------------------------------------------------------------
// Fixtures compartilhadas pelas telas de terminal e de geração
// ---------------------------------------------------------------------------

const fixtureTerminalId = 'mnemos-t5-0a3f';

/// Guarda um terminal pareado, para as telas que só existem com um.
Future<String> storeTerminal(AppDatabase db) async {
  final store = TerminalLocalStore(db);
  await store.saveTerminal(
    StoredTerminal(
      deviceId: fixtureTerminalId,
      model: 'Mnemos T5',
      firmware: '0.5.0',
      protocol: 3,
      maxCards: 400,
      bleSync: true,
      lastSeenAt: fixedNow.subtract(const Duration(hours: 4)),
    ),
  );
  await store.setActiveDevice(fixtureTerminalId);
  await store.markSync(fixtureTerminalId, sentCards: 10, receivedReviews: 4);
  return fixtureTerminalId;
}

/// A resposta do backend para esse terminal.
Map<String, Object?> terminalSummary(String deviceId, List<String> deckIds) => {
      'device_id': deviceId,
      'model': 'Mnemos T5',
      'firmware': '0.5.0',
      'desired_deck_ids': deckIds,
      'reported_deck_ids': deckIds,
      'card_count': 10,
      'max_cards': 400,
      'revoked': false,
      'last_seen_at': '2026-08-31T14:02:00Z',
      'last_sync_at': '2026-08-31T14:02:00Z',
      'connectivity': 'wifi',
      'wifi_ssid': 'casa-2g',
    };

/// Uma fila de aprovação com cards plausíveis.
const approvalQueue = <String, Object?>{
  'decided': 2,
  'total': 8,
  'cards': [
    {
      'id': 'pending-1',
      'front': 'O que o controle de congestionamento do TCP tenta evitar?',
      'back': 'Que o emissor injete mais tráfego do que a rede consegue escoar, '
          'causando fila, perda de pacotes e colapso de throughput.',
      'tags': ['tcp', 'transporte'],
      'position': 0,
    },
    {
      'id': 'pending-2',
      'front': 'Qual a diferença entre latência e largura de banda?',
      'back': 'Latência é o tempo que um bit leva para atravessar o enlace; '
          'largura de banda é quantos bits o enlace transporta por segundo.',
      'tags': ['redes'],
      'position': 1,
    },
    {
      'id': 'pending-3',
      'front': 'Para que serve o campo checksum do cabeçalho UDP?',
      'back': 'Para detectar corrupção do datagrama em trânsito.',
      'tags': ['udp'],
      'position': 2,
    },
  ],
};
