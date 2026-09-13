import 'package:flutter_test/flutter_test.dart';

import 'package:flashcards/device/terminal_protocol.dart';

void main() {
  test(
    'TerminalInfo reports missing required fields instead of null assertion',
    () {
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
    },
  );

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

  test('TerminalPairing accepts T5 local protocol v4 QR', () {
    final pairing = TerminalPairing.parse(
      'mnemos://local'
      '?v=4'
      '&mode=provision'
      '&id=T5S3-A1B2C3'
      '&ssid=MNEMOS-A1B2C3'
      '&pwd=MN1234567890'
      '&host=192.168.4.1'
      '&token=ABCDEF0123456789'
      '&model=LILYGO-T5-4.7-S3-CARDKB'
      '&fw=0.6.0-preview.1',
    );

    expect(pairing.protocol, 4);
    expect(pairing.mode, 'provision');
    expect(pairing.deviceId, 'T5S3-A1B2C3');
    expect(pairing.host, '192.168.4.1');
  });

  test('TerminalPairing keeps legacy pair QR compatible', () {
    final pairing = TerminalPairing.parse(
      'mnemos://pair'
      '?v=3'
      '&id=LEGACY-1'
      '&ssid=MNEMOS-LEGACY'
      '&pwd=MN12345678'
      '&host=192.168.4.1'
      '&token=0123456789ABCDEF',
    );

    expect(pairing.protocol, 3);
    expect(pairing.mode, 'provision');
  });

  test('TerminalReview accepts canonical review v2 fields', () {
    final review = TerminalReview.fromJson({
      'schema': 'mnemos.review/v2',
      'id': 'review-1',
      'cardId': 'card-1',
      'reviewedAtMs': 1767258000123,
      'schedulerRating': 4,
      'responseTimeMs': 850,
    });

    expect(review.reviewedAt, 1767258000);
    expect(review.rating, 4);
    expect(review.responseTimeMs, 850);
  });
}
