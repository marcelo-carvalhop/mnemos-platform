/// Entities, value types and the generated contract.
///
/// This package depends on nothing — not Flutter, not storage, not IO. It sits
/// at the bottom of the dependency direction stated in §4:
/// `features → sync → store → domain`, with `scheduler` hanging off `domain`
/// alone. The package boundary is what enforces that (§12.1): a package cannot
/// import upward without declaring the dependency in its pubspec.
library;

export 'src/contract.g.dart';
export 'src/entities.dart';
export 'src/ids.dart';
export 'src/text.dart';
