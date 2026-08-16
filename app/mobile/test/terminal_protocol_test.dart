import 'package:flutter_test/flutter_test.dart';

import 'package:flashcards/device/terminal_protocol.dart';

void main() {
  test('TerminalInfo reports missing required fields instead of null assertion', () {
    expect(
      () => TerminalInfo.fromJson({
        'deviceId': 'CYD-ABC123',
        'firmware': '0.3.0',
        'model': 'CYD',
        'cardCount': 10,
      }),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('maxCards'),
        ),
      ),
    );
  });

  test('TerminalReview reports missing id instead of null assertion', () {
    expect(
      () => TerminalReview.fromJson({
        'cardId': 'card-1',
        'reviewedAt': 1700000000,
        'rating': 3,
      }),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('id'),
        ),
      ),
    );
  });
}
