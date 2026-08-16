import 'package:domain/domain.dart';
import 'package:drift/native.dart';
import 'package:flashcards/features/settings_screen.dart';
import 'package:flashcards/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store/store.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// §5.12 and §5.7.
///
/// What is worth testing here is not that a slider slides: it is that a
/// setting which changes scheduling reaches `user_settings` with a fresh
/// `updated_at`, because that is what makes last-writer-wins mean anything
/// between two devices (§6.2) — and that the screen tells the truth about the
/// day cutoff not rewriting the past.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  final now = DateTime.utc(2026, 8, 9, 15);

  Widget harness() {
    db = AppDatabase(NativeDatabase.memory());
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => now),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    );
  }

  tearDown(() => db.close());

  Future<Map<String, String>> stored() async {
    final rows = await db.select(db.userSettings).get();
    return {for (final r in rows) r.key: r.value};
  }

  testWidgets('changing a limit writes it with a timestamp and a device',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await tester.pumpAndSettle();

    final row = await (db.select(db.userSettings)
          ..where((t) => t.key.equals('new_per_day')))
        .getSingle();
    expect(row.value, '15');
    // Without these, two devices cannot decide whose setting is newer.
    expect(row.updatedAt, now.millisecondsSinceEpoch);
    expect(row.deviceId, isNotEmpty);
    // Null server_seq is the outbox: it has not been pushed yet (§6.2).
    expect(row.serverSeq, isNull);
  });

  testWidgets('the retention target is a synced setting, not a local one',
      (tester) async {
    // §3.1 — it is an input to the interval formula, so a phone and a tablet
    // disagreeing about it would schedule the same card differently.
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pumpAndSettle();

    // What matters is that it landed in `user_settings`, which is the synced
    // table — not which way the drag went.
    final values = await stored();
    expect(values, contains('desired_retention'));
    expect(double.parse(values['desired_retention']!),
        isNot(closeTo(kDesiredRetention, 0.001)));
  });

  testWidgets('the retention target cannot be set to something absurd',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // Below 0.80 the schedule stops being a schedule; above 0.95 the workload
    // explodes. Neither end is a choice worth offering.
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 0.80);
    expect(slider.max, 0.95);

    await tester.drag(find.byType(Slider), const Offset(-800, 0));
    await tester.pumpAndSettle();
    expect(double.parse((await stored())['desired_retention']!), greaterThanOrEqualTo(0.80));
  });

  testWidgets('the day cutoff says it does not rewrite the past', (tester) async {
    // §5.7 — a user who changes it and finds yesterday's streak rearranged
    // has been lied to. Saying so is the cheap half of not doing it.
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.textContaining('não reescreve o passado'), findsOneWidget);
    expect(find.textContaining('conta para o dia anterior'), findsOneWidget);
  });

  testWidgets('defaults come from the contract, not from the widget',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('${(kDesiredRetention * 100).round()}%'), findsOneWidget);
    expect(
      find.text('${kDefaultDayCutoffHour.toString().padLeft(2, '0')}:00'),
      findsOneWidget,
    );
  });
}
