import 'dart:math';

import 'package:domain/domain.dart';
import 'package:scheduler/scheduler.dart';
import 'package:test/test.dart';

final params = FsrsParams(weights: defaultFsrsWeights);
final epoch = DateTime.utc(2026, 1, 1, 12);

Review review(String id, Grade grade, DateTime at, {String card = 'c1'}) =>
    Review(
      id: id,
      cardId: card,
      reviewedAt: at,
      grade: grade,
      source: ReviewSource.standard,
    );

/// A deterministic pseudo-random history, so failures reproduce from the seed.
List<Review> randomHistory(int seed, int length) {
  final random = Random(seed);
  var at = epoch;
  return List.generate(length, (i) {
    at = at.add(Duration(hours: 1 + random.nextInt(72 * 24)));
    return review(
      'r${i.toString().padLeft(4, '0')}',
      Grade.values[random.nextInt(Grade.values.length)],
      at,
    );
  });
}

void main() {
  _contractAgreement();

  group('no randomness (§4.1)', () {
    test('the same input always produces the same interval', () {
      // The package enables interval fuzzing by default. With it on, this
      // fails intermittently — and two devices compute different due dates
      // from identical histories, which is the failure the whole design
      // exists to prevent.
      var state = CardState.fresh('c1');
      for (var i = 0; i < 6; i++) {
        state = Scheduler.apply(state, Grade.good, epoch.add(Duration(days: i * 3)), params);
      }

      final results = List.generate(
        50,
        (_) => Scheduler.apply(state, Grade.good, epoch.add(const Duration(days: 60)), params).dueAt,
      ).toSet();

      expect(results.length, 1, reason: 'fuzzing is enabled — intervals vary');
    });

    test('long intervals are stable too, where fuzz would apply', () {
      // Fuzz only kicks in above ~2.5 days, so a test on short intervals
      // would pass with fuzzing on and prove nothing.
      var state = CardState.fresh('c1');
      var at = epoch;
      for (var i = 0; i < 12; i++) {
        state = Scheduler.apply(state, Grade.easy, at, params);
        at = state.dueAt!;
      }
      expect(state.interval!.inDays, greaterThan(21),
          reason: 'the fixture must reach the range where fuzz applies');

      final again = Scheduler.apply(state, Grade.good, at, params);
      final twice = Scheduler.apply(state, Grade.good, at, params);
      expect(again.dueAt, twice.dueAt);
      expect(again.stability, twice.stability);
    });
  });

  group('replay (§3, §5.3)', () {
    test('replaying the same log twice yields identical state', () {
      for (final seed in [1, 7, 42, 99, 2026]) {
        final history = randomHistory(seed, 40);
        final a = Scheduler.replay(history, const [], params, cardId: 'c1');
        final b = Scheduler.replay(history, const [], params, cardId: 'c1');

        expect(a.stability, b.stability, reason: 'seed $seed');
        expect(a.difficulty, b.difficulty, reason: 'seed $seed');
        expect(a.dueAt, b.dueAt, reason: 'seed $seed');
        expect(a.reps, b.reps, reason: 'seed $seed');
        expect(a.lapses, b.lapses, reason: 'seed $seed');
        expect(a.phase, b.phase, reason: 'seed $seed');
      }
    });

    test('arrival order does not matter — only (reviewedAt, id) does', () {
      // Two-way history sync means a review can arrive after the replay has
      // already advanced past its timestamp (§5.3). Replay must not depend on
      // the order the list happens to be in.
      for (final seed in [3, 11, 77]) {
        final history = randomHistory(seed, 30);
        final shuffled = [...history]..shuffle(Random(seed));

        final ordered = Scheduler.replay(history, const [], params, cardId: 'c1');
        final jumbled = Scheduler.replay(shuffled, const [], params, cardId: 'c1');

        expect(jumbled.dueAt, ordered.dueAt, reason: 'seed $seed');
        expect(jumbled.stability, ordered.stability, reason: 'seed $seed');
      }
    });

    test('only this card\'s reviews count', () {
      final history = [
        review('r1', Grade.good, epoch, card: 'c1'),
        review('r2', Grade.again, epoch.add(const Duration(days: 1)), card: 'other'),
        review('r3', Grade.good, epoch.add(const Duration(days: 2)), card: 'c1'),
      ];
      final state = Scheduler.replay(history, const [], params, cardId: 'c1');
      expect(state.reps, 2);
      expect(state.lapses, 0);
    });

    test('an empty history is a fresh card', () {
      final state = Scheduler.replay(const [], const [], params, cardId: 'c1');
      expect(state.phase, CardPhase.newCard);
      expect(state.reps, 0);
      expect(state.dueAt, isNull);
    });
  });

  group('progress reset (§5.10)', () {
    test('a reset makes replay match a card that was never reviewed', () {
      final history = randomHistory(5, 25);
      final resetAt = history.last.reviewedAt.add(const Duration(days: 1));

      final afterReset = Scheduler.replay(
        history,
        [ProgressReset(id: 'p1', cardId: 'c1', resetAt: resetAt)],
        params,
        cardId: 'c1',
      );

      expect(afterReset.phase, CardPhase.newCard);
      expect(afterReset.reps, 0);
      expect(afterReset.lapses, 0);
      expect(afterReset.dueAt, isNull);
    });

    test('reviews after the reset rebuild from zero', () {
      final history = [
        review('r1', Grade.good, epoch),
        review('r2', Grade.good, epoch.add(const Duration(days: 5))),
        review('r3', Grade.good, epoch.add(const Duration(days: 30))),
      ];
      final resetAt = epoch.add(const Duration(days: 10));

      final withReset = Scheduler.replay(
        history,
        [ProgressReset(id: 'p1', cardId: 'c1', resetAt: resetAt)],
        params,
        cardId: 'c1',
      );
      final fromScratch = Scheduler.replay(
        [review('r3', Grade.good, epoch.add(const Duration(days: 30)))],
        const [],
        params,
        cardId: 'c1',
      );

      // The history survives (§3 forbids deleting it); only the schedule
      // starts over.
      expect(withReset.reps, 1);
      expect(withReset.dueAt, fromScratch.dueAt);
      expect(withReset.stability, fromScratch.stability);
    });

    test('the latest reset wins', () {
      final history = randomHistory(9, 20);
      final resets = [
        ProgressReset(id: 'p1', cardId: 'c1', resetAt: epoch.add(const Duration(days: 1))),
        ProgressReset(id: 'p2', cardId: 'c1', resetAt: history.last.reviewedAt.add(const Duration(days: 1))),
      ];
      expect(
        Scheduler.replay(history, resets, params, cardId: 'c1').phase,
        CardPhase.newCard,
      );
    });

    test('another card\'s reset is ignored', () {
      final history = [review('r1', Grade.good, epoch)];
      final state = Scheduler.replay(
        history,
        [ProgressReset(id: 'p1', cardId: 'outro', resetAt: epoch.add(const Duration(days: 1)))],
        params,
        cardId: 'c1',
      );
      expect(state.reps, 1);
    });
  });

  group('preview (§5.8.3)', () {
    test('the shown interval is exactly what the review writes', () {
      // The property that matters: a user who taps "bom" gets the interval the
      // button promised. Derived from apply, so this is nearly free — but it
      // is the assertion that would catch a future refactor separating them.
      for (final seed in [2, 13, 64]) {
        final history = randomHistory(seed, 15);
        final state = Scheduler.replay(history, const [], params, cardId: 'c1');
        final now = state.dueAt ?? epoch;

        final preview = Scheduler.preview(state, now, params);
        for (final grade in Grade.values) {
          final actual = Scheduler.apply(state, grade, now, params);
          expect(actual.dueAt!.difference(now), preview[grade],
              reason: 'seed $seed, grade $grade');
        }
      }
    });

    test('covers all four grades', () {
      final preview = Scheduler.preview(CardState.fresh('c1'), epoch, params);
      expect(preview.keys.toSet(), Grade.values.toSet());
    });

    test('better grades never schedule sooner than worse ones', () {
      var state = CardState.fresh('c1');
      var at = epoch;
      for (var i = 0; i < 5; i++) {
        state = Scheduler.apply(state, Grade.good, at, params);
        at = state.dueAt!;
      }

      final preview = Scheduler.preview(state, at, params);
      expect(preview[Grade.again]!, lessThanOrEqualTo(preview[Grade.hard]!));
      expect(preview[Grade.hard]!, lessThanOrEqualTo(preview[Grade.good]!));
      expect(preview[Grade.good]!, lessThanOrEqualTo(preview[Grade.easy]!));
    });

    test('an overdue card previews different intervals than a punctual one', () {
      // Why preview takes `now`. If this passes trivially, the parameter was
      // dropped and the preview is wrong for exactly the cards users care
      // about.
      var state = CardState.fresh('c1');
      var at = epoch;
      for (var i = 0; i < 6; i++) {
        state = Scheduler.apply(state, Grade.good, at, params);
        at = state.dueAt!;
      }

      final punctual = Scheduler.preview(state, at, params);
      final overdue = Scheduler.preview(state, at.add(const Duration(days: 30)), params);

      expect(overdue[Grade.good], isNot(equals(punctual[Grade.good])));
    });
  });

  group('state transitions', () {
    test('a new card leaves the new phase on its first review', () {
      final state = Scheduler.apply(CardState.fresh('c1'), Grade.good, epoch, params);
      expect(state.phase, isNot(CardPhase.newCard));
      expect(state.reps, 1);
      expect(state.lastReviewAt, isNotNull);
    });

    test('failing a review card counts a lapse and enters relearning', () {
      var state = CardState.fresh('c1');
      var at = epoch;
      for (var i = 0; i < 6; i++) {
        state = Scheduler.apply(state, Grade.easy, at, params);
        at = state.dueAt!;
      }
      expect(state.phase, CardPhase.review, reason: 'fixture must reach review');

      final lapsed = Scheduler.apply(state, Grade.again, at, params);
      expect(lapsed.lapses, state.lapses + 1);
      expect(lapsed.phase, CardPhase.relearning);
      // §4 lists no "relearning" — to the user it is "em aprendizado".
      expect(lapsed.displayPhase, CardPhase.learning);
    });

    test('failing during learning is not a lapse', () {
      // A card still in learning has nothing to lapse from; counting it would
      // inflate the leech statistics of §5.11.
      final learning = Scheduler.apply(CardState.fresh('c1'), Grade.good, epoch, params);
      expect(learning.phase, CardPhase.learning);

      final failed = Scheduler.apply(learning, Grade.again, epoch.add(const Duration(minutes: 10)), params);
      expect(failed.lapses, 0);
    });

    test('maturity is the 21-day cut of §4, not a stored flag', () {
      var state = CardState.fresh('c1');
      var at = epoch;
      expect(state.isMature, isFalse);

      for (var i = 0; i < 12; i++) {
        state = Scheduler.apply(state, Grade.easy, at, params);
        at = state.dueAt!;
      }
      expect(state.interval!.inDays, greaterThan(kMatureIntervalDays));
      expect(state.isMature, isTrue);
    });

    test('stability only grows while the card is remembered', () {
      // §9 — "memória acumulada" sums stability, and it must fall on a lapse
      // or the metric becomes inflatable, which §2.3 forbids.
      var state = CardState.fresh('c1');
      var at = epoch;
      for (var i = 0; i < 8; i++) {
        state = Scheduler.apply(state, Grade.good, at, params);
        at = state.dueAt!;
      }
      final before = state.stability;

      final lapsed = Scheduler.apply(state, Grade.again, at, params);
      expect(lapsed.stability, lessThan(before));
    });
  });

  group('desired retention is a real input (§3.1)', () {
    test('a lower target lengthens intervals', () {
      // If this fails, desiredRetention is not reaching the engine — and two
      // devices with different settings would compute different due dates
      // from identical histories.
      CardState settle(double retention) {
        final p = FsrsParams(weights: defaultFsrsWeights, desiredRetention: retention);
        var state = CardState.fresh('c1');
        var at = epoch;
        for (var i = 0; i < 6; i++) {
          state = Scheduler.apply(state, Grade.good, at, p);
          at = state.dueAt!;
        }
        return state;
      }

      expect(settle(0.80).interval!, greaterThan(settle(0.95).interval!));
    });
  });
}

/// O vetor de pesos que a web também usa.
///
/// §4.1 declara o vetor no contrato porque cada plataforma usa um pacote
/// diferente de FSRS e os padrões **não** coincidem: o `ts-fsrs` do npm traz o
/// vetor do FSRS-6 e este traz outro. Herdar o padrão de cada pacote fazia o
/// navegador e o telefone calcularem vencimentos diferentes do mesmo
/// histórico, sem nada avisar — foi assim que apareceu.
///
/// Este teste é a metade Dart do acordo; a outra está em
/// `app/web/src/app/core/scheduler.spec.ts`.
void _contractAgreement() {
  test('o padrão do pacote é o vetor declarado no contrato', () {
    expect(defaultFsrsWeights, kFsrsWeights);
  });
}
