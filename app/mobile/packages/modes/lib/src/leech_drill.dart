import 'package:domain/domain.dart';
import 'package:drift/drift.dart';
import 'package:store/store.dart';

/// A card that keeps being forgotten, with the count that says so.
class LeechCard {
  const LeechCard({
    required this.cardId,
    required this.front,
    required this.back,
    required this.lapses,
  });

  final String cardId;
  final String front;
  final String back;

  /// Lapses **since the last progress reset**, so a card the user chose to
  /// start over on is not still labelled a leech (§5.10).
  final int lapses;
}

/// "Só os que erro muito" (§5.9).
///
/// Extra practice, not a review. It takes no [StudyService] and holds no
/// writing method: the guarantee that it cannot distort the schedule is
/// structural, not a promise in a comment. The interface still has to say so
/// out loud — §5.9 is explicit that a user who thinks this is getting work
/// done will wreck their own schedule.
class LeechDrill {
  const LeechDrill(this.db);

  final AppDatabase db;

  /// The cards with the most lapses, worst first.
  ///
  /// Counted from the review log rather than from `card_state`, because the
  /// log is the only source of truth (§3) and a rebuilt cache may not have
  /// caught up yet.
  Future<List<LeechCard>> select({
    int limit = 20,
    int minLapses = kLeechMinLapses,
  }) async {
    final rows = await db.customSelect(
      '''
      SELECT c.id AS card_id, c.front AS front, c.back AS back,
             COUNT(*) AS lapses
        FROM reviews r
        JOIN cards c ON c.id = r.card_id
       WHERE r.grade = ?
         AND c.deleted_at IS NULL
         AND r.reviewed_at > COALESCE(
               (SELECT MAX(pr.reset_at) FROM progress_resets pr
                 WHERE pr.card_id = c.id), -1)
       GROUP BY c.id
      HAVING COUNT(*) >= ?
       ORDER BY lapses DESC, c.id
       LIMIT ?
      ''',
      variables: [
        Variable<int>(Grade.again.value),
        Variable<int>(minLapses),
        Variable<int>(limit),
      ],
      readsFrom: {db.reviews, db.cards, db.progressResets},
    ).get();

    return [
      for (final row in rows)
        LeechCard(
          cardId: row.read<String>('card_id'),
          front: row.read<String>('front'),
          back: row.read<String>('back'),
          lapses: row.read<int>('lapses'),
        ),
    ];
  }
}
