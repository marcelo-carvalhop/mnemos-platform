import 'dart:math';

import 'package:domain/domain.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:modes/modes.dart';
import 'package:scheduler/scheduler.dart';
import 'package:session/session.dart';
import 'package:store/store.dart';
import 'package:test/test.dart';

void main() {
  late AppDatabase db;
  late StudyService study;
  final now = DateTime.utc(2026, 8, 9, 15);

  /// Seeded, so a shuffle failure is reproducible rather than a flake.
  Random seeded() => Random(1);

  int ms(DateTime t) => t.millisecondsSinceEpoch;

  Future<String> deck(String name) async {
    final id = Uuid7.generate(now: now);
    await db.into(db.decks).insert(DecksCompanion.insert(
          id: id,
          name: name,
          updatedAt: ms(now),
          deviceId: 'test',
        ));
    return id;
  }

  Future<String> card(String deckId, String front, String back) async {
    final id = Uuid7.generate(now: now);
    await db.into(db.cards).insert(CardsCompanion.insert(
          id: id,
          deckId: deckId,
          front: front,
          back: back,
          updatedAt: ms(now),
          deviceId: 'test',
        ));
    return id;
  }

  Future<int> reviewCount() async =>
      (await db.select(db.reviews).get()).length;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    study = StudyService(
      db,
      deviceId: 'test',
      params: const FsrsParams(weights: defaultFsrsWeights, desiredRetention: 0.9),
    );
  });

  tearDown(() => db.close());

  // -------------------------------------------------------------------------
  // The line that runs through §5.9
  // -------------------------------------------------------------------------

  group('what feeds the scheduler', () {
    test('the drill, the simulado and the audio session write nothing', () async {
      final d = await deck('Baralho');
      final ids = [
        for (var i = 0; i < 6; i++) await card(d, 'Frente $i', 'Verso $i'),
      ];
      for (var i = 0; i < 5; i++) {
        await study.recordReview(
          cardId: ids.first,
          grade: Grade.again,
          at: now.add(Duration(minutes: i)),
        );
      }
      final before = await reviewCount();

      await LeechDrill(db).select();
      final paper = await SimuladoMode(db, random: seeded()).build(deckId: d);
      SimuladoMode(db).score(
        paper,
        correctCardIds: paper.questions.map((q) => q.cardId).toSet(),
        wrongCardIds: const {},
        elapsed: const Duration(minutes: 3),
      );
      await AudioSessionBuilder(db).build(ids);

      expect(await reviewCount(), before,
          reason: 'extra practice must not touch the schedule (§5.9)');

      // Structural, not a promise: none of the three can be handed a writer.
      expect(LeechDrill(db), isNot(isA<MultipleChoiceMode>()));
    });

    test('multiple choice writes a row, tagged as such', () async {
      final d = await deck('Baralho');
      final ids = [
        for (var i = 0; i < 5; i++) await card(d, 'Frente $i', 'Verso $i'),
      ];

      final mode = MultipleChoiceMode(db, study: study, random: seeded());
      final questions = await mode.build([ids.first]);
      await mode.answer(
        question: questions.single,
        chosenIndex: questions.single.answerIndex,
        elapsed: const Duration(seconds: 3),
        at: now,
      );

      final rows = await db.select(db.reviews).get();
      expect(rows, hasLength(1));
      // The wire value, not the Dart member name. `.name` is 'multipleChoice'
      // and the contract says 'multiple_choice'; writing the first stored a
      // value the server does not recognise, silently, because the column is
      // just text.
      expect(rows.single.source, 'multiple_choice');
      expect(rows.single.source, ReviewSource.multipleChoice.wire);
      expect(rows.single.elapsedMs, 3000);
    });
  });

  // -------------------------------------------------------------------------
  // Multiple choice
  // -------------------------------------------------------------------------

  group('multiple choice', () {
    test('never infers fácil, however fast the answer', () {
      // §5.2: a 1-in-4 guess must not be able to buy the longest interval.
      for (final elapsed in [Duration.zero, const Duration(milliseconds: 1)]) {
        expect(
          MultipleChoiceMode.gradeFor(correct: true, elapsed: elapsed),
          Grade.good,
        );
      }
    });

    test('slow but right is difícil; wrong is errei at any speed', () {
      expect(
        MultipleChoiceMode.gradeFor(
            correct: true,
            elapsed: const Duration(milliseconds: kMultipleChoiceFastAnswerMs + 1)),
        Grade.hard,
      );
      expect(
        MultipleChoiceMode.gradeFor(correct: false, elapsed: Duration.zero),
        Grade.again,
      );
      expect(
        MultipleChoiceMode.gradeFor(correct: false, elapsed: const Duration(minutes: 5)),
        Grade.again,
      );
    });

    test('the boundary is inclusive, so exactly on time counts as fast', () {
      expect(
        MultipleChoiceMode.gradeFor(
            correct: true,
            elapsed: const Duration(milliseconds: kMultipleChoiceFastAnswerMs)),
        Grade.good,
      );
    });

    test('options contain the answer once and come from the same deck', () async {
      final d = await deck('Certo');
      final other = await deck('Errado');
      await card(other, 'Intruso', 'Verso intruso');
      final ids = [
        for (var i = 0; i < 5; i++) await card(d, 'Frente $i', 'Verso $i'),
      ];

      final questions =
          await MultipleChoiceMode(db, study: study, random: seeded()).build(ids);

      for (final q in questions) {
        expect(q.options, hasLength(kMultipleChoiceOptions));
        expect(q.options.where((o) => o == q.answer), hasLength(1),
            reason: 'the right answer must not also be a distractor');
        expect(q.options, isNot(contains('Verso intruso')));
        expect(q.options.toSet(), hasLength(kMultipleChoiceOptions));
      }
    });

    test('a deck too small to make a real question is skipped, not padded',
        () async {
      // Two options is a coin toss, and a coin toss would be written into the
      // log as if it meant something.
      final d = await deck('Pequeno');
      final ids = [
        for (var i = 0; i < 3; i++) await card(d, 'Frente $i', 'Verso $i'),
      ];

      expect(
        await MultipleChoiceMode(db, study: study, random: seeded()).build(ids),
        isEmpty,
      );
    });

    test('cards sharing a back do not yield a duplicate option', () async {
      final d = await deck('Repetido');
      for (var i = 0; i < 5; i++) {
        await card(d, 'Frente $i', 'Mesmo verso');
      }
      final target = await card(d, 'Alvo', 'Verso do alvo');

      // Only one distinct distractor exists, so no honest question can be
      // built.
      expect(
        await MultipleChoiceMode(db, study: study, random: seeded()).build([target]),
        isEmpty,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Leech drill
  // -------------------------------------------------------------------------

  group('leech drill', () {
    test('ranks by lapses and honours the threshold', () async {
      final d = await deck('Baralho');
      final bad = await card(d, 'Difícil', 'Resposta');
      final ok = await card(d, 'Fácil', 'Resposta 2');

      for (var i = 0; i < 5; i++) {
        await study.recordReview(
            cardId: bad, grade: Grade.again, at: now.add(Duration(minutes: i)));
      }
      await study.recordReview(cardId: ok, grade: Grade.again, at: now);

      final leeches = await LeechDrill(db).select();
      expect(leeches.map((l) => l.cardId), [bad],
          reason: 'one lapse is not a leech');
      expect(leeches.single.lapses, 5);
      expect(leeches.single.front, 'Difícil');
    });

    test('a good answer is not a lapse', () async {
      final d = await deck('Baralho');
      final c = await card(d, 'Frente', 'Verso');
      for (var i = 0; i < 6; i++) {
        await study.recordReview(
            cardId: c, grade: Grade.good, at: now.add(Duration(days: i)));
      }
      expect(await LeechDrill(db).select(), isEmpty);
    });

    test('restarting a card clears its leech record', () async {
      // §5.10 — reiniciar progresso cannot delete history (§3), so the drill
      // has to read past the marker instead.
      final d = await deck('Baralho');
      final c = await card(d, 'Frente', 'Verso');
      for (var i = 0; i < 5; i++) {
        await study.recordReview(
            cardId: c, grade: Grade.again, at: now.add(Duration(minutes: i)));
      }
      expect(await LeechDrill(db).select(), hasLength(1));

      await study.resetProgress(c, now.add(const Duration(hours: 1)));

      expect(await LeechDrill(db).select(), isEmpty,
          reason: 'the history survives; the label does not');
      expect(await db.select(db.reviews).get(), hasLength(5),
          reason: 'nothing was deleted (§3)');
    });

    test('a deleted card never appears', () async {
      final d = await deck('Baralho');
      final c = await card(d, 'Frente', 'Verso');
      for (var i = 0; i < 5; i++) {
        await study.recordReview(
            cardId: c, grade: Grade.again, at: now.add(Duration(minutes: i)));
      }
      await (db.update(db.cards)..where((t) => t.id.equals(c)))
          .write(CardsCompanion(deletedAt: Value(ms(now))));

      expect(await LeechDrill(db).select(), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Simulado
  // -------------------------------------------------------------------------

  group('simulado', () {
    test('draws from one deck only, and skips suspended cards', () async {
      final a = await deck('A');
      final b = await deck('B');
      for (var i = 0; i < 4; i++) {
        await card(a, 'A$i', 'Verso A$i');
      }
      await card(b, 'B0', 'Verso B0');
      final hidden = await card(a, 'Escondido', 'Verso escondido');
      await study.suspend(hidden, now);

      final paper = await SimuladoMode(db, random: seeded()).build(deckId: a);

      expect(paper.questions.map((q) => q.prompt), isNot(contains('B0')));
      expect(paper.questions.map((q) => q.cardId), isNot(contains(hidden)),
          reason: 'an exam is not the place to overrule "do not show me this"');
      expect(paper.questions, hasLength(4));
    });

    test('a short paper gets proportionally less time', () async {
      final d = await deck('Curto');
      for (var i = 0; i < 5; i++) {
        await card(d, 'F$i', 'V$i');
      }

      final paper = await SimuladoMode(db, random: seeded()).build(deckId: d);

      expect(paper.questions, hasLength(5));
      expect(
        paper.timeLimit,
        Duration(
            minutes: kSimuladoDefaultMinutes * 5 ~/ kSimuladoDefaultQuestions),
      );
    });

    test('the clock is for the whole paper and stops at zero', () {
      const paper = Simulado(questions: [], timeLimit: Duration(minutes: 20));

      expect(paper.remaining(const Duration(minutes: 5)),
          const Duration(minutes: 15));
      expect(paper.remaining(const Duration(minutes: 40)), Duration.zero,
          reason: 'never a negative countdown');
    });

    test('unanswered is distinct from wrong', () async {
      final d = await deck('Prova');
      final ids = [for (var i = 0; i < 4; i++) await card(d, 'F$i', 'V$i')];
      final mode = SimuladoMode(db, random: seeded());
      final paper = await mode.build(deckId: d, questions: 4);

      final result = mode.score(
        paper,
        correctCardIds: {ids[0]},
        wrongCardIds: {ids[1]},
        elapsed: const Duration(minutes: 12),
      );

      expect(result.correctCardIds, [ids[0]]);
      expect(result.wrongCardIds, [ids[1]]);
      expect(result.unanswered.toSet(), {ids[2], ids[3]});
      // Not reaching a question says nothing about whether it was known, so
      // it is not counted against the score.
      expect(result.score, 0.5);
      expect(result.answered, 2);
    });

    test('an empty paper scores zero rather than dividing by zero', () async {
      final d = await deck('Vazio');
      final mode = SimuladoMode(db, random: seeded());
      final paper = await mode.build(deckId: d);

      expect(paper.questions, isEmpty);
      expect(paper.timeLimit, Duration.zero);
      expect(
        mode
            .score(paper,
                correctCardIds: const {},
                wrongCardIds: const {},
                elapsed: Duration.zero)
            .score,
        0,
      );
    });

    test('filters by tag when asked', () async {
      final d = await deck('Etiquetado');
      final tagged = await card(d, 'Com etiqueta', 'Verso');
      await card(d, 'Sem etiqueta', 'Verso 2');
      await (db.update(db.cards)..where((t) => t.id.equals(tagged)))
          .write(const CardsCompanion(tags: Value('["prova"]')));

      final paper =
          await SimuladoMode(db, random: seeded()).build(deckId: d, tag: 'prova');

      expect(paper.questions.map((q) => q.cardId), [tagged]);
    });
  });

  // -------------------------------------------------------------------------
  // Audio
  // -------------------------------------------------------------------------

  group('audio', () {
    test('reads front, pauses, reads back, in the order given', () async {
      final d = await deck('Áudio');
      final first = await card(d, 'Frente 1', 'Verso 1');
      final second = await card(d, 'Frente 2', 'Verso 2');

      final steps = await AudioSessionBuilder(db).build([first, second]);

      expect(steps.map((s) => s.runtimeType.toString()), [
        'Speak', 'Pause', 'Speak', // card 1
        'Pause', //                   between cards
        'Speak', 'Pause', 'Speak', // card 2
      ]);
      expect((steps[0] as Speak).text, 'Frente 1');
      expect((steps[0] as Speak).isFront, isTrue);
      expect((steps[2] as Speak).text, 'Verso 1');
      expect((steps[4] as Speak).text, 'Frente 2');
    });

    test('the gap before the answer is the point of the mode', () async {
      final d = await deck('Áudio');
      final c = await card(d, 'Frente', 'Verso');

      final steps = await AudioSessionBuilder(db).build([c]);

      expect((steps[1] as Pause).duration,
          const Duration(milliseconds: kTtsAnswerPauseMs));
    });

    test('an empty or unknown selection produces no steps', () async {
      expect(await AudioSessionBuilder(db).build([]), isEmpty);
      expect(await AudioSessionBuilder(db).build(['nao-existe']), isEmpty);
    });
  });
}
