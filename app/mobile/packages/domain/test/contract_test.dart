import 'package:domain/domain.dart';
import 'package:test/test.dart';

/// §4 and §10 — the wire value is the contract.
void main() {
  test('enum members carry the wire value, not their Dart name', () {
    // `.name` is camelCase and the wire value is not. Writing `.name` into a
    // column stored 'multipleChoice' where the server expects
    // 'multiple_choice' — silently, because the column is only text.
    expect(ReviewSource.multipleChoice.wire, 'multiple_choice');
    expect(ReviewSource.multipleChoice.name, isNot(ReviewSource.multipleChoice.wire));
    expect(ErrorCode.quotaExhausted.wire, 'quota_exhausted');
    expect(CardStatus.suspended.wire, 'suspended');
  });

  test('every wire value round-trips', () {
    for (final v in ReviewSource.values) {
      expect(ReviewSource.fromWire(v.wire), v);
    }
    for (final v in CardStatus.values) {
      expect(CardStatus.fromWire(v.wire), v);
    }
    for (final v in ErrorCode.values) {
      expect(ErrorCode.fromWire(v.wire), v);
    }
  });

  test('an unknown error code is null, not an exception', () {
    // §5.3 — a client several versions behind meets codes it has never heard
    // of, and that is ordinary rather than corrupt.
    expect(ErrorCode.fromWire('inventado_no_futuro'), isNull);
    expect(ErrorCode.fromWire(null), isNull);
  });

  test('an unknown review source is loud, because it is not ordinary', () {
    // A row already in the database carrying a source this build cannot read
    // is a real inconsistency, unlike a code arriving over the wire.
    expect(() => ReviewSource.fromWire('telepatia'), throwsArgumentError);
  });

  test('grade wire values are never renumbered', () {
    expect(Grade.again.value, 1);
    expect(Grade.hard.value, 2);
    expect(Grade.good.value, 3);
    expect(Grade.easy.value, 4);
    expect(Grade.fromValue(3), Grade.good);
  });
}
