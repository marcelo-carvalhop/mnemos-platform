import 'package:drift/native.dart';
import 'package:flashcards/features/onboarding/onboarding_screen.dart';
import 'package:flashcards/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store/store.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// §5.1, and the part of §7.7.1 that lives in an interface.
///
/// The free tier is one generation for the lifetime of the account. An
/// onboarding that spends it without saying so has taken something the user
/// did not know they had, and one where declining is hard has taken it by
/// attrition. Both are behaviour, so both are tested.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  final now = DateTime.utc(2026, 8, 9, 15);

  Widget harness({VoidCallback? onDone}) {
    db = AppDatabase(NativeDatabase.memory());
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(home: OnboardingScreen(onDone: onDone ?? () {})),
    );
  }

  tearDown(() => db.close());

  Future<void> walkToLastStep(WidgetTester tester, {String? subject}) async {
    await tester.tap(find.text('Começar'));
    await tester.pumpAndSettle();
    if (subject != null) {
      await tester.enterText(find.byType(TextField), subject);
      await tester.pump();
    }
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
  }

  testWidgets('the last step says what the free generation costs', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await walkToLastStep(tester);

    // It is one, it is per account, and it does not expire — all three said
    // out loud before it can be spent.
    expect(find.textContaining('uma geração por IA'), findsOneWidget);
    expect(find.textContaining('não expira'), findsOneWidget);
  });

  testWidgets('declining is a real button, not a link in the corner', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await walkToLastStep(tester);

    final skip = find.widgetWithText(OutlinedButton, 'Guardar para depois');
    expect(skip, findsOneWidget);
    expect(tester.widget<OutlinedButton>(skip).onPressed, isNotNull);
    // And the screen says why declining costs nothing.
    expect(find.textContaining('livres, sempre'), findsOneWidget);
  });

  testWidgets('skipping still leaves a usable app: a deck and a goal',
      (tester) async {
    var done = false;
    await tester.pumpWidget(harness(onDone: () => done = true));
    await tester.pumpAndSettle();
    await walkToLastStep(tester, subject: 'Direito Constitucional');

    await tester.tap(find.text('Guardar para depois'));
    await tester.pumpAndSettle();

    expect(done, isTrue);
    final decks = await db.select(db.decks).get();
    expect(decks.map((d) => d.name), ['Direito Constitucional']);
    expect(await db.select(db.goalHistory).get(), hasLength(1));
    // §5.1 — no cards. An app that starts with four someone else wrote starts
    // with a lie about whose knowledge it is.
    expect(await db.select(db.cards).get(), isEmpty);
  });

  testWidgets('a chosen goal is the one that is stored', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Começar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Leve'));
    await tester.pump();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar para depois'));
    await tester.pumpAndSettle();

    final goal = await db.select(db.goalHistory).getSingle();
    expect(goal.dailyGoal, 10);
  });

  testWidgets('someone who does not know what to study is not blocked',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await walkToLastStep(tester);
    await tester.tap(find.text('Guardar para depois'));
    await tester.pumpAndSettle();

    // A name is invented rather than a wall put up at step two of an app they
    // have not seen yet.
    expect((await db.select(db.decks).getSingle()).name, isNotEmpty);
  });

  testWidgets('it is not shown twice', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await walkToLastStep(tester);
    await tester.tap(find.text('Guardar para depois'));
    await tester.pumpAndSettle();

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    expect(await container.read(onboardingDoneProvider.future), isTrue);
  });
}
