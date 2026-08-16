/// Local SQLite persistence (§4).
///
/// Owns tables and queries; knows nothing about FSRS. Depends on `domain`
/// alone, and the package boundary is what enforces the direction (§12.1).
library;

export 'src/database.dart';
export 'src/search.dart';
export 'src/day.dart';
export 'src/tables.dart';
