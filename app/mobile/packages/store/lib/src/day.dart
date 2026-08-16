import 'package:timezone/timezone.dart' as tz;

/// Day bucketing (§5.7).
///
/// One function serves the daily goal, "enterrado até amanhã" (§4), the
/// heatmap and the streak (§5.11). Two decisions hide in it:
///
/// **The timezone is stored, not read from the device.** Reading the device
/// means the heatmap rewrites itself when the user flies to Lisbon — every
/// past day shifts, and a streak can break retroactively.
///
/// **The day rolls over at 04:00 local by default, not midnight.** Studying at
/// 01:00 otherwise counts as the next day, which breaks the streak of exactly
/// the people who study late.
class DayBucket {
  const DayBucket({required this.timezoneName, this.cutoffHour = 4});

  /// IANA name, e.g. `America/Sao_Paulo`.
  final String timezoneName;

  /// Hour at which the local day rolls over.
  final int cutoffHour;

  tz.Location get _location => tz.getLocation(timezoneName);

  /// The local day [instant] belongs to, as `YYYY-MM-DD`.
  ///
  /// An instant before the cutoff belongs to the previous day.
  ///
  /// The comparison is on the local wall clock, and the day arithmetic runs in
  /// UTC. Subtracting `cutoffHour` as a [Duration] looks equivalent and is not:
  /// across a DST transition it crosses into the other offset and returns the
  /// wrong day. On the night Lisbon springs forward, 04:00 local minus four
  /// absolute hours lands at 23:00 on the *previous* day.
  String keyFor(DateTime instant) {
    final local = tz.TZDateTime.from(instant.toUtc(), _location);

    var calendar = DateTime.utc(local.year, local.month, local.day);
    if (local.hour < cutoffHour) {
      calendar = calendar.subtract(const Duration(days: 1));
    }
    return _format(calendar);
  }

  static String _format(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// The instant the given local day begins.
  DateTime startOf(String dayKey) {
    final parts = dayKey.split('-').map(int.parse).toList();
    final start = tz.TZDateTime(
      _location,
      parts[0],
      parts[1],
      parts[2],
      cutoffHour,
    );
    return start.toUtc();
  }

  /// Half-open range `[start, end)` covering the given local day.
  ///
  /// Computed by adding a day to the *key* rather than 24 hours to the start,
  /// so a DST transition gives a 23- or 25-hour day instead of silently
  /// shifting the boundary.
  (DateTime start, DateTime end) rangeOf(String dayKey) {
    final parts = dayKey.split('-').map(int.parse).toList();
    final nextDay = DateTime.utc(parts[0], parts[1], parts[2] + 1);
    return (startOf(dayKey), startOf(_format(nextDay)));
  }

  /// The day key for "today" at [now].
  String today(DateTime now) => keyFor(now);

  /// The instant "enterrado até amanhã" (§4) should expire.
  DateTime endOfDay(DateTime instant) => rangeOf(keyFor(instant)).$2;
}
