import 'package:domain/domain.dart';
import 'package:test/test.dart';

/// The shared grapheme fixture required by §7.6 and §12.
///
/// The Python suite runs the same cases against the server-side `constrain`
/// stage. If the two ever disagree, the editor accepts text the server drops.
const graphemeFixture = <String, int>{
  '': 0,
  'a': 1,
  'abc': 3,
  // Composed: U+00E7 (ç) as a single code point.
  'ção': 3,
  // Decomposed: c + U+0327 combining cedilla, then a + U+0303 combining tilde.
  'ção': 3,
  // Portuguese with several accents.
  'A função é intuitiva': 20,
  // Emoji with a variation selector: one cluster, several code units.
  '❤️': 1,
  // ZWJ sequence: family emoji is one user-perceived character.
  '👨‍👩‍👧': 1,
  // Skin-tone modifier.
  '👍🏽': 1,
  // Hyphenation and punctuation are ordinary characters.
  'guarda-chuva': 12,
};

void main() {
  group('graphemeLength', () {
    graphemeFixture.forEach((text, expected) {
      test('counts ${_describe(text)} as $expected', () {
        expect(CardText.graphemeLength(text), expected);
      });
    });

    test('composed and decomposed forms count the same', () {
      // This is the property that makes grapheme clusters the right unit:
      // the two strings have different bytes and different code-unit lengths,
      // but the user sees the same three characters.
      const composed = 'ção';
      const decomposed = 'ção';

      expect(composed.length, isNot(equals(decomposed.length)),
          reason: 'the fixture must actually exercise the difference');
      expect(
        CardText.graphemeLength(composed),
        CardText.graphemeLength(decomposed),
      );
    });

    test('String.length would give the wrong answer for emoji', () {
      // Guards against someone "simplifying" the implementation back to
      // String.length.
      expect('👍🏽'.length, greaterThan(1));
      expect(CardText.graphemeLength('👍🏽'), 1);
    });
  });

  group('limits', () {
    test('front accepts exactly the limit and rejects one more', () {
      final atLimit = 'a' * kFrontMaxGraphemes;
      expect(CardText.frontFits(atLimit), isTrue);
      expect(CardText.frontRemaining(atLimit), 0);

      expect(CardText.frontFits('$atLimit!'), isFalse);
      expect(CardText.frontRemaining('$atLimit!'), -1);
    });

    test('back accepts exactly the limit and rejects one more', () {
      final atLimit = 'a' * kBackMaxGraphemes;
      expect(CardText.backFits(atLimit), isTrue);
      expect(CardText.backFits('$atLimit!'), isFalse);
    });

    test('a limit measured in emoji is the same limit', () {
      // 120 emoji is 120 characters to the user, whatever the byte count.
      final emojiFront = '👍🏽' * kFrontMaxGraphemes;
      expect(CardText.frontFits(emojiFront), isTrue);
      expect(CardText.frontFits('$emojiFront👍🏽'), isFalse);
    });

    test('the back limit is larger than the front limit', () {
      expect(kBackMaxGraphemes, greaterThan(kFrontMaxGraphemes));
    });
  });

  group('truncateToGraphemes', () {
    test('never splits a cluster', () {
      const text = '👨‍👩‍👧👍🏽ção';
      final cut = CardText.truncateToGraphemes(text, 2);
      expect(CardText.graphemeLength(cut), 2);
      expect(cut, '👨‍👩‍👧👍🏽');
    });

    test('returns the input unchanged when already within the limit', () {
      expect(CardText.truncateToGraphemes('curto', 10), 'curto');
    });
  });
}

String _describe(String text) {
  if (text.isEmpty) return 'the empty string';
  final codeUnits = text.length;
  return '"$text" ($codeUnits code units)';
}
