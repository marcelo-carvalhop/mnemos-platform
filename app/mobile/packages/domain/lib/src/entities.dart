import 'contract.g.dart';

/// The phase a card is in, derived from its history — never stored on the
/// server and never synced (§5.3).
///
/// "Maduro" is deliberately absent: §4 of the functional spec says it is not a
/// real state, only a cut of `review` where the interval exceeds
/// [kMatureIntervalDays]. Making it an enum value would invite storing it.
///
/// [relearning] is FSRS-native and has no counterpart in §4, which lists only
/// Novo / Em aprendizado / Em revisão. It is carried faithfully because the
/// algorithm needs it, and collapsed by [CardState.displayPhase] for the UI —
/// a card the user lapsed is "em aprendizado" to them.
enum CardPhase { newCard, learning, review, relearning }

/// One immutable review event (§5.2).
///
/// Never updated, never deleted. Everything the scheduler and the statistics
/// know is derived from a list of these.
class Review {
  const Review({
    required this.id,
    required this.cardId,
    required this.reviewedAt,
    required this.grade,
    required this.source,
    this.elapsedMs,
  });

  final String id;
  final String cardId;

  /// UTC. Day boundaries are applied at query time in the user's timezone
  /// (§5.7), never baked in here.
  final DateTime reviewedAt;

  final Grade grade;
  final ReviewSource source;

  /// Time from reveal to grade. Used to infer a grade in multiple choice
  /// (§5.2) and reported in statistics; never an input to FSRS.
  final int? elapsedMs;
}

/// A marker that resets a card's schedule without deleting its history
/// (§5.2, §5.10).
///
/// Replay ignores every review before [resetAt] for that card, so the user
/// gets a card that starts from zero while the statistics still see the whole
/// truth.
class ProgressReset {
  const ProgressReset({
    required this.id,
    required this.cardId,
    required this.resetAt,
  });

  final String id;
  final String cardId;
  final DateTime resetAt;
}

/// The FSRS parameter vector and the retention target (§3.1).
///
/// Synced, because both are inputs to the interval computation: leaving them
/// device-local means two devices produce different due dates from identical
/// histories, which falsifies the premise the whole design rests on.
class FsrsParams {
  const FsrsParams({
    required this.weights,
    this.desiredRetention = kDesiredRetention,
    this.version = 1,
  });

  /// FSRS weight vector.
  final List<double> weights;

  /// Target probability of recall at the moment a card comes due.
  final double desiredRetention;

  /// Bumped when the vector or the algorithm changes, which forces a rebuild
  /// of the derived cache (§5.3).
  final int version;
}

/// Derived scheduling state — a rebuildable cache, never a source of truth
/// (§3, §5.3).
class CardState {
  const CardState({
    required this.cardId,
    required this.stability,
    required this.difficulty,
    required this.dueAt,
    required this.lastReviewAt,
    required this.reps,
    required this.lapses,
    required this.phase,
    this.step,
  });

  /// The state of a card that has never been reviewed.
  factory CardState.fresh(String cardId) => CardState(
        cardId: cardId,
        stability: 0,
        difficulty: 0,
        dueAt: null,
        lastReviewAt: null,
        reps: 0,
        lapses: 0,
        phase: CardPhase.newCard,
        step: 0,
      );

  final String cardId;

  /// Days until retrievability decays to 90% — by the algorithm's definition,
  /// independent of [FsrsParams.desiredRetention] (§9). The interval derives
  /// from the target; the stability does not.
  ///
  /// This is the unit "memória acumulada" sums.
  final double stability;

  final double difficulty;
  final DateTime? dueAt;
  final DateTime? lastReviewAt;
  final int reps;
  final int lapses;
  final CardPhase phase;

  /// Position within the learning or relearning steps, or null in review.
  ///
  /// FSRS-internal, but it must survive between reviews or a card restarts its
  /// learning ladder on every session. Derived like the rest of this class, so
  /// a rebuild from the log restores it.
  final int? step;

  /// The phase as §4 of the functional spec names it.
  ///
  /// Collapses [CardPhase.relearning] into [CardPhase.learning]: the algorithm
  /// distinguishes them, the user does not.
  CardPhase get displayPhase =>
      phase == CardPhase.relearning ? CardPhase.learning : phase;

  /// The scheduled interval — the gap the algorithm chose between the last
  /// review and the next one.
  Duration? get interval {
    final due = dueAt;
    final last = lastReviewAt;
    if (due == null || last == null) return null;
    return due.difference(last);
  }

  /// True when the current interval exceeds [kMatureIntervalDays].
  ///
  /// Computed, never stored — see [CardPhase].
  bool get isMature => (interval?.inDays ?? 0) > kMatureIntervalDays;

  CardState copyWith({
    double? stability,
    double? difficulty,
    DateTime? dueAt,
    DateTime? lastReviewAt,
    int? reps,
    int? lapses,
    CardPhase? phase,
    int? step,
  }) {
    return CardState(
      cardId: cardId,
      stability: stability ?? this.stability,
      difficulty: difficulty ?? this.difficulty,
      dueAt: dueAt ?? this.dueAt,
      lastReviewAt: lastReviewAt ?? this.lastReviewAt,
      reps: reps ?? this.reps,
      lapses: lapses ?? this.lapses,
      phase: phase ?? this.phase,
      step: step ?? this.step,
    );
  }
}
