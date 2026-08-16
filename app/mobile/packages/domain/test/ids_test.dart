import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('Uuid7', () {
    test('produces canonical v7 identifiers', () {
      for (var i = 0; i < 200; i++) {
        final id = Uuid7.generate();
        expect(Uuid7.isV7(id), isTrue, reason: id);
        expect(id.length, 36);
      }
    });

    test('embeds the supplied timestamp', () {
      final now = DateTime.utc(2026, 8, 8, 12, 30, 45, 123);
      final id = Uuid7.generate(now: now);
      expect(Uuid7.timestampOf(id), now);
    });

    test('sorts lexicographically in timestamp order', () {
      // This is the whole reason for v7 over v4 (§5.7): index locality. A
      // string sort must agree with chronological order.
      final ids = [
        Uuid7.generate(now: DateTime.utc(2024, 1, 1)),
        Uuid7.generate(now: DateTime.utc(2025, 6, 15)),
        Uuid7.generate(now: DateTime.utc(2026, 8, 8)),
      ];
      final shuffled = [...ids]..shuffle();
      shuffled.sort();
      expect(shuffled, ids);
    });

    test('is unique across a tight loop within one millisecond', () {
      final pinned = DateTime.utc(2026, 8, 8);
      final ids = {
        for (var i = 0; i < 5000; i++) Uuid7.generate(now: pinned),
      };
      // Same millisecond for every id, so uniqueness comes entirely from the
      // random bits.
      expect(ids.length, 5000);
    });

    test('rejects a timestamp before the epoch', () {
      expect(
        () => Uuid7.generate(now: DateTime.utc(1969)),
        throwsArgumentError,
      );
    });

    test('rejects malformed input', () {
      expect(() => Uuid7.timestampOf('not-a-uuid'), throwsFormatException);
      expect(Uuid7.isV7('not-a-uuid'), isFalse);
      // A v4 uuid is well-formed but not v7.
      expect(Uuid7.isV7('f47ac10b-58cc-4372-a567-0e02b2c3d479'), isFalse);
    });
  });
}
