import 'package:drift/drift.dart';

import 'tables.dart';

part 'database.g.dart';

/// Local SQLite (§5). Source of truth for everything except generation.
@DriftDatabase(
  tables: [
    Decks,
    Cards,
    CardFlags,
    Reviews,
    ProgressResets,
    GoalHistory,
    CardStates,
    UserSettings,
    LocalSettings,
    SyncState,
    PendingCards,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createSearchIndex();
          await _createImmutabilityTriggers();
        },
        // §5.3 — additive, never a rename. A device that has been offline for
        // a month arrives here, not at a fresh install.
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(reviews, reviews.schedulerVersion);
            await m.addColumn(reviews, reviews.appVersion);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// §5.10 requires search over cards.
  ///
  /// `remove_diacritics 2` is not optional in Portuguese: without it,
  /// searching "funcao" does not find "função" and the feature reads as
  /// broken. Kept in sync by trigger, so no caller can forget.
  Future<void> _createSearchIndex() async {
    await customStatement('''
      CREATE VIRTUAL TABLE cards_fts USING fts5(
        front, back, content='cards', content_rowid='rowid',
        tokenize="unicode61 remove_diacritics 2"
      )
    ''');
    await customStatement('''
      CREATE TRIGGER cards_fts_insert AFTER INSERT ON cards BEGIN
        INSERT INTO cards_fts(rowid, front, back) VALUES (new.rowid, new.front, new.back);
      END
    ''');
    await customStatement('''
      CREATE TRIGGER cards_fts_delete AFTER DELETE ON cards BEGIN
        INSERT INTO cards_fts(cards_fts, rowid, front, back)
        VALUES ('delete', old.rowid, old.front, old.back);
      END
    ''');
    await customStatement('''
      CREATE TRIGGER cards_fts_update AFTER UPDATE ON cards BEGIN
        INSERT INTO cards_fts(cards_fts, rowid, front, back)
        VALUES ('delete', old.rowid, old.front, old.back);
        INSERT INTO cards_fts(rowid, front, back) VALUES (new.rowid, new.front, new.back);
      END
    ''');
  }

  /// §5.2 — append-only, enforced by the database.
  ///
  /// §3's guarantee is only as strong as its weakest caller, so it does not
  /// depend on every future write path remembering.
  ///
  /// Immutability protects the **event**, not the row's sync bookkeeping.
  /// `server_seq` arrives after the fact — it is how the client learns the
  /// server accepted the row (§6.4) — so a blanket UPDATE ban would make the
  /// outbox impossible to clear. The triggers therefore fire only when a
  /// historical fact changes.
  ///
  /// The server does not need this distinction: there the row is inserted with
  /// its `server_seq` already assigned, so no UPDATE ever happens.
  Future<void> _createImmutabilityTriggers() async {
    const facts = {
      'reviews': 'old.id != new.id OR old.card_id != new.card_id '
          'OR old.reviewed_at != new.reviewed_at OR old.grade != new.grade '
          'OR old.source != new.source',
      'progress_resets': 'old.id != new.id OR old.card_id != new.card_id '
          'OR old.reset_at != new.reset_at',
    };

    for (final entry in facts.entries) {
      await customStatement('''
        CREATE TRIGGER ${entry.key}_no_update BEFORE UPDATE ON ${entry.key}
        WHEN ${entry.value}
        BEGIN
          SELECT RAISE(ABORT, '${entry.key} is append-only (spec section 3)');
        END
      ''');
      await customStatement('''
        CREATE TRIGGER ${entry.key}_no_delete BEFORE DELETE ON ${entry.key} BEGIN
          SELECT RAISE(ABORT, '${entry.key} is append-only (spec section 3)');
        END
      ''');
    }
  }

  /// Cards searchable by accent-insensitive text (§5.10).
  Future<List<String>> searchCardIds(String query) async {
    if (query.trim().isEmpty) return const [];
    final rows = await customSelect(
      '''
      SELECT c.id FROM cards_fts f
      JOIN cards c ON c.rowid = f.rowid
      WHERE cards_fts MATCH ?1 AND c.deleted_at IS NULL
      ORDER BY rank
      LIMIT 100
      ''',
      variables: [Variable<String>('${query.trim()}*')],
      readsFrom: {cards},
    ).get();
    return rows.map((r) => r.read<String>('id')).toList();
  }

  /// Today's queue (§5.8): due, not suspended, not still buried.
  Future<List<String>> dueCardIds(DateTime now, {int limit = 200}) async {
    final rows = await customSelect(
      '''
      SELECT s.card_id FROM card_states s
      JOIN cards c ON c.id = s.card_id
      LEFT JOIN card_flags f ON f.card_id = s.card_id
      WHERE c.deleted_at IS NULL
        AND s.due_at IS NOT NULL
        AND s.due_at <= ?1
        AND s.dirty = 0
        AND COALESCE(f.status, 'active') = 'active'
        AND (f.buried_until IS NULL OR f.buried_until <= ?1)
      ORDER BY s.due_at
      LIMIT ?2
      ''',
      variables: [
        Variable<int>(now.toUtc().millisecondsSinceEpoch),
        Variable<int>(limit),
      ],
      readsFrom: {cardStates, cards, cardFlags},
    ).get();
    return rows.map((r) => r.read<String>('card_id')).toList();
  }

  /// Marks a card for full replay (§5.3).
  Future<void> markDirty(String cardId) async {
    await (update(cardStates)..where((t) => t.cardId.equals(cardId)))
        .write(const CardStatesCompanion(dirty: Value(true)));
  }
}
