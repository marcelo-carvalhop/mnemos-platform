/// Deck and card authoring (§5.1, §5.4, §5.10).
///
/// One home for the invariants: a deck tree that cannot cycle, a character
/// limit that is a rule rather than a suggestion, and edits that never disturb
/// a card's schedule.
library;

export 'src/authoring_service.dart';
