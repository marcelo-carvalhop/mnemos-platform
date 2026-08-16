import 'package:characters/characters.dart';

import 'contract.g.dart';

/// Card text measurement (§7.6).
///
/// The limit is counted in **grapheme clusters**, not code units. Dart's
/// `String.length` counts UTF-16 code units and Python's `len()` counts code
/// points; for "ção" both happen to return 3, but a decomposed combining
/// accent gives a different answer in each while the user sees no difference.
/// The result of using either is an editor that accepts text the server drops.
///
/// Grapheme clusters give the same count for composed and decomposed forms,
/// which is exactly why they are the unit. NFC normalisation is a separate
/// concern — it makes stored bytes consistent so that two devices editing the
/// same visible text produce equal rows for LWW (§6.1) — and never changes
/// what [graphemeLength] returns.
abstract final class CardText {
  /// Number of user-perceived characters in [text].
  static int graphemeLength(String text) => text.characters.length;

  /// True when the front side is within [kFrontMaxGraphemes].
  static bool frontFits(String front) =>
      graphemeLength(front) <= kFrontMaxGraphemes;

  /// True when the back side is within [kBackMaxGraphemes].
  static bool backFits(String back) => graphemeLength(back) <= kBackMaxGraphemes;

  /// Graphemes remaining before the front limit; negative when over.
  static int frontRemaining(String front) =>
      kFrontMaxGraphemes - graphemeLength(front);

  /// Graphemes remaining before the back limit; negative when over.
  static int backRemaining(String back) =>
      kBackMaxGraphemes - graphemeLength(back);

  /// Truncates to [maxGraphemes] without splitting a cluster.
  ///
  /// Not used by the generation pipeline — §7.6 drops oversized cards rather
  /// than truncating them, because a card cut mid-sentence is worse than one
  /// fewer card. This exists for input affordances such as paste handling.
  static String truncateToGraphemes(String text, int maxGraphemes) {
    final chars = text.characters;
    if (chars.length <= maxGraphemes) return text;
    return chars.take(maxGraphemes).toString();
  }
}
