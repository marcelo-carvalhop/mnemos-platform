import 'package:authoring/authoring.dart';
import 'package:domain/domain.dart';
import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:progress/progress.dart';
import 'package:scheduler/scheduler.dart';
import 'package:session/session.dart';
import 'package:store/store.dart';
import 'package:timezone/timezone.dart' as tz;

import 'notifications.dart';

/// Composition (§4.4).
///
/// Providers hold no SQL and no scheduling arithmetic — they wire the packages
/// together and supply the two things the pure code refuses to invent for
/// itself: the clock and the database.

/// Injected so tests can pin time. `scheduler` takes the instant as a
/// parameter precisely so nothing reads a hidden clock (§4.1).
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(driftDatabase(name: 'flashcards'));
  ref.onDispose(db.close);
  return db;
});

/// Identifies this install. Written once and then read (§5.7, §8.1).
final deviceIdProvider = FutureProvider<String>((ref) async {
  final db = ref.watch(databaseProvider);
  const key = 'device_id';

  final existing = await (db.select(db.localSettings)..where((t) => t.key.equals(key)))
      .getSingleOrNull();
  if (existing != null) return existing.value;

  final id = Uuid7.generate();
  await db.into(db.localSettings).insert(
        LocalSettingsCompanion.insert(key: key, value: id),
      );
  return id;
});

/// Everything in `user_settings`, as a map.
///
/// One read, shared: the settings screen, the day bucket, the FSRS parameters
/// and the queue all want the same rows, and four queries for one table is
/// four chances for them to disagree within a frame.
final userSettingsProvider = FutureProvider<Map<String, String>>((ref) async {
  final db = ref.watch(databaseProvider);
  final rows = await db.select(db.userSettings).get();
  return {for (final r in rows) r.key: r.value};
});

/// The stored timezone and cutoff, never the device's (§5.7).
final dayBucketProvider = FutureProvider<DayBucket>((ref) async {
  final db = ref.watch(databaseProvider);
  final rows = await db.select(db.userSettings).get();
  final settings = {for (final r in rows) r.key: r.value};

  return DayBucket(
    timezoneName: settings['timezone'] ?? 'America/Sao_Paulo',
    cutoffHour: int.tryParse(settings['day_cutoff_hour'] ?? '') ?? kDefaultDayCutoffHour,
  );
});

/// The FSRS vector and retention target — synced, because both are inputs to
/// the interval formula (§3.1).
final fsrsParamsProvider = FutureProvider<FsrsParams>((ref) async {
  final db = ref.watch(databaseProvider);
  final rows = await db.select(db.userSettings).get();
  final settings = {for (final r in rows) r.key: r.value};

  return FsrsParams(
    weights: defaultFsrsWeights,
    desiredRetention:
        double.tryParse(settings['desired_retention'] ?? '') ?? kDesiredRetention,
  );
});

final studyServiceProvider = FutureProvider<StudyService>((ref) async {
  return StudyService(
    ref.watch(databaseProvider),
    deviceId: await ref.watch(deviceIdProvider.future),
    params: await ref.watch(fsrsParamsProvider.future),
  );
});

final authoringServiceProvider = FutureProvider<AuthoringService>((ref) async {
  return AuthoringService(
    ref.watch(databaseProvider),
    deviceId: await ref.watch(deviceIdProvider.future),
  );
});

final progressServiceProvider = FutureProvider<ProgressService>((ref) async {
  return ProgressService(
    ref.watch(databaseProvider),
    day: await ref.watch(dayBucketProvider.future),
  );
});

// ---------------------------------------------------------------------------
// Screen state
// ---------------------------------------------------------------------------

/// The headline of §9, as the home screen shows it.
final accumulatedMemoryProvider = FutureProvider<AccumulatedMemory>((ref) async {
  final service = await ref.watch(progressServiceProvider.future);
  return service.accumulatedMemory();
});

final dailyGoalProvider = FutureProvider<int>((ref) async {
  final service = await ref.watch(progressServiceProvider.future);
  final day = await ref.watch(dayBucketProvider.future);
  return await service.goalOn(day.today(ref.watch(clockProvider)())) ?? 20;
});

/// Cards answered today, against the goal in force today.
final studiedTodayProvider = FutureProvider<int>((ref) async {
  final study = await ref.watch(studyServiceProvider.future);
  final day = await ref.watch(dayBucketProvider.future);
  final counts = await study.countReviewsOn(day.today(ref.watch(clockProvider)()), day);
  return counts.newCards + counts.reviews;
});

/// Today's queue, honouring both daily limits (§5.8).
final queueProvider = FutureProvider<List<String>>((ref) async {
  final study = await ref.watch(studyServiceProvider.future);
  final day = await ref.watch(dayBucketProvider.future);
  final db = ref.watch(databaseProvider);

  final rows = await db.select(db.userSettings).get();
  final settings = {for (final r in rows) r.key: r.value};

  return study.buildQueue(
    now: ref.watch(clockProvider)(),
    newPerDay: int.tryParse(settings['new_per_day'] ?? '') ?? 10,
    reviewPerDay: int.tryParse(settings['review_per_day'] ?? '') ?? 200,
    day: day,
  );
});

/// Whether anything exists to study at all.
///
/// "Nothing due" and "nothing exists" are different sentences and were the
/// same one: a brand-new account with no cards was told its memory was working
/// away on its own (§5.1, §5.2).
final hasAnyCardsProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final rows = await (db.select(db.cards)..where((t) => t.deletedAt.isNull())..limit(1)).get();
  return rows.isNotEmpty;
});

final decksProvider = FutureProvider<List<Deck>>((ref) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.decks)
        ..where((t) => t.deletedAt.isNull())
        ..where((t) => t.archivedAt.isNull()))
      .get();
});

final deckCardCountsProvider = FutureProvider<Map<String, int>>((ref) async {
  final db = ref.watch(databaseProvider);
  final rows = await db.customSelect(
    '''
    SELECT deck_id, COUNT(*) AS card_count
    FROM cards
    WHERE deleted_at IS NULL
    GROUP BY deck_id
    ''',
    readsFrom: {db.cards},
  ).get();
  return {
    for (final row in rows)
      row.read<String>('deck_id'): row.read<int>('card_count'),
  };
});

final deckMaturityProvider = FutureProvider<Map<String, DeckMaturity>>((ref) async {
  final service = await ref.watch(progressServiceProvider.future);
  return {for (final m in await service.maturityByDeck()) m.deckId: m};
});

final cardProvider = FutureProvider.family<Card?, String>((ref, cardId) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.cards)..where((t) => t.id.equals(cardId))).getSingleOrNull();
});

/// The four intervals for the grade buttons (§5.8.3).
///
/// Derived from the same function that writes the state, so the button cannot
/// promise something the review does not deliver.
final previewProvider =
    FutureProvider.family<Map<Grade, Duration>, String>((ref, cardId) async {
  final study = await ref.watch(studyServiceProvider.future);
  return study.preview(cardId, ref.watch(clockProvider)());
});

/// Whether §5.1's onboarding has been walked.
///
/// In `local_settings`, which never syncs: onboarding is per install. A second
/// device belonging to the same account has its own first launch, and pulling
/// somebody's decks does not mean this phone has seen the four screens.
const kOnboardingKey = 'onboarding_done';

final onboardingDoneProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final row = await (db.select(db.localSettings)
        ..where((t) => t.key.equals(kOnboardingKey)))
      .getSingleOrNull();
  if (row != null) return true;

  // An install that already has decks predates this flag — sending it through
  // onboarding would be asking someone with a year of history what they would
  // like to study.
  return (await db.select(db.decks).get()).isNotEmpty;
});

Future<void> markOnboardingDone(AppDatabase db) async {
  await db.into(db.localSettings).insert(
        LocalSettingsCompanion.insert(key: kOnboardingKey, value: '1'),
        mode: InsertMode.insertOrReplace,
      );
}

/// Per-install preferences, which never sync (§5.4).
///
/// The spec is explicit that the notification time belongs here: a reminder is
/// a property of a phone, not of a person. Someone whose tablet lives on a
/// desk does not want it buzzing at 20:00 in an empty room.
final localSettingsProvider = FutureProvider<Map<String, String>>((ref) async {
  final db = ref.watch(databaseProvider);
  final rows = await db.select(db.localSettings).get();
  return {for (final r in rows) r.key: r.value};
});

Future<void> writeLocalSetting(WidgetRef ref, String key, String value) async {
  final db = ref.read(databaseProvider);
  await db.into(db.localSettings).insert(
        LocalSettingsCompanion.insert(key: key, value: value),
        mode: InsertMode.insertOrReplace,
      );
  ref.invalidate(localSettingsProvider);
}

/// §5.12, §11.5 — the one local notification.
final remindersProvider = Provider<StudyReminders>(
  (ref) => StudyReminders(PluginReminderSink()),
);

/// Reschedules the reminder from what is actually due.
///
/// Called after a session and at bootstrap. A daily notification that fires
/// whether or not there is anything to do is the kind people turn off in a
/// week, so the count decides whether it exists at all.
Future<void> refreshReminder(WidgetRef ref) async {
  final local = await ref.read(localSettingsProvider.future);
  final reminders = ref.read(remindersProvider);

  if ((local['reminder_enabled'] ?? '0') != '1') {
    await reminders.cancel();
    return;
  }

  final day = await ref.read(dayBucketProvider.future);
  await reminders.schedule(
    hour: int.tryParse(local['reminder_hour'] ?? '') ?? 20,
    minute: 0,
    dueCount: (await ref.read(queueProvider.future)).length,
    // §5.7's zone, not the device's: someone who set São Paulo and is
    // travelling wants the reminder when their day was defined to end.
    location: tz.getLocation(day.timezoneName),
    now: ref.read(clockProvider)(),
  );
}

/// Kept for tests and for `--dart-define=SEED_DEMO=true`.
///
/// Not called on a real first launch any more: §5.1's onboarding creates the
/// deck, and an app that starts with four cards someone else wrote starts with
/// a lie about whose knowledge it is.
Future<void> seedIfEmpty(AppDatabase db, String deviceId, DateTime now) async {
  final decks = await db.select(db.decks).get();
  if (decks.isNotEmpty) return;

  final authoring = AuthoringService(db, deviceId: deviceId);
  final deckId = await authoring.createDeck(name: 'Redes de Computadores', at: now);

  const seeds = [
    ('Qual é a função principal da camada de enlace?',
        'Entregar quadros entre nós diretamente conectados ao mesmo enlace e tratar o acesso ao meio físico.'),
    ('Qual é a função principal do protocolo IP?',
        'Endereçar e encaminhar datagramas entre redes, oferecendo entrega por melhor esforço.'),
    ('Qual é a diferença fundamental entre TCP e UDP?',
        'TCP oferece fluxo orientado a conexão, confiável e ordenado; UDP oferece datagramas sem conexão e sem garantias de entrega ou ordem.'),
    ('O que ocorre no three-way handshake do TCP?',
        'Cliente e servidor trocam SYN, SYN-ACK e ACK para sincronizar números de sequência e estabelecer a conexão.'),
    ('Para que serve o DNS?',
        'Resolver nomes de domínio em dados como endereços IP por meio de uma hierarquia distribuída de servidores.'),
    ('Qual é a função de uma máscara de sub-rede?',
        'Separar os bits de rede e de host de um endereço IP, permitindo determinar quais endereços pertencem à mesma sub-rede.'),
    ('O que faz um roteador?',
        'Encaminha pacotes entre redes distintas com base em sua tabela de roteamento e no endereço IP de destino.'),
    ('O que é ARP em redes IPv4?',
        'É o protocolo usado em uma rede local para descobrir o endereço MAC associado a um endereço IPv4 conhecido.'),
    ('Qual é a finalidade do DHCP?',
        'Fornecer automaticamente parâmetros de configuração de rede, como endereço IP, máscara, gateway e servidores DNS.'),
    ('O que significa NAT?',
        'Network Address Translation: tradução de endereços entre domínios de rede, frequentemente usada para compartilhar um endereço público entre hosts privados.'),
  ];

  for (final (front, back) in seeds) {
    await authoring.createCard(deckId: deckId, front: front, back: back, at: now);
  }

  await db.into(db.goalHistory).insert(
        GoalHistoryCompanion.insert(
          id: Uuid7.generate(now: now),
          effectiveFromLocalDate:
              const DayBucket(timezoneName: 'America/Sao_Paulo').today(now),
          dailyGoal: 20,
          createdAt: now.millisecondsSinceEpoch,
          deviceId: deviceId,
        ),
      );

  await db.into(db.userSettings).insert(
        UserSettingsCompanion.insert(
          key: 'timezone',
          value: 'America/Sao_Paulo',
          updatedAt: now.millisecondsSinceEpoch,
          deviceId: deviceId,
          serverSeq: const Value.absent(),
        ),
      );
}
