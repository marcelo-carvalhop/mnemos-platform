import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// §5.12, §11.5 — one notification, local, no backend at all.
///
/// The queue is computed on the device, so nothing about what someone is
/// studying has to leave it in order to decide when to nudge them. That
/// deletes an entire subsystem: no push tokens, no push service, no
/// server-side scheduler, and no privacy question about a third party knowing
/// how often a user forgets things.
///
/// One notification, at a chosen time, switchable off. Rescheduled at the end
/// of a session and cancelled when there is nothing due — a reminder that
/// fires for an empty queue is how people learn to swipe reminders away.
/// What scheduling a reminder needs from the platform.
///
/// An interface for the same reason `SyncApi` is one: the decisions worth
/// testing are *whether* to schedule and *when*, and neither is about a
/// platform channel. The plugin cannot be subclassed anyway.
abstract interface class ReminderSink {
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime at,
  });

  Future<void> cancel(int id);
  Future<bool> requestPermission();
  Future<void> initialise();
}

class StudyReminders {
  StudyReminders(this._sink);

  final ReminderSink _sink;

  static const _id = 1;
  Future<void> initialise() => _sink.initialise();

  /// Asks for permission at the moment it means something — when the switch is
  /// turned on, not at first launch, because a prompt shown before anyone
  /// knows what the app does is a prompt that gets denied.
  Future<bool> requestPermission() => _sink.requestPermission();

  /// Schedules the daily reminder, or cancels it when nothing is due.
  ///
  /// [dueCount] is why this takes an argument at all: §5.12 wants a nudge
  /// about the overdue queue, and a daily notification that fires whether or
  /// not there is anything to do is the kind people turn off in a week.
  Future<void> schedule({
    required int hour,
    required int minute,
    required int dueCount,
    required tz.Location location,
    DateTime? now,
  }) async {
    if (dueCount == 0) {
      await cancel();
      return;
    }

    await _sink.schedule(
      id: _id,
      title: 'Sua revisão de hoje',
      body: dueCount == 1 ? '1 card esperando' : '$dueCount cards esperando',
      at: _nextOccurrence(hour: hour, minute: minute, location: location, now: now),
    );
  }

  Future<void> cancel() => _sink.cancel(_id);

  /// The next time that clock reading happens, in the user's own timezone.
  ///
  /// §5.7's zone, not the device's: someone who set São Paulo and is
  /// travelling wants their reminder at 20:00 São Paulo, because that is when
  /// their day was defined to end.
  static tz.TZDateTime _nextOccurrence({
    required int hour,
    required int minute,
    required tz.Location location,
    DateTime? now,
  }) {
    final current = now == null
        ? tz.TZDateTime.now(location)
        : tz.TZDateTime.from(now, location);

    var next = tz.TZDateTime(
      location,
      current.year,
      current.month,
      current.day,
      hour,
      minute,
    );
    if (!next.isAfter(current)) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }
}


/// The real one.
class PluginReminderSink implements ReminderSink {
  PluginReminderSink([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'daily_review',
      'Revisão diária',
      channelDescription: 'Um lembrete por dia, quando há cards vencendo.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<void> initialise() async {
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  @override
  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }
    return false;
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime at,
  }) {
    return _plugin.zonedSchedule(
      id,
      title,
      body,
      at,
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // Absolute: the hour was already resolved in the user's zone. Wall-clock
      // interpretation would drift the reminder by an hour twice a year for
      // anyone whose zone observes daylight saving.
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id);
}
