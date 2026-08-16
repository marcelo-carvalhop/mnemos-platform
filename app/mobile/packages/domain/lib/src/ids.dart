import 'dart:math';

/// UUIDv7 — client-generated identity (§5.7).
///
/// Offline creation cannot wait for a server to assign an id, and v7's
/// leading millisecond timestamp keeps index locality that random v4 would
/// destroy. Ownership is still verified server-side (§5.5): a client-chosen
/// id is an identity, never an authorisation.
///
/// Layout (RFC 9562): 48-bit big-endian milliseconds, 4-bit version 7,
/// 12 bits random, 2-bit variant, 62 bits random.
abstract final class Uuid7 {
  static final Random _random = Random.secure();

  /// Generates a new v7 identifier in canonical 8-4-4-4-12 form.
  ///
  /// [now] is injectable so tests can pin the timestamp; production passes
  /// nothing and gets the wall clock.
  static String generate({DateTime? now}) {
    final millis = (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
    if (millis < 0) {
      throw ArgumentError.value(now, 'now', 'must be at or after the epoch');
    }

    final bytes = Uint8ListLike(16);

    // 48-bit timestamp, big-endian.
    for (var i = 0; i < 6; i++) {
      bytes[i] = (millis >> (8 * (5 - i))) & 0xFF;
    }
    for (var i = 6; i < 16; i++) {
      bytes[i] = _random.nextInt(256);
    }

    // Version 7 in the high nibble of byte 6.
    bytes[6] = (bytes[6] & 0x0F) | 0x70;
    // RFC 4122 variant in the two high bits of byte 8.
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  /// Extracts the embedded timestamp. Used by tests and by diagnostics that
  /// need to order ids without a separate column.
  static DateTime timestampOf(String uuid) {
    final hex = uuid.replaceAll('-', '');
    if (hex.length != 32) {
      throw FormatException('not a uuid: $uuid');
    }
    final millis = int.parse(hex.substring(0, 12), radix: 16);
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  /// True when [uuid] is canonical and carries version 7.
  static bool isV7(String uuid) {
    final match = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    return match.hasMatch(uuid.toLowerCase());
  }
}

/// Minimal fixed-length byte buffer, so `domain` needs no `dart:typed_data`
/// import in its public surface and stays trivially portable.
class Uint8ListLike {
  Uint8ListLike(int length) : _bytes = List<int>.filled(length, 0);

  final List<int> _bytes;

  int operator [](int i) => _bytes[i];
  void operator []=(int i, int value) => _bytes[i] = value & 0xFF;

  Iterable<T> map<T>(T Function(int) f) => _bytes.map(f);
}
