import 'package:flashcards/notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// §5.12, §11.5.
///
/// The scheduling decision is what is worth testing: a daily notification that
/// fires whether or not there is anything to do is the kind people turn off in
/// a week, and one computed in the wrong timezone arrives at the wrong hour
/// for anyone who travels.
class _RecordingSink implements ReminderSink {
  final List<({tz.TZDateTime at, String body})> scheduled = [];
  int cancels = 0;

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime at,
  }) async {
    scheduled.add((at: at, body: body));
  }

  @override
  Future<void> cancel(int id) async => cancels++;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> initialise() async {}
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late _RecordingSink plugin;
  late StudyReminders reminders;
  tz.Location saoPaulo() => tz.getLocation('America/Sao_Paulo');

  setUp(() {
    plugin = _RecordingSink();
    reminders = StudyReminders(plugin);
  });

  test('nothing due means no notification at all', () async {
    // A reminder that fires for an empty queue teaches people to swipe
    // reminders away.
    await reminders.schedule(
      hour: 20,
      minute: 0,
      dueCount: 0,
      location: saoPaulo(),
      now: DateTime.utc(2026, 8, 9, 12),
    );

    expect(plugin.scheduled, isEmpty);
    expect(plugin.cancels, 1);
  });

  test('the body says how much is waiting, in the right plural', () async {
    await reminders.schedule(
      hour: 20,
      minute: 0,
      dueCount: 1,
      location: saoPaulo(),
      now: DateTime.utc(2026, 8, 9, 12),
    );
    expect(plugin.scheduled.single.body, '1 card esperando');

    await reminders.schedule(
      hour: 20,
      minute: 0,
      dueCount: 7,
      location: saoPaulo(),
      now: DateTime.utc(2026, 8, 9, 12),
    );
    expect(plugin.scheduled.last.body, '7 cards esperando');
  });

  test('it is scheduled in the stored zone, not the device one', () async {
    // §5.7 — someone who set São Paulo and is travelling wants the reminder
    // when their day was defined to end, not when the airport clock says 20:00.
    await reminders.schedule(
      hour: 20,
      minute: 0,
      dueCount: 3,
      location: saoPaulo(),
      // 12:00 UTC is 09:00 in São Paulo, so today's 20:00 is still ahead.
      now: DateTime.utc(2026, 8, 9, 12),
    );

    final at = plugin.scheduled.single.at;
    expect(at.location.name, 'America/Sao_Paulo');
    expect(at.hour, 20);
    expect(at.day, 9);
  });

  test('past the hour, it goes to tomorrow rather than firing at once',
      () async {
    // 23:00 UTC is 20:00 in São Paulo — the moment has passed.
    await reminders.schedule(
      hour: 20,
      minute: 0,
      dueCount: 2,
      location: saoPaulo(),
      now: DateTime.utc(2026, 8, 9, 23, 30),
    );

    expect(plugin.scheduled.single.at.day, 10);
    expect(plugin.scheduled.single.at.hour, 20);
  });

  test('a chosen hour is honoured', () async {
    await reminders.schedule(
      hour: 7,
      minute: 0,
      dueCount: 1,
      location: saoPaulo(),
      now: DateTime.utc(2026, 8, 9, 12),
    );

    // 09:00 local, so 07:00 is already gone: tomorrow at 07:00.
    final at = plugin.scheduled.single.at;
    expect(at.hour, 7);
    expect(at.day, 10);
  });
}
