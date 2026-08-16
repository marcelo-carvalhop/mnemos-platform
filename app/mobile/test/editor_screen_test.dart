import 'package:authoring/authoring.dart';
import 'package:domain/domain.dart';
import 'package:drift/native.dart';
import 'package:flashcards/features/editor_screen.dart';
import 'package:flashcards/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store/store.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// The one screen whose rule lives in the interface (§5.4).
///
/// The grapheme limit is enforced in three places — the counter, the disabled
/// button and the service — and only the first two are visible. Widget tests
/// are kept few, so they are spent where the behaviour is not reachable from
/// the packages.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  late String deckId;
  final now = DateTime.utc(2026, 8, 9, 15);

  Future<Widget> harness() async {
    db = AppDatabase(NativeDatabase.memory());
    deckId = await AuthoringService(db, deviceId: 'test-device')
        .createDeck(name: 'Baralho', at: now);
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(
        home: EditorScreen(deckId: deckId, deckName: 'Baralho'),
      ),
    );
  }

  tearDown(() => db.close());

  testWidgets('save stays disabled until both sides have text', (tester) async {
    await tester.pumpWidget(await harness());
    await tester.pumpAndSettle();

    final save = find.widgetWithText(FilledButton, 'Salvar e criar outro');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, 'Frente');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull,
        reason: 'a card with no answer is not a card');

    await tester.enterText(find.byType(TextField).last, 'Verso');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
  });

  testWidgets('over the limit the counter turns and saving is refused',
      (tester) async {
    await tester.pumpWidget(await harness());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'Verso');
    await tester.enterText(find.byType(TextField).first, 'a' * (kFrontMaxGraphemes + 5));
    await tester.pump();

    expect(find.text('${kFrontMaxGraphemes + 5} / $kFrontMaxGraphemes'), findsOneWidget);
    expect(find.textContaining('caracteres acima do limite'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Salvar e criar outro'))
          .onPressed,
      isNull,
      reason: 'the limit is a restriction, not a warning',
    );
  });

  testWidgets('an emoji counts once, not as its code units', (tester) async {
    // The counter must agree with the server, which counts grapheme clusters
    // (§5.4) — a family emoji is one character on the device screen.
    await tester.pumpWidget(await harness());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '👨‍👩‍👧‍👦');
    await tester.pump();

    expect(find.text('1 / $kFrontMaxGraphemes'), findsOneWidget);
  });

  testWidgets('"salvar e criar outro" clears the fields and keeps the screen',
      (tester) async {
    await tester.pumpWidget(await harness());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Frente');
    await tester.enterText(find.byType(TextField).last, 'Verso');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar e criar outro'));
    await tester.pumpAndSettle();

    expect(find.byType(EditorScreen), findsOneWidget);
    expect(find.text('0 / $kFrontMaxGraphemes'), findsOneWidget);

    final cards = await db.select(db.cards).get();
    expect(cards.map((c) => c.front), ['Frente']);
  });
}
