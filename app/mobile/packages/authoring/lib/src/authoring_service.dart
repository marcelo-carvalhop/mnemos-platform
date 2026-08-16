import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:drift/drift.dart';
import 'package:store/store.dart';

/// Deck and card authoring (§5.1, §5.4, §5.10).
///
/// Every write goes through here so the invariants have one home: a deck tree
/// that cannot cycle, a character limit that is a rule rather than a
/// suggestion, and edits that never disturb a card's schedule.

/// §5.1 — a tree without a cap grows until some query walks it and stalls.
const int kMaxDeckDepth = 5;

class DeckCycle implements Exception {
  const DeckCycle(this.message);
  final String message;
  @override
  String toString() => 'DeckCycle: $message';
}

class DeckTooDeep implements Exception {
  const DeckTooDeep(this.message);
  final String message;
  @override
  String toString() => 'DeckTooDeep: $message';
}

/// §5.4 — the limit is a rule, not a suggestion. It exists because of the
/// device screen, and it happens to coincide with good practice.
class CardTooLong implements Exception {
  const CardTooLong(this.side, this.length, this.limit);
  final String side;
  final int length;
  final int limit;

  @override
  String toString() =>
      'CardTooLong: $side has $length graphemes, limit is $limit';
}

class AuthoringService {
  AuthoringService(this.db, {required this.deviceId});

  final AppDatabase db;
  final String deviceId;

  int _ms(DateTime t) => t.toUtc().millisecondsSinceEpoch;

  // -------------------------------------------------------------------------
  // Decks (§5.1)
  // -------------------------------------------------------------------------

  Future<String> createDeck({
    required String name,
    required DateTime at,
    String? parentId,
    String? description,
    String? id,
  }) async {
    final deckId = id ?? Uuid7.generate(now: at);
    if (parentId != null) {
      await _assertDepthAllows(parentId);
    }

    await db.into(db.decks).insert(
          DecksCompanion.insert(
            id: deckId,
            name: name,
            updatedAt: _ms(at),
            deviceId: deviceId,
            parentId: Value(parentId),
            description: Value(description),
          ),
        );
    return deckId;
  }

  Future<void> renameDeck(String deckId, String name, DateTime at) async {
    await (db.update(db.decks)..where((t) => t.id.equals(deckId))).write(
      DecksCompanion(
        name: Value(name),
        updatedAt: Value(_ms(at)),
        deviceId: Value(deviceId),
        // Cleared so the outbox picks the row up again (§6.4).
        serverSeq: const Value(null),
      ),
    );
  }

  /// Reparents a deck, rejecting anything that would corrupt the tree.
  ///
  /// A cycle is not a theoretical concern: dragging a deck onto its own child
  /// is an ordinary gesture, and the result is a subtree that no traversal can
  /// terminate on. Checked here *and* on the server (§5.1), because a client
  /// is not a trust boundary.
  Future<void> moveDeck(String deckId, String? newParentId, DateTime at) async {
    if (newParentId != null) {
      if (newParentId == deckId) {
        throw const DeckCycle('a deck cannot be its own parent');
      }
      if (await _isDescendant(candidate: newParentId, of: deckId)) {
        throw DeckCycle('$newParentId is inside $deckId');
      }
      await _assertDepthAllows(newParentId, movingSubtreeOf: deckId);
    }

    await (db.update(db.decks)..where((t) => t.id.equals(deckId))).write(
      DecksCompanion(
        parentId: Value(newParentId),
        updatedAt: Value(_ms(at)),
        deviceId: Value(deviceId),
        serverSeq: const Value(null),
      ),
    );
  }

  /// Excluded from study, but keeps its cards and their history (§5.1).
  Future<void> archiveDeck(String deckId, DateTime at) async {
    await (db.update(db.decks)..where((t) => t.id.equals(deckId))).write(
      DecksCompanion(
        archivedAt: Value(_ms(at)),
        updatedAt: Value(_ms(at)),
        deviceId: Value(deviceId),
        serverSeq: const Value(null),
      ),
    );
  }

  /// Soft-deletes the deck **and its whole subtree** (§5.1).
  ///
  /// Deleting only the parent would leave orphans that no screen can reach and
  /// no query excludes — invisible cards that still come due.
  Future<int> deleteDeck(String deckId, DateTime at) async {
    final ids = await subtreeOf(deckId);
    for (final id in ids) {
      await (db.update(db.decks)..where((t) => t.id.equals(id))).write(
        DecksCompanion(
          deletedAt: Value(_ms(at)),
          updatedAt: Value(_ms(at)),
          deviceId: Value(deviceId),
          serverSeq: const Value(null),
        ),
      );
      await (db.update(db.cards)..where((t) => t.deckId.equals(id))).write(
        CardsCompanion(
          deletedAt: Value(_ms(at)),
          updatedAt: Value(_ms(at)),
          deviceId: Value(deviceId),
          serverSeq: const Value(null),
        ),
      );
    }
    return ids.length;
  }

  /// The deck and every descendant, deepest last.
  Future<List<String>> subtreeOf(String deckId) async {
    final rows = await db.customSelect(
      '''
      WITH RECURSIVE tree(id) AS (
        SELECT id FROM decks WHERE id = ?1
        UNION
        SELECT d.id FROM decks d JOIN tree ON d.parent_id = tree.id
      )
      SELECT id FROM tree
      ''',
      variables: [Variable<String>(deckId)],
      readsFrom: {db.decks},
    ).get();
    return rows.map((r) => r.read<String>('id')).toList();
  }

  Future<int> depthOf(String deckId) async {
    var depth = 0;
    String? current = deckId;
    final seen = <String>{};

    while (current != null) {
      if (!seen.add(current)) {
        // Defensive: a cycle that reached the database anyway must not hang
        // the caller. It cannot happen through this service.
        throw DeckCycle('cycle detected at $current');
      }
      final row =
          await (db.select(db.decks)..where((t) => t.id.equals(current!))).getSingleOrNull();
      current = row?.parentId;
      if (current != null) depth++;
    }
    return depth;
  }

  Future<bool> _isDescendant({required String candidate, required String of}) async {
    return (await subtreeOf(of)).contains(candidate);
  }

  Future<void> _assertDepthAllows(String parentId, {String? movingSubtreeOf}) async {
    final parentDepth = await depthOf(parentId);
    var subtreeHeight = 0;

    if (movingSubtreeOf != null) {
      for (final id in await subtreeOf(movingSubtreeOf)) {
        final relative = await depthOf(id) - await depthOf(movingSubtreeOf);
        if (relative > subtreeHeight) subtreeHeight = relative;
      }
    }

    if (parentDepth + 1 + subtreeHeight > kMaxDeckDepth) {
      throw DeckTooDeep(
        'nesting would reach ${parentDepth + 1 + subtreeHeight}, limit is $kMaxDeckDepth',
      );
    }
  }

  // -------------------------------------------------------------------------
  // Cards (§5.4)
  // -------------------------------------------------------------------------

  /// Validates a card the way the editor's counter does.
  ///
  /// The client shows the count live and the server re-checks after generation
  /// (§7.6); this is the same rule for the manual path, so the three cannot
  /// disagree.
  static void validate({required String front, required String back}) {
    final frontLength = CardText.graphemeLength(front);
    if (frontLength > kFrontMaxGraphemes) {
      throw CardTooLong('front', frontLength, kFrontMaxGraphemes);
    }
    final backLength = CardText.graphemeLength(back);
    if (backLength > kBackMaxGraphemes) {
      throw CardTooLong('back', backLength, kBackMaxGraphemes);
    }
  }

  Future<String> createCard({
    required String deckId,
    required String front,
    required String back,
    required DateTime at,
    List<String> tags = const [],
    String? id,
  }) async {
    validate(front: front, back: back);
    final cardId = id ?? Uuid7.generate(now: at);

    await db.into(db.cards).insert(
          CardsCompanion.insert(
            id: cardId,
            deckId: deckId,
            front: front,
            back: back,
            updatedAt: _ms(at),
            deviceId: deviceId,
            tags: Value(jsonEncode(tags)),
          ),
        );
    return cardId;
  }

  /// Edits content. **Never touches the schedule** (§3).
  ///
  /// Content and schedule live in different tables, so this is structural
  /// rather than a rule someone has to remember: correcting a comma cannot
  /// throw away months of history.
  Future<void> editCard({
    required String cardId,
    required DateTime at,
    String? front,
    String? back,
    List<String>? tags,
  }) async {
    final existing =
        await (db.select(db.cards)..where((t) => t.id.equals(cardId))).getSingle();

    validate(front: front ?? existing.front, back: back ?? existing.back);

    await (db.update(db.cards)..where((t) => t.id.equals(cardId))).write(
      CardsCompanion(
        front: front == null ? const Value.absent() : Value(front),
        back: back == null ? const Value.absent() : Value(back),
        tags: tags == null ? const Value.absent() : Value(jsonEncode(tags)),
        updatedAt: Value(_ms(at)),
        deviceId: Value(deviceId),
        serverSeq: const Value(null),
      ),
    );
  }

  Future<void> deleteCard(String cardId, DateTime at) async {
    await (db.update(db.cards)..where((t) => t.id.equals(cardId))).write(
      CardsCompanion(
        deletedAt: Value(_ms(at)),
        updatedAt: Value(_ms(at)),
        deviceId: Value(deviceId),
        serverSeq: const Value(null),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Bulk operations (§5.10)
  // -------------------------------------------------------------------------

  Future<int> moveCards(List<String> cardIds, String deckId, DateTime at) async {
    if (cardIds.isEmpty) return 0;
    return (db.update(db.cards)..where((t) => t.id.isIn(cardIds))).write(
      CardsCompanion(
        deckId: Value(deckId),
        updatedAt: Value(_ms(at)),
        deviceId: Value(deviceId),
        serverSeq: const Value(null),
      ),
    );
  }

  /// Adds tags without dropping the ones already there.
  ///
  /// Tags are a column, not a join table (§5.1) — a join table has nowhere to
  /// put a tombstone, so a removed tag reappears on the next sync.
  Future<int> addTags(List<String> cardIds, List<String> tags, DateTime at) async {
    var touched = 0;
    for (final cardId in cardIds) {
      final row =
          await (db.select(db.cards)..where((t) => t.id.equals(cardId))).getSingleOrNull();
      if (row == null) continue;

      final current = (jsonDecode(row.tags) as List).cast<String>();
      final merged = {...current, ...tags.map((t) => t.trim().toLowerCase())}
        ..removeWhere((t) => t.isEmpty);

      await (db.update(db.cards)..where((t) => t.id.equals(cardId))).write(
        CardsCompanion(
          tags: Value(jsonEncode(merged.toList())),
          updatedAt: Value(_ms(at)),
          deviceId: Value(deviceId),
          serverSeq: const Value(null),
        ),
      );
      touched++;
    }
    return touched;
  }

  Future<int> deleteCards(List<String> cardIds, DateTime at) async {
    if (cardIds.isEmpty) return 0;
    return (db.update(db.cards)..where((t) => t.id.isIn(cardIds))).write(
      CardsCompanion(
        deletedAt: Value(_ms(at)),
        updatedAt: Value(_ms(at)),
        deviceId: Value(deviceId),
        serverSeq: const Value(null),
      ),
    );
  }

  /// Cards in a deck, filterable by tag and state — the list of §5.10.
  Future<List<String>> listCards({
    String? deckId,
    String? tag,
    String? status,
  }) async {
    final rows = await db.customSelect(
      '''
      SELECT c.id FROM cards c
      LEFT JOIN card_flags f ON f.card_id = c.id
      WHERE c.deleted_at IS NULL
        AND (?1 IS NULL OR c.deck_id = ?1)
        AND (?2 IS NULL OR c.tags LIKE '%"' || ?2 || '"%')
        AND (?3 IS NULL OR COALESCE(f.status, 'active') = ?3)
      ORDER BY c.id
      ''',
      variables: [
        Variable<String>(deckId),
        Variable<String>(tag),
        Variable<String>(status),
      ],
      readsFrom: {db.cards, db.cardFlags},
    ).get();
    return rows.map((r) => r.read<String>('id')).toList();
  }
}
