import 'dart:convert';
import 'dart:math';

import 'package:domain/domain.dart';
import 'package:store/store.dart';

/// One question on the paper.
class SimuladoQuestion {
  const SimuladoQuestion({
    required this.cardId,
    required this.prompt,
    required this.expected,
  });

  final String cardId;
  final String prompt;
  final String expected;
}

/// A paper: the questions and the total time allowed.
class Simulado {
  const Simulado({required this.questions, required this.timeLimit});

  final List<SimuladoQuestion> questions;
  final Duration timeLimit;

  /// Time is a budget for the whole paper, not for each question — §5.9 says
  /// exam format, and an exam is not a per-question countdown.
  Duration remaining(Duration elapsed) {
    final left = timeLimit - elapsed;
    return left.isNegative ? Duration.zero : left;
  }
}

/// What the user got right, produced only at the end.
class SimuladoResult {
  const SimuladoResult({
    required this.correctCardIds,
    required this.wrongCardIds,
    required this.unanswered,
    required this.elapsed,
  });

  final List<String> correctCardIds;
  final List<String> wrongCardIds;

  /// Ran out of time. Distinct from wrong: not reaching a question says
  /// nothing about whether it was known.
  final List<String> unanswered;
  final Duration elapsed;

  int get answered => correctCardIds.length + wrongCardIds.length;
  double get score => answered == 0 ? 0 : correctCardIds.length / answered;
}

/// Timed simulado (§5.9).
///
/// Measurement, not study: **no feedback during, result only at the end, and
/// no review row ever**. Like [LeechDrill] it is given no [StudyService], so
/// it has no way to write one even by mistake.
class SimuladoMode {
  SimuladoMode(this.db, {Random? random}) : _random = random ?? Random();

  final AppDatabase db;
  final Random _random;

  /// Draws a paper from a deck or a tag (§5.9).
  ///
  /// Suspended cards are excluded — the user has said they do not want to see
  /// them, and an exam is not the place to overrule that.
  Future<Simulado> build({
    String? deckId,
    String? tag,
    int questions = kSimuladoDefaultQuestions,
    Duration? timeLimit,
  }) async {
    final query = db.select(db.cards)..where((t) => t.deletedAt.isNull());
    if (deckId != null) query.where((t) => t.deckId.equals(deckId));

    final suspended = await (db.select(db.cardFlags)
          ..where((t) => t.status.equals(CardStatus.suspended.wire)))
        .get();
    final excluded = suspended.map((f) => f.cardId).toSet();

    var pool = (await query.get()).where((c) => !excluded.contains(c.id)).toList();

    if (tag != null) {
      pool = pool.where((c) {
        final decoded = jsonDecode(c.tags);
        return decoded is List && decoded.contains(tag);
      }).toList();
    }

    pool.shuffle(_random);
    final drawn = pool.take(questions).toList();

    return Simulado(
      questions: [
        for (final c in drawn)
          SimuladoQuestion(cardId: c.id, prompt: c.front, expected: c.back),
      ],
      // A shorter paper gets proportionally less time, so a deck with eight
      // cards is not an eight-question exam with twenty minutes on the clock.
      timeLimit: timeLimit ??
          Duration(
            milliseconds: drawn.isEmpty
                ? 0
                : (kSimuladoDefaultMinutes * 60000 * drawn.length ~/
                    kSimuladoDefaultQuestions),
          ),
    );
  }

  /// Scores the paper. Self-marked: §5.9 wants exam format, and the app cannot
  /// judge a free-text answer against the back of a card.
  ///
  /// Nothing here touches `reviews` or `card_state`.
  SimuladoResult score(
    Simulado paper, {
    required Set<String> correctCardIds,
    required Set<String> wrongCardIds,
    required Duration elapsed,
  }) {
    final seen = {...correctCardIds, ...wrongCardIds};
    return SimuladoResult(
      correctCardIds: [
        for (final q in paper.questions)
          if (correctCardIds.contains(q.cardId)) q.cardId
      ],
      wrongCardIds: [
        for (final q in paper.questions)
          if (wrongCardIds.contains(q.cardId)) q.cardId
      ],
      unanswered: [
        for (final q in paper.questions)
          if (!seen.contains(q.cardId)) q.cardId
      ],
      elapsed: elapsed,
    );
  }
}
