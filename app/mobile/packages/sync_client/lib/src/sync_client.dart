import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:store/store.dart';

/// The client half of §6.
///
/// The server is a backup and a meeting point, not the source of truth: local
/// SQLite is. This drains the outbox into it and applies what other devices
/// wrote back, and it is deliberately the only place that knows the order
/// those two things must happen in.

/// Dependency order (§6.4).
///
/// A card pushed before its deck arrives references a row the server has never
/// seen and the foreign key rejects it. History goes last because it points at
/// cards.
const List<String> kPushOrder = [
  'decks',
  'cards',
  'card_flags',
  'user_settings',
  'reviews',
  'progress_resets',
  'goal_history',
];

/// Pull order is the same: applying a card before its deck would break the
/// same reference locally.
const List<String> kPullOrder = kPushOrder;

class PushResult {
  const PushResult({required this.applied, required this.assignedSeqs});
  final int applied;

  /// Row id → the `server_seq` the server assigned it.
  final Map<String, int> assignedSeqs;
}

/// Signals §6.3: the device's cursor predates the tombstone horizon.
class ResyncRequired implements Exception {
  const ResyncRequired(this.message);
  final String message;
  @override
  String toString() => 'ResyncRequired: $message';
}

/// The transport. An interface so the loop is testable without a server —
/// the interesting failures here are ordering and idempotency, not HTTP.
abstract interface class SyncApi {
  Future<PushResult> push(String table, List<Map<String, Object?>> rows, String idempotencyKey);

  /// Throws [ResyncRequired] when the cursor is too old.
  Future<({List<Map<String, Object?>> rows, int cursor, bool hasMore})> pull(
    String table,
    int since,
    int limit,
  );
}

class SyncClient {
  SyncClient(this.db, this.api, {this.chunkSize = 200});

  final AppDatabase db;
  final SyncApi api;
  final int chunkSize;

  // -------------------------------------------------------------------------
  // Push
  // -------------------------------------------------------------------------

  /// Sends everything the server has not acknowledged.
  ///
  /// The outbox is `server_seq IS NULL` — no second table to fall out of step
  /// with the rows it describes. Coalescing is therefore free: the row carries
  /// its current state, so ten offline typo fixes are one push (§6.4).
  Future<int> pushAll() async {
    var total = 0;
    for (final table in kPushOrder) {
      total += await _pushTable(table);
    }
    return total;
  }

  Future<int> _pushTable(String table) async {
    var pushed = 0;

    while (true) {
      final rows = await _pendingRows(table, limit: chunkSize);
      if (rows.isEmpty) break;

      // Derived from the content, so a retry after a timeout carries the same
      // key and the server can recognise it (§6.4).
      final key = _idempotencyKey(table, rows);
      final result = await api.push(table, rows, key);

      await _acknowledge(table, result.assignedSeqs);
      pushed += result.applied;

      if (rows.length < chunkSize) break;
    }
    return pushed;
  }

  Future<List<Map<String, Object?>>> _pendingRows(String table, {required int limit}) async {
    final rows = await db.customSelect(
      'SELECT * FROM $table WHERE server_seq IS NULL LIMIT ?1',
      variables: [Variable<int>(limit)],
    ).get();
    return rows.map((r) => Map<String, Object?>.from(r.data)).toList();
  }

  Future<void> _acknowledge(String table, Map<String, int> assigned) async {
    if (assigned.isEmpty) return;
    final key = table == 'card_flags'
        ? 'card_id'
        : table == 'user_settings'
            ? 'key'
            : 'id';

    await db.transaction(() async {
      for (final entry in assigned.entries) {
        await db.customStatement(
          'UPDATE $table SET server_seq = ? WHERE $key = ?',
          [entry.value, entry.key],
        );
      }
    });
  }

  String _idempotencyKey(String table, List<Map<String, Object?>> rows) {
    final ids = rows.map((r) => r['id'] ?? r['card_id'] ?? r['key']).join(',');
    return '$table:${ids.hashCode}';
  }

  // -------------------------------------------------------------------------
  // Pull
  // -------------------------------------------------------------------------

  /// Applies every delta since the stored cursor.
  ///
  /// On [ResyncRequired] the local mirror of tiers 1 and 2 is discarded and
  /// everything is pulled from zero (§6.3) — but **the outbox is pushed
  /// first**, so nothing local is lost.
  Future<int> pullAll() async {
    var applied = 0;
    for (final table in kPullOrder) {
      try {
        applied += await _pullTable(table);
      } on ResyncRequired {
        await pushAll();
        await _resetCursors();
        applied += await _pullTable(table);
      }
    }
    return applied;
  }

  Future<int> _pullTable(String table) async {
    var applied = 0;

    while (true) {
      final cursor = await cursorFor(table);
      final page = await api.pull(table, cursor, chunkSize);
      if (page.rows.isEmpty) break;

      await db.transaction(() async {
        for (final row in page.rows) {
          await _apply(table, row);
        }
        await _setCursor(table, page.cursor);
      });

      applied += page.rows.length;
      if (!page.hasMore) break;
    }
    return applied;
  }

  /// Applies one incoming row.
  ///
  /// History merges by union — the row is inserted or ignored, never
  /// overwritten (§6.1). Entities merge by last-writer-wins, evaluated locally
  /// with the same rule the server uses, so both sides converge on the same
  /// answer rather than trusting whoever spoke last.
  /// Columns each local table actually has, read once per table.
  ///
  /// §5.3 says schema changes are additive and devices run several versions
  /// behind, which means the server routinely sends columns this build has
  /// never heard of. Passing them straight into an INSERT throws — and the
  /// throw happens inside a background sync, so it is invisible: on a real
  /// device the pull of `reviews` died on `scheduler_version` and the only
  /// trace was a line in logcat.
  final Map<String, Set<String>> _localColumns = {};

  Future<Set<String>> _columnsOf(String table) async {
    final cached = _localColumns[table];
    if (cached != null) return cached;

    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    final names = {for (final r in rows) r.read<String>('name')};
    _localColumns[table] = names;
    return names;
  }

  Future<void> _apply(String table, Map<String, Object?> row) async {
    final known = await _columnsOf(table);
    row = {
      for (final entry in row.entries)
        if (known.contains(entry.key)) entry.key: entry.value,
    };

    final isHistory = table == 'reviews' ||
        table == 'progress_resets' ||
        table == 'goal_history';

    final columns = row.keys.toList();
    final placeholders = List.filled(columns.length, '?').join(',');
    final values = columns.map((c) => _bind(row[c])).toList();

    if (isHistory) {
      await db.customStatement(
        'INSERT OR IGNORE INTO $table (${columns.join(",")}) VALUES ($placeholders)',
        values,
      );
      return;
    }

    final key = table == 'card_flags'
        ? 'card_id'
        : table == 'user_settings'
            ? 'key'
            : 'id';

    final existing = await db.customSelect(
      'SELECT updated_at, device_id FROM $table WHERE $key = ?1',
      variables: [Variable<String>(row[key] as String)],
    ).getSingleOrNull();

    if (existing != null) {
      final localAt = existing.read<int>('updated_at');
      final localDevice = existing.read<String>('device_id');
      final remoteAt = row['updated_at'] as int;
      final remoteDevice = row['device_id'] as String;

      final remoteWins = remoteAt > localAt ||
          (remoteAt == localAt && remoteDevice.compareTo(localDevice) > 0);
      if (!remoteWins) return;
    }

    final assignments = columns.map((c) => '$c=excluded.$c').join(',');
    await db.customStatement(
      'INSERT INTO $table (${columns.join(",")}) VALUES ($placeholders) '
      'ON CONFLICT($key) DO UPDATE SET $assignments',
      values,
    );
  }

  Object? _bind(Object? value) {
    if (value is bool) return value ? 1 : 0;
    if (value is List || value is Map) return jsonEncode(value);
    return value;
  }

  // -------------------------------------------------------------------------
  // Cursors (§6.2)
  // -------------------------------------------------------------------------

  Future<int> cursorFor(String table) async {
    final row = await (db.select(db.syncState)..where((t) => t.entity.equals(table)))
        .getSingleOrNull();
    return row?.lastPulledSeq ?? 0;
  }

  Future<void> _setCursor(String table, int seq) async {
    await db.into(db.syncState).insertOnConflictUpdate(
          SyncStateCompanion.insert(entity: table, lastPulledSeq: Value(seq)),
        );
  }

  Future<void> _resetCursors() async {
    await db.delete(db.syncState).go();
  }

  /// Full round trip. Push before pull, so a device that has been away does
  /// not receive its own edits back as if they were someone else's.
  Future<({int pushed, int pulled})> syncNow() async {
    final pushed = await pushAll();
    final pulled = await pullAll();
    return (pushed: pushed, pulled: pulled);
  }

  /// Rows still waiting for the server.
  Future<int> outboxDepth() async {
    var total = 0;
    for (final table in kPushOrder) {
      final row = await db
          .customSelect('SELECT COUNT(*) AS n FROM $table WHERE server_seq IS NULL')
          .getSingle();
      total += row.read<int>('n');
    }
    return total;
  }
}
