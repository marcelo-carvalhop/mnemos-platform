import 'package:domain/domain.dart' as d;
import 'package:drift/drift.dart';
import 'package:scheduler/scheduler.dart';
import 'package:store/store.dart';

/// The seam between the scheduler and the store.
///
/// `scheduler` is pure and `store` knows nothing about FSRS; this is where a
/// grade becomes a row and a row becomes a schedule. Everything it writes is
/// derived from the review log, so nothing here is a source of truth except
/// the log itself (§3).
class StudyService {
  StudyService(this.db, {required this.deviceId, required this.params});

  final AppDatabase db;
  final String deviceId;
  final d.FsrsParams params;

  int _ms(DateTime t) => t.toUtc().millisecondsSinceEpoch;
  DateTime _at(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

  // -------------------------------------------------------------------------
  // Recording
  // -------------------------------------------------------------------------

  /// Records one answer and advances the card's state.
  ///
  /// Written on the spot, in one transaction: §5.8 requires that leaving
  /// mid-session preserves what was already reviewed. Nothing is batched to
  /// the end of a session, because the end of a session is exactly what does
  /// not happen when a user closes the app.
  Future<d.CardState> recordReview({
    required String cardId,
    required d.Grade grade,
    required DateTime at,
    d.ReviewSource source = d.ReviewSource.standard,
    int? elapsedMs,
    String? reviewId,
  }) async {
    return db.transaction(() async {
      final current = await stateOf(cardId);
      final next = Scheduler.apply(current, grade, at, params);

      await db.into(db.reviews).insert(
            ReviewsCompanion.insert(
              id: reviewId ?? d.Uuid7.generate(now: at),
              cardId: cardId,
              reviewedAt: _ms(at),
              grade: grade.value,
              source: source.wire,
              deviceId: deviceId,
              elapsedMs: Value(elapsedMs),
              // Advisory snapshots (§5.2): they make graduation and
              // retention charts a query instead of a replay, and are never
              // read back as authority.
              intervalDaysAfter: Value(next.interval?.inDays),
              stabilityAfter: Value(next.stability),
              difficultyAfter: Value(next.difficulty),
              // serverSeq stays null: that is the outbox (§6.4).
            ),
          );

      await _writeState(next, throughReviewedAt: _ms(at), throughReviewId: reviewId);
      return next;
    });
  }

  /// The four intervals, for the grade buttons (§5.8.3).
  Future<Map<d.Grade, Duration>> preview(String cardId, DateTime now) async {
    return Scheduler.preview(await stateOf(cardId), now, params);
  }

  // -------------------------------------------------------------------------
  // Replay (§5.3)
  // -------------------------------------------------------------------------

  /// Accepts a review that arrived from another device.
  ///
  /// If it predates the watermark the card is marked dirty rather than folded
  /// in: incremental replay would silently skip it, and FSRS is order
  /// dependent, so the resulting state would be quietly wrong.
  Future<void> ingestRemoteReview({
    required String id,
    required String cardId,
    required DateTime reviewedAt,
    required d.Grade grade,
    required d.ReviewSource source,
    required String fromDeviceId,
    int? elapsedMs,
    int? serverSeq,
  }) async {
    await db.transaction(() async {
      await db.into(db.reviews).insert(
            ReviewsCompanion.insert(
              id: id,
              cardId: cardId,
              reviewedAt: _ms(reviewedAt),
              grade: grade.value,
              source: source.wire,
              deviceId: fromDeviceId,
              elapsedMs: Value(elapsedMs),
              serverSeq: Value(serverSeq),
            ),
            mode: InsertMode.insertOrIgnore, // union merge (§6.1)
          );

      final state = await (db.select(db.cardStates)
            ..where((t) => t.cardId.equals(cardId)))
          .getSingleOrNull();

      final watermark = state?.computedThroughReviewedAt;
      if (watermark != null && _ms(reviewedAt) <= watermark) {
        await db.markDirty(cardId);
      } else {
        await rebuild(cardId);
      }
    });
  }

  /// Full replay from the log (§3, §5.3). The fallback, not the hot path.
  Future<d.CardState> rebuild(String cardId) async {
    final reviewRows = await (db.select(db.reviews)
          ..where((t) => t.cardId.equals(cardId)))
        .get();
    final resetRows = await (db.select(db.progressResets)
          ..where((t) => t.cardId.equals(cardId)))
        .get();

    final state = Scheduler.replay(
      reviewRows
          .map((r) => d.Review(
                id: r.id,
                cardId: r.cardId,
                reviewedAt: _at(r.reviewedAt),
                grade: d.Grade.fromValue(r.grade),
                source: d.ReviewSource.fromWire(r.source),
              ))
          .toList(),
      resetRows
          .map((r) => d.ProgressReset(
                id: r.id,
                cardId: r.cardId,
                resetAt: _at(r.resetAt),
              ))
          .toList(),
      params,
      cardId: cardId,
    );

    final last = reviewRows.isEmpty
        ? null
        : reviewRows.reduce((a, b) => a.reviewedAt >= b.reviewedAt ? a : b);

    await _writeState(
      state,
      throughReviewedAt: last?.reviewedAt,
      throughReviewId: last?.id,
    );
    return state;
  }

  /// Replays every card marked dirty. Cheap per card; never done account-wide
  /// on the hot path, which is why the flag is per card (§5.3).
  Future<int> rebuildDirty() async {
    final dirty = await (db.select(db.cardStates)..where((t) => t.dirty.equals(true))).get();
    for (final row in dirty) {
      await rebuild(row.cardId);
    }
    return dirty.length;
  }

  Future<d.CardState> stateOf(String cardId) async {
    final row = await (db.select(db.cardStates)..where((t) => t.cardId.equals(cardId)))
        .getSingleOrNull();
    if (row == null) return d.CardState.fresh(cardId);

    return d.CardState(
      cardId: row.cardId,
      stability: row.stability,
      difficulty: row.difficulty,
      dueAt: row.dueAt == null ? null : _at(row.dueAt!),
      lastReviewAt: row.lastReviewAt == null ? null : _at(row.lastReviewAt!),
      reps: row.reps,
      lapses: row.lapses,
      phase: d.CardPhase.values.byName(row.phase),
      step: row.step,
    );
  }

  Future<void> _writeState(
    d.CardState state, {
    int? throughReviewedAt,
    String? throughReviewId,
  }) async {
    await db.into(db.cardStates).insertOnConflictUpdate(
          CardStatesCompanion.insert(
            cardId: state.cardId,
            stability: Value(state.stability),
            difficulty: Value(state.difficulty),
            dueAt: Value(state.dueAt == null ? null : _ms(state.dueAt!)),
            lastReviewAt:
                Value(state.lastReviewAt == null ? null : _ms(state.lastReviewAt!)),
            reps: Value(state.reps),
            lapses: Value(state.lapses),
            phase: Value(state.phase.name),
            step: Value(state.step),
            computedThroughReviewedAt: Value(throughReviewedAt),
            computedThroughReviewId: Value(throughReviewId),
            dirty: const Value(false),
          ),
        );
  }

  // -------------------------------------------------------------------------
  // The queue (§5.8)
  // -------------------------------------------------------------------------

  /// Today's queue, honouring both daily limits.
  ///
  /// The new-card limit is **separate** from the review limit and never
  /// borrows from it: §5.8 keeps them apart so introducing cards today cannot
  /// silently inflate the workload of every future day.
  Future<List<String>> buildQueue({
    required DateTime now,
    required int newPerDay,
    required int reviewPerDay,
    required DayBucket day,
  }) async {
    final studiedToday = await countReviewsOn(day.today(now), day);

    final due = await db.dueCardIds(now, limit: reviewPerDay + studiedToday.reviews);
    final reviews = due.take((reviewPerDay - studiedToday.reviews).clamp(0, reviewPerDay));

    final remainingNew = (newPerDay - studiedToday.newCards).clamp(0, newPerDay);
    final fresh = await _newCardIds(limit: remainingNew);

    return [...reviews, ...fresh];
  }

  Future<List<String>> _newCardIds({required int limit}) async {
    if (limit <= 0) return const [];
    final rows = await db.customSelect(
      '''
      SELECT c.id FROM cards c
      LEFT JOIN card_states s ON s.card_id = c.id
      LEFT JOIN card_flags f ON f.card_id = c.id
      WHERE c.deleted_at IS NULL
        AND (s.card_id IS NULL OR s.reps = 0)
        AND COALESCE(f.status, 'active') = 'active'
      ORDER BY c.id
      LIMIT ?1
      ''',
      variables: [Variable<int>(limit)],
      readsFrom: {db.cards, db.cardStates, db.cardFlags},
    ).get();
    return rows.map((r) => r.read<String>('id')).toList();
  }

  /// How much of each limit today has already consumed.
  Future<({int newCards, int reviews})> countReviewsOn(
    String dayKey,
    DayBucket day,
  ) async {
    final (start, end) = day.rangeOf(dayKey);
    final rows = await db.customSelect(
      '''
      SELECT r.card_id, MIN(r.reviewed_at) AS first_at,
             (SELECT MIN(reviewed_at) FROM reviews r2 WHERE r2.card_id = r.card_id) AS ever_first
      FROM reviews r
      WHERE r.reviewed_at >= ?1 AND r.reviewed_at < ?2
      GROUP BY r.card_id
      ''',
      variables: [Variable<int>(_ms(start)), Variable<int>(_ms(end))],
      readsFrom: {db.reviews},
    ).get();

    var newCards = 0;
    for (final row in rows) {
      // A card counts against the new limit on the day it was first seen.
      if (row.read<int>('first_at') == row.read<int>('ever_first')) newCards++;
    }
    return (newCards: newCards, reviews: rows.length - newCards);
  }

  // -------------------------------------------------------------------------
  // Card state changes (§4, §5.10)
  // -------------------------------------------------------------------------

  Future<void> suspend(String cardId, DateTime at) =>
      _writeFlags(cardId, at, status: 'suspended');

  Future<void> unsuspend(String cardId, DateTime at) =>
      _writeFlags(cardId, at, status: 'active');

  /// Hidden until the next local day (§4).
  Future<void> bury(String cardId, DateTime at, DayBucket day) =>
      _writeFlags(cardId, at, status: 'active', buriedUntil: day.endOfDay(at));

  Future<void> _writeFlags(
    String cardId,
    DateTime at, {
    required String status,
    DateTime? buriedUntil,
  }) async {
    await db.into(db.cardFlags).insertOnConflictUpdate(
          CardFlagsCompanion.insert(
            cardId: cardId,
            status: Value(status),
            buriedUntil: Value(buriedUntil == null ? null : _ms(buriedUntil)),
            updatedAt: _ms(at),
            deviceId: deviceId,
          ),
        );
  }

  /// §5.10 — restarts the schedule without deleting history (§3).
  ///
  /// Writes a marker and replays. Statistics still see every review; only the
  /// schedule starts over.
  Future<d.CardState> resetProgress(String cardId, DateTime at) async {
    return db.transaction(() async {
      await db.into(db.progressResets).insert(
            ProgressResetsCompanion.insert(
              id: d.Uuid7.generate(now: at),
              cardId: cardId,
              resetAt: _ms(at),
              deviceId: deviceId,
            ),
          );
      return rebuild(cardId);
    });
  }

  // -------------------------------------------------------------------------
  // Outbox (§6.4)
  // -------------------------------------------------------------------------

  /// Rows not yet acknowledged by the server.
  ///
  /// `serverSeq IS NULL` *is* the outbox — no second table to fall out of step
  /// with the rows it describes.
  Future<int> outboxDepth() async {
    final row = await db.customSelect(
      '''
      SELECT
        (SELECT COUNT(*) FROM reviews         WHERE server_seq IS NULL) +
        (SELECT COUNT(*) FROM cards           WHERE server_seq IS NULL) +
        (SELECT COUNT(*) FROM decks           WHERE server_seq IS NULL) +
        (SELECT COUNT(*) FROM card_flags      WHERE server_seq IS NULL) +
        (SELECT COUNT(*) FROM progress_resets WHERE server_seq IS NULL) AS depth
      ''',
      readsFrom: {db.reviews, db.cards, db.decks, db.cardFlags, db.progressResets},
    ).getSingle();
    return row.read<int>('depth');
  }

  /// Marks reviews acknowledged, in dependency order (§6.4).
  Future<void> acknowledgeReviews(Map<String, int> idToServerSeq) async {
    await db.transaction(() async {
      for (final entry in idToServerSeq.entries) {
        await db.customStatement(
          'UPDATE reviews SET server_seq = ? WHERE id = ?',
          [entry.value, entry.key],
        );
      }
    });
  }
}
