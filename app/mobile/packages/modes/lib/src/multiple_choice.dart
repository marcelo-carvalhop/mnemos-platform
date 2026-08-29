import 'dart:math';

import 'package:domain/domain.dart';
import 'package:domain/domain.dart' as d show CardState;
import 'package:session/session.dart';
import 'package:store/store.dart';

/// One question: the card's front, and four backs of which one is right.
class MultipleChoiceQuestion {
  const MultipleChoiceQuestion({
    required this.cardId,
    required this.prompt,
    required this.options,
    required this.answerIndex,
  });

  final String cardId;
  final String prompt;

  /// Distractors come from other cards in the same deck (§5.9) — a plausible
  /// wrong answer is what makes the question worth anything.
  final List<String> options;
  final int answerIndex;

  String get answer => options[answerIndex];
}

/// Multiple choice — the one alternative mode that counts (§5.9).
///
/// It writes a review row with `source = multiple_choice`, so the history can
/// always be read back to ask how a card was answered.
class MultipleChoiceMode {
  MultipleChoiceMode(this.db, {required this.study, Random? random})
      : _random = random ?? Random();

  final AppDatabase db;
  final StudyService study;
  final Random _random;

  /// Infers the grade from correctness and speed.
  ///
  /// Deliberately pessimistic. One option in four is a 25% chance of guessing
  /// right; treating that as *bom* or *fácil* feeds noise into stability and
  /// quietly degrades the schedule over months. So: wrong → *errei*,
  /// correct-and-slow → *difícil*, correct-and-fast → *bom*, and **`fácil` is
  /// never inferred** — a guess must not be able to buy the longest interval.
  static Grade gradeFor({required bool correct, required Duration elapsed}) {
    if (!correct) return Grade.again;
    return elapsed.inMilliseconds <= kMultipleChoiceFastAnswerMs
        ? Grade.good
        : Grade.hard;
  }

  /// Builds a paper for [cardIds], in the order given.
  ///
  /// A card whose deck cannot supply enough distinct distractors is dropped
  /// rather than padded: a question with two options is a coin toss, and a
  /// coin toss would be written into the review log as if it meant something.
  Future<List<MultipleChoiceQuestion>> build(
    List<String> cardIds, {
    int optionCount = kMultipleChoiceOptions,
  }) async {
    if (cardIds.isEmpty) return const [];

    final cards = await (db.select(db.cards)
          ..where((t) => t.id.isIn(cardIds))
          ..where((t) => t.deletedAt.isNull()))
        .get();
    final byId = {for (final c in cards) c.id: c};

    // One query for the pool, not one per question.
    final deckIds = cards.map((c) => c.deckId).toSet();
    final pool = await (db.select(db.cards)
          ..where((t) => t.deckId.isIn(deckIds))
          ..where((t) => t.deletedAt.isNull()))
        .get();

    final backsByDeck = <String, List<String>>{};
    for (final c in pool) {
      (backsByDeck[c.deckId] ??= []).add(c.back);
    }

    final questions = <MultipleChoiceQuestion>[];
    for (final id in cardIds) {
      final card = byId[id];
      if (card == null) continue;

      final distractors = (backsByDeck[card.deckId] ?? const [])
          .where((back) => back != card.back)
          .toSet()
          .toList()
        ..shuffle(_random);

      if (distractors.length < optionCount - 1) continue;

      final options = [...distractors.take(optionCount - 1), card.back]
        ..shuffle(_random);

      questions.add(MultipleChoiceQuestion(
        cardId: id,
        prompt: card.front,
        options: options,
        answerIndex: options.indexOf(card.back),
      ));
    }
    return questions;
  }

  /// Records an answer. This is the only place in this package that writes.
  Future<d.CardState> answer({
    required MultipleChoiceQuestion question,
    required int chosenIndex,
    required Duration elapsed,
    required DateTime at,
  }) {
    return study.recordReview(
      cardId: question.cardId,
      grade: gradeFor(correct: chosenIndex == question.answerIndex, elapsed: elapsed),
      at: at,
      source: ReviewSource.multipleChoice,
      elapsedMs: elapsed.inMilliseconds,
    );
  }
}
