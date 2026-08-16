import 'package:drift/drift.dart';

/// Local schema (§5). Three tiers, distinguished by how they sync.
///
/// Timestamps are stored as UTC milliseconds (§5.7). Day boundaries are
/// computed at query time from the stored IANA timezone and cutoff hour —
/// storing local dates is how a streak breaks when the user flies to Lisbon.

// ---------------------------------------------------------------------------
// Tier 1 — content, two-way LWW
// ---------------------------------------------------------------------------

class Decks extends Table {
  TextColumn get id => text()();
  TextColumn get parentId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();

  /// Reserved and unused in v1; §7 needs shared decks not to force a migration.
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get author => text().nullable()();
  TextColumn get license => text().nullable()();
  TextColumn get origin => text().withDefault(const Constant('own'))();
  TextColumn get sourceDeckId => text().nullable()();

  IntColumn get archivedAt => integer().nullable()();

  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get deviceId => text()();

  /// Null while the row still sits in the outbox (§6.2).
  IntColumn get serverSeq => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Cards extends Table {
  TextColumn get id => text()();
  TextColumn get deckId => text()();
  TextColumn get front => text()();
  TextColumn get back => text()();

  /// A value of the card, not a join table (§5.1): a join table has nowhere to
  /// put a tombstone, so a tag removed offline reappears on sync. Stored as a
  /// JSON array.
  TextColumn get tags => text().withDefault(const Constant('[]'))();

  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get deviceId => text()();
  IntColumn get serverSeq => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Volatile per-card state, split from [Cards] on purpose (§5.1).
///
/// Row-level LWW loses concurrent edits to different fields of one row:
/// burying on the phone while fixing a typo on the tablet would discard one of
/// them.
class CardFlags extends Table {
  TextColumn get cardId => text()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  IntColumn get buriedUntil => integer().nullable()();

  IntColumn get updatedAt => integer()();
  TextColumn get deviceId => text()();
  IntColumn get serverSeq => integer().nullable()();

  @override
  Set<Column> get primaryKey => {cardId};
}

// ---------------------------------------------------------------------------
// Tier 2 — history, append-only, merged by union
// ---------------------------------------------------------------------------

/// Immutable (§3, §5.2). A trigger rejects UPDATE and DELETE — the guarantee
/// is only as strong as its weakest caller, so it is not left to convention.
class Reviews extends Table {
  TextColumn get id => text()();
  TextColumn get cardId => text()();
  IntColumn get reviewedAt => integer()();
  IntColumn get grade => integer()();
  TextColumn get source => text()();
  IntColumn get elapsedMs => integer().nullable()();
  TextColumn get deviceId => text()();
  IntColumn get serverSeq => integer().nullable()();

  /// Written once, advisory, never authoritative (§5.2).
  IntColumn get intervalDaysAfter => integer().nullable()();
  RealColumn get stabilityAfter => real().nullable()();
  RealColumn get difficultyAfter => real().nullable()();

  /// §5.2 — what the app actually did at the time, so an algorithm change
  /// later can be reasoned about. Present on the server since the first
  /// migration; the client was missing them, which is how a pull of another
  /// device's reviews came to fail on an unknown column.
  IntColumn get schedulerVersion => integer().nullable()();
  TextColumn get appVersion => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// §5.10 — resets the schedule without deleting history (§3).
class ProgressResets extends Table {
  TextColumn get id => text()();
  TextColumn get cardId => text()();
  IntColumn get resetAt => integer()();
  TextColumn get deviceId => text()();
  IntColumn get serverSeq => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// §9 — records the change, not a daily snapshot.
///
/// The streak needs the goal in force on a past day; a setting only holds
/// today's. Append-only, so it merges by union and survives a reinstall.
class GoalHistory extends Table {
  TextColumn get id => text()();

  /// Local date as `YYYY-MM-DD`, already bucketed by the day-cutoff rule.
  TextColumn get effectiveFromLocalDate => text()();
  IntColumn get dailyGoal => integer()();
  IntColumn get createdAt => integer()();
  TextColumn get deviceId => text()();
  IntColumn get serverSeq => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Tier 3 — derived, never synced, rebuildable
// ---------------------------------------------------------------------------

class CardStates extends Table {
  TextColumn get cardId => text()();
  RealColumn get stability => real().withDefault(const Constant(0))();
  RealColumn get difficulty => real().withDefault(const Constant(0))();
  IntColumn get dueAt => integer().nullable()();
  IntColumn get lastReviewAt => integer().nullable()();
  IntColumn get reps => integer().withDefault(const Constant(0))();
  IntColumn get lapses => integer().withDefault(const Constant(0))();
  TextColumn get phase => text().withDefault(const Constant('newCard'))();
  IntColumn get step => integer().nullable()();

  /// Incremental-replay watermark as a `(reviewedAt, id)` pair (§5.3).
  ///
  /// A single review id is not enough: with two-way history sync a review can
  /// arrive **out of order**, and incremental replay would silently skip it.
  IntColumn get computedThroughReviewedAt => integer().nullable()();
  TextColumn get computedThroughReviewId => text().nullable()();

  /// Set when an out-of-order review lands below the watermark, or when the
  /// FSRS parameters change. A background pass fully replays these cards.
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();
  IntColumn get fsrsParamsVersion => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {cardId};
}

// ---------------------------------------------------------------------------
// Device-local
// ---------------------------------------------------------------------------

/// Settings that are inputs to the schedule (§5.4).
///
/// `desiredRetention` and the FSRS vector are not preferences: they are terms
/// in the interval formula, and device-local they would make two devices
/// compute different due dates from identical histories (§3.1). Named to match
/// the server and the wire, so the sync protocol needs no table-name mapping
/// to get wrong.
class UserSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  IntColumn get updatedAt => integer()();
  TextColumn get deviceId => text()();
  IntColumn get serverSeq => integer().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Settings that never leave the device (§5.4): TTS voice, theme, the hour a
/// notification fires. Nothing here can change what a card's due date is, so
/// nothing here needs to travel.
class LocalSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class SyncState extends Table {
  /// Not `tableName`: drift's own `Table.tableName` occupies that name, and
  /// declaring a column with it fails to compile with a confusing override
  /// error rather than a naming one.
  TextColumn get entity => text()();
  IntColumn get lastPulledSeq => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {entity};
}

/// Server-owned, pulled down and drained locally (§5.4).
class PendingCards extends Table {
  TextColumn get id => text()();
  TextColumn get jobId => text()();
  TextColumn get deckId => text()();
  TextColumn get front => text()();
  TextColumn get back => text()();
  TextColumn get tags => text().withDefault(const Constant('[]'))();
  IntColumn get position => integer().withDefault(const Constant(0))();

  /// The one column the client writes; it pushes back like any mutation.
  TextColumn get decision => text().nullable()();
  IntColumn get decidedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
