import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:drift/drift.dart';
import 'package:session/session.dart';
import 'package:store/store.dart';

import 'terminal_protocol.dart';

class TerminalSyncResult {
  const TerminalSyncResult({
    required this.importedReviews,
    required this.skippedReviews,
    required this.sentCards,
  });

  final int importedReviews;
  final int skippedReviews;
  final int sentCards;
}

class TerminalSyncService {
  const TerminalSyncService(this.db, this.study);

  final AppDatabase db;
  final StudyService study;

  Future<TerminalSyncResult> synchronize({
    required TerminalClient client,
    required Set<String> deckIds,
    required int maxCards,
  }) async {
    final reviewResult = await _importReviews(client);
    final bundle = await buildLibraryBundle(deckIds: deckIds, maxCards: maxCards);
    final sent = await client.sendLibrary(bundle);
    await client.acknowledgeReviews();
    return TerminalSyncResult(
      importedReviews: reviewResult.$1,
      skippedReviews: reviewResult.$2,
      sentCards: sent,
    );
  }

  Future<(int, int)> _importReviews(TerminalClient client) async {
    final rows = await client.reviews();
    var imported = 0;
    var skipped = 0;

    for (final remote in rows) {
      final reviewId = remote.id;
      final already = await (db.select(db.reviews)..where((t) => t.id.equals(reviewId)))
          .getSingleOrNull();
      if (already != null) {
        skipped++;
        continue;
      }
      final card = await (db.select(db.cards)
            ..where((t) => t.id.equals(remote.cardId))
            ..where((t) => t.deletedAt.isNull()))
          .getSingleOrNull();
      if (card == null) {
        skipped++;
        continue;
      }
      try {
        await study.ingestRemoteReview(
          id: reviewId,
          cardId: remote.cardId,
          reviewedAt: DateTime.fromMillisecondsSinceEpoch(remote.reviewedAt * 1000, isUtc: true),
          grade: Grade.fromValue(remote.rating),
          source: ReviewSource.standard,
          fromDeviceId: client.pairing.deviceId,
          elapsedMs: remote.responseTimeMs,
        );
        imported++;
      } on ArgumentError {
        skipped++;
      }
    }
    return (imported, skipped);
  }

  Future<Map<String, Object?>> buildLibraryBundle({
    required Set<String> deckIds,
    required int maxCards,
  }) async {
    if (deckIds.isEmpty) throw StateError('Selecione ao menos um baralho.');

    final placeholders = List.filled(deckIds.length, '?').join(',');
    final deckRows = await db.customSelect(
      '''
      SELECT id, name, description, updated_at, server_seq
      FROM decks
      WHERE deleted_at IS NULL
        AND archived_at IS NULL
        AND id IN ($placeholders)
      ORDER BY name COLLATE NOCASE
      ''',
      variables: [for (final id in deckIds) Variable<String>(id)],
      readsFrom: {db.decks},
    ).get();

    final result = await db.customSelect(
      '''
      SELECT
        c.id, c.deck_id, c.front, c.back, c.tags, c.updated_at,
        c.server_seq AS card_server_seq,
        s.due_at, s.last_review_at, s.reps, s.lapses
      FROM cards c
      JOIN decks d ON d.id = c.deck_id
      LEFT JOIN card_states s ON s.card_id = c.id
      LEFT JOIN card_flags f ON f.card_id = c.id
      WHERE c.deleted_at IS NULL
        AND d.deleted_at IS NULL
        AND d.archived_at IS NULL
        AND c.deck_id IN ($placeholders)
        AND COALESCE(f.status, 'active') = 'active'
      ORDER BY d.name COLLATE NOCASE, c.updated_at DESC
      LIMIT ?
      ''',
      variables: [
        for (final id in deckIds) Variable<String>(id),
        Variable<int>(maxCards + 1),
      ],
      readsFrom: {db.cards, db.decks, db.cardStates, db.cardFlags},
    ).get();

    if (result.length > maxCards) {
      throw StateError(
        'Os baralhos selecionados possuem mais de $maxCards cartões ativos, limite atual do protótipo.',
      );
    }

    String iso(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();
    int revision(int? serverSeq, int updatedAt) =>
        serverSeq ?? (updatedAt ~/ 1000).clamp(1, 0x7FFFFFFF).toInt();

    final decks = <String, Map<String, Object?>>{
      for (final row in deckRows)
        row.read<String>('id'): <String, Object?>{
          'schema': 'mnemos.deck/v1',
          'id': row.read<String>('id'),
          'name': row.read<String>('name'),
          'description': row.readNullable<String>('description'),
          'metadata': {
            'language': 'pt-BR',
            'updatedAt': iso(row.read<int>('updated_at')),
            'revision': revision(
              row.readNullable<int>('server_seq'),
              row.read<int>('updated_at'),
            ),
          },
        },
    };
    final cards = <Map<String, Object?>>[];
    final states = <Map<String, Object?>>[];

    for (final row in result) {
      final deckId = row.read<String>('deck_id');
      final updatedAt = row.read<int>('updated_at');
      List<String> tags = const [];
      try {
        tags = [for (final value in jsonDecode(row.read<String>('tags')) as List) value.toString()];
      } catch (_) {}

      cards.add(<String, Object?>{
        'schema': 'mnemos.card/v1',
        'id': row.read<String>('id'),
        'deckId': deckId,
        'type': 'basic',
        'content': {
          'prompt': {'format': 'plain', 'text': row.read<String>('front')},
          'answer': {'format': 'plain', 'text': row.read<String>('back')},
        },
        'tags': tags,
        'metadata': {
          'language': 'pt-BR',
          'createdAt': iso(updatedAt),
          'updatedAt': iso(updatedAt),
          'revision': revision(row.readNullable<int>('card_server_seq'), updatedAt),
        },
      });

      final dueAtMs = row.readNullable<int>('due_at');
      final lastReviewMs = row.readNullable<int>('last_review_at');
      final intervalSeconds = dueAtMs != null && lastReviewMs != null
          ? ((dueAtMs - lastReviewMs) ~/ 1000).clamp(0, 0xFFFFFFFF)
          : 0;
      states.add(<String, Object?>{
        'schema': 'mnemos.card-state/v1',
        'cardId': row.read<String>('id'),
        'dueAt': dueAtMs == null ? 0 : dueAtMs ~/ 1000,
        'lastReviewedAt': lastReviewMs == null ? null : lastReviewMs ~/ 1000,
        'intervalSeconds': intervalSeconds,
        'repetitions': row.readNullable<int>('reps') ?? 0,
        'lapses': row.readNullable<int>('lapses') ?? 0,
        'lastRating': 0,
        'revision': revision(row.readNullable<int>('card_server_seq'), updatedAt),
      });
    }

    return <String, Object?>{
      'schema': 'mnemos.sync/v1',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'decks': decks.values.toList(growable: false),
      'cards': cards,
      'states': states,
    };
  }

}
