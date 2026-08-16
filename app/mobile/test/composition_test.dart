import 'package:domain/domain.dart';
import 'package:drift/native.dart';
import 'package:flashcards/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store/store.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// Composition, not widgets (§12, §4.4).
///
/// Providers are testable without a widget tree, which is what makes "light on
/// widget tests" an honest position rather than a gap. What is verified here is
/// the wiring: that the packages reach each other and that the clock and the
/// database are the only things injected.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  late ProviderContainer container;
  final now = DateTime.utc(2026, 8, 9, 15);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    await db.customSelect('SELECT 1').get();
    await seedIfEmpty(db, 'test-device', now);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('a fresh install has a deck and a queue rather than a blank screen', () async {
    final decks = await container.read(decksProvider.future);
    expect(decks, isNotEmpty);

    final queue = await container.read(queueProvider.future);
    expect(queue, isNotEmpty, reason: 'new cards must be offered on day one');
  });

  test('the headline starts at zero and only moves by remembering', () async {
    // §2.3 — seeding four cards must not inflate it.
    expect((await container.read(accumulatedMemoryProvider.future)).days, 0);

    final study = await container.read(studyServiceProvider.future);
    final queue = await container.read(queueProvider.future);
    await study.recordReview(cardId: queue.first, grade: Grade.good, at: now);

    container.invalidate(accumulatedMemoryProvider);
    expect((await container.read(accumulatedMemoryProvider.future)).days, greaterThan(0));
  });

  test('the grade buttons get four real intervals, ordered', () async {
    // §5.8.3 — the button must not promise something the review will not
    // deliver, so the preview comes from the scheduler, never from the UI.
    final queue = await container.read(queueProvider.future);
    final preview = await container.read(previewProvider(queue.first).future);

    expect(preview.keys.toSet(), Grade.values.toSet());
    expect(preview[Grade.again]!, lessThanOrEqualTo(preview[Grade.hard]!));
    expect(preview[Grade.hard]!, lessThanOrEqualTo(preview[Grade.good]!));
    expect(preview[Grade.good]!, lessThanOrEqualTo(preview[Grade.easy]!));
  });

  test('answering counts against today, bucketed by the stored timezone', () async {
    final study = await container.read(studyServiceProvider.future);
    final queue = await container.read(queueProvider.future);
    await study.recordReview(cardId: queue.first, grade: Grade.good, at: now);

    container.invalidate(studiedTodayProvider);
    expect(await container.read(studiedTodayProvider.future), 1);
  });

  test('the device id is created once and then reused', () async {
    final first = await container.read(deviceIdProvider.future);
    container.invalidate(deviceIdProvider);
    expect(await container.read(deviceIdProvider.future), first);
  });

  test('seeding twice does not duplicate the deck', () async {
    await seedIfEmpty(db, 'test-device', now);
    expect((await container.read(decksProvider.future)).length, 1);
  });

  test('nothing due and nothing existing are different answers', () async {
    // A brand-new account was being told its memory was working away on its
    // own, with no cards at all. §5.2's completion state belongs to someone
    // who finished, not to someone who has not started.
    expect(await container.read(hasAnyCardsProvider.future), isTrue);

    final empty = AppDatabase(NativeDatabase.memory());
    addTearDown(empty.close);
    final fresh = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(empty),
      clockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(fresh.dispose);

    expect(await fresh.read(hasAnyCardsProvider.future), isFalse);
    expect(await fresh.read(queueProvider.future), isEmpty);
  });
}