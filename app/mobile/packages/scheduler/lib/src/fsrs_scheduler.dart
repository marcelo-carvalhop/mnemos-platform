import 'package:domain/domain.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

/// FSRS scheduling (§4.1).
///
/// Pure: no IO, no database, no ambient clock — every entry point takes the
/// time it should use. That is what lets the correctness-critical logic be
/// tested against thousands of synthetic histories in milliseconds, which
/// matters because scheduling bugs surface weeks later as "why is this card
/// due today".
abstract final class Scheduler {
  /// The single place a grade becomes a new state. Everything else derives
  /// from it.
  static CardState apply(
    CardState state,
    Grade grade,
    DateTime at,
    FsrsParams params,
  ) {
    final engine = _engine(params);
    final (card: reviewed, reviewLog: _) = engine.reviewCard(
      _toFsrs(state, at),
      _toRating(grade),
      reviewDateTime: at.toUtc(),
    );

    final lapsed = grade == Grade.again && state.phase == CardPhase.review;

    return CardState(
      cardId: state.cardId,
      stability: reviewed.stability ?? 0,
      difficulty: reviewed.difficulty ?? 0,
      dueAt: reviewed.due,
      lastReviewAt: reviewed.lastReview,
      reps: state.reps + 1,
      lapses: state.lapses + (lapsed ? 1 : 0),
      phase: _toPhase(reviewed.state),
      step: reviewed.step,
    );
  }

  /// Rebuilds a card's state from its history (§3, §5.3).
  ///
  /// [resets] implements §5.10's *reiniciar progresso*: reviews at or before
  /// the latest reset for this card are ignored, so the schedule starts over
  /// while the history itself survives — §3 forbids deleting it.
  ///
  /// Reviews are sorted by `(reviewedAt, id)` rather than trusted in the order
  /// given, because two-way history sync means a review can arrive out of
  /// order (§5.3) and replay must not depend on arrival order.
  static CardState replay(
    List<Review> history,
    List<ProgressReset> resets,
    FsrsParams params, {
    required String cardId,
  }) {
    DateTime? cutoff;
    for (final reset in resets) {
      if (reset.cardId != cardId) continue;
      if (cutoff == null || reset.resetAt.isAfter(cutoff)) {
        cutoff = reset.resetAt;
      }
    }

    final relevant = history
        .where((r) => r.cardId == cardId)
        .where((r) => cutoff == null || r.reviewedAt.isAfter(cutoff))
        .toList()
      ..sort((a, b) {
        final byTime = a.reviewedAt.compareTo(b.reviewedAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });

    var state = CardState.fresh(cardId);
    for (final review in relevant) {
      state = apply(state, review.grade, review.reviewedAt, params);
    }
    return state;
  }

  /// The interval each of the four grades would produce, right now.
  ///
  /// §5.8.3 requires every grade button to show its resulting interval before
  /// the user commits. This is **derived from [apply]** rather than computed
  /// alongside it, which makes "the preview never lies" true by construction
  /// instead of by test.
  ///
  /// [now] is a parameter because the answer depends on it: a card three days
  /// overdue does not produce the same four intervals as one reviewed on
  /// schedule. Omitting it is the quiet way to ship a preview that is wrong
  /// for exactly the cards the user cares about.
  static Map<Grade, Duration> preview(
    CardState state,
    DateTime now,
    FsrsParams params,
  ) {
    return {
      for (final grade in Grade.values)
        grade: apply(state, grade, now, params).dueAt!.difference(now),
    };
  }

  // ---------------------------------------------------------------------------

  static fsrs.Scheduler _engine(FsrsParams params) => fsrs.Scheduler(
        parameters: params.weights,
        desiredRetention: params.desiredRetention,
        // §4.1 — no randomness, ever.
        //
        // The package defaults this to true: it spreads review load by
        // jittering intervals of ~2.5 days and up. That is reasonable for a
        // single-device app and fatal here. It would make replaying the same
        // log twice produce different states, and two devices compute
        // different due dates from identical histories — the exact failure
        // this architecture is built to prevent. A test asserts it stays off.
        enableFuzzing: false,
      );

  static fsrs.Card _toFsrs(CardState state, DateTime at) {
    if (state.phase == CardPhase.newCard) {
      return fsrs.Card(
        cardId: 0,
        state: fsrs.State.learning,
        step: 0,
        due: at.toUtc(),
      );
    }
    return fsrs.Card(
      cardId: 0,
      state: _toFsrsState(state.phase),
      step: state.step,
      stability: state.stability,
      difficulty: state.difficulty,
      due: (state.dueAt ?? at).toUtc(),
      lastReview: state.lastReviewAt?.toUtc(),
    );
  }

  static fsrs.Rating _toRating(Grade grade) => switch (grade) {
        Grade.again => fsrs.Rating.again,
        Grade.hard => fsrs.Rating.hard,
        Grade.good => fsrs.Rating.good,
        Grade.easy => fsrs.Rating.easy,
      };

  static fsrs.State _toFsrsState(CardPhase phase) => switch (phase) {
        CardPhase.newCard || CardPhase.learning => fsrs.State.learning,
        CardPhase.review => fsrs.State.review,
        CardPhase.relearning => fsrs.State.relearning,
      };

  static CardPhase _toPhase(fsrs.State state) => switch (state) {
        fsrs.State.learning => CardPhase.learning,
        fsrs.State.review => CardPhase.review,
        fsrs.State.relearning => CardPhase.relearning,
      };
}

/// The package's published default weight vector.
///
/// Exposed so callers construct [FsrsParams] without importing the package —
/// §4.1 keeps the dependency swappable behind this wrapper.
const List<double> defaultFsrsWeights = fsrs.defaultParameters;
