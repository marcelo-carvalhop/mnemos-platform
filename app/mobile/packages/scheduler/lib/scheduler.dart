/// FSRS scheduling — pure Dart, zero IO, no ambient clock, no randomness.
///
/// Depends on `domain` alone (§4). The package boundary is what enforces that:
/// a package cannot import upward without declaring it in its pubspec (§12.1).
library;

export 'src/fsrs_scheduler.dart';
