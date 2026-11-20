import 'package:authoring/authoring.dart';
import 'package:domain/domain.dart';
import 'package:scheduler/scheduler.dart';
import 'package:session/session.dart';
import 'package:store/store.dart';

import 'providers.dart';

/// `--dart-define=SEED_DEMO=true`: a install that looks like three weeks of use.
///
/// Mirrors `test_screenshots/harness.dart` (two decks, sixteen cards, a review
/// log with a streak, two missed days and a realistic grade mix), but dated
/// relative to the real clock so the home screen shows a live day. Off by
/// default; a build without the define never touches this.
const kSeedDemo = bool.fromEnvironment('SEED_DEMO');

Future<void>? _running;

/// Idempotent and safe to call on every bootstrap rebuild: only an install
/// with no decks is seeded, and concurrent calls share one run.
Future<void> seedDemoIfEmpty(AppDatabase db, String deviceId, DateTime now) =>
    _running ??= _seed(db, deviceId, now);

Future<void> _seed(AppDatabase db, String deviceId, DateTime now) async {
  if ((await db.select(db.decks).get()).isNotEmpty) return;

  // Deck "Redes de Computadores", the daily goal and the timezone — what
  // onboarding would have written.
  await seedIfEmpty(db, deviceId, now.subtract(const Duration(days: 21)));

  final authoring = AuthoringService(db, deviceId: deviceId);
  final created = now.subtract(const Duration(days: 12));
  final direitoId = await authoring.createDeck(name: 'Direito Constitucional', at: created);
  for (final (front, back) in _direitoCards) {
    await authoring.createCard(deckId: direitoId, front: front, back: back, at: created);
  }

  final study = StudyService(
    db,
    deviceId: deviceId,
    params: const FsrsParams(weights: defaultFsrsWeights),
  );

  final cards = await db.select(db.cards).get();
  var seed = 20260831;
  int next(int mod) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed % mod;
  }

  Grade grade() {
    final roll = next(100);
    return roll < 12
        ? Grade.again
        : roll < 30
            ? Grade.hard
            : roll < 88
                ? Grade.good
                : Grade.easy;
  }

  // Two gaps, so the heatmap is a record and the streak a real number.
  const missed = {13, 8};
  for (var daysAgo = 20; daysAgo >= 1; daysAgo--) {
    if (missed.contains(daysAgo)) continue;
    final at = now.subtract(Duration(days: daysAgo, hours: 3));
    final count = 21 + next(12);
    for (var i = 0; i < count; i++) {
      await study.recordReview(
        cardId: cards[next(cards.length)].id,
        grade: grade(),
        at: at.add(Duration(minutes: i * 3)),
      );
    }
  }

  // Today: a session already started, short of the goal.
  final today = now.subtract(const Duration(minutes: 40));
  for (var i = 0; i < 8; i++) {
    await study.recordReview(
      cardId: cards[next(cards.length)].id,
      grade: grade(),
      at: today.add(Duration(minutes: i * 3)),
    );
  }

  await markOnboardingDone(db);
}

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
