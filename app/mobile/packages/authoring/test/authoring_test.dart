import 'dart:convert';

import 'package:authoring/authoring.dart';
import 'package:domain/domain.dart';
import 'package:drift/native.dart';
import 'package:scheduler/scheduler.dart';
import 'package:session/session.dart';
import 'package:store/store.dart' hide CardState;
import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tzdata;

late AppDatabase db;
late AuthoringService authoring;

final t0 = DateTime.utc(2026, 8, 9, 15);

void main() {
  setUpAll(tzdata.initializeTimeZones);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    authoring = AuthoringService(db, deviceId: 'phone');
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async => db.close());

  group('deck tree (§5.1)', () {
    test('a deck can be nested under another', () async {
      final root = await authoring.createDeck(name: 'História', at: t0);
      final child =
          await authoring.createDeck(name: 'Brasil', at: t0, parentId: root);

      expect(await authoring.depthOf(child), 1);
      expect(await authoring.subtreeOf(root), containsAll([root, child]));
    });

    test('a deck cannot become its own parent', () async {
      final deck = await authoring.createDeck(name: 'A', at: t0);
      expect(
        () => authoring.moveDeck(deck, deck, t0),
        throwsA(isA<DeckCycle>()),
      );
    });

    test('a deck cannot be moved inside its own subtree', () async {
      // Dragging a deck onto its own child is an ordinary gesture, and the
      // result is a subtree no traversal terminates on.
      final root = await authoring.createDeck(name: 'A', at: t0);
      final child = await authoring.createDeck(name: 'B', at: t0, parentId: root);
      final grandchild =
          await authoring.createDeck(name: 'C', at: t0, parentId: child);

      expect(() => authoring.moveDeck(root, child, t0), throwsA(isA<DeckCycle>()));
      expect(
        () => authoring.moveDeck(root, grandchild, t0),
        throwsA(isA<DeckCycle>()),
        reason: 'the check must reach the whole subtree, not just children',
      );
    });

    test('a legitimate move is allowed', () async {
      final a = await authoring.createDeck(name: 'A', at: t0);
      final b = await authoring.createDeck(name: 'B', at: t0);
      await authoring.moveDeck(b, a, t0);
      expect(await authoring.depthOf(b), 1);
    });

    test('nesting is capped', () async {
      // Without a cap the tree grows until some query walks it and stalls.
      var parent = await authoring.createDeck(name: 'n0', at: t0);
      for (var i = 1; i <= kMaxDeckDepth; i++) {
        parent = await authoring.createDeck(name: 'n$i', at: t0, parentId: parent);
      }
      expect(
        () => authoring.createDeck(name: 'demais', at: t0, parentId: parent),
        throwsA(isA<DeckTooDeep>()),
      );
    });

    test('moving a tall subtree under a deep parent is rejected', () async {
      final tall = await authoring.createDeck(name: 'raiz', at: t0);
      var node = tall;
      for (var i = 0; i < 3; i++) {
        node = await authoring.createDeck(name: 'f$i', at: t0, parentId: node);
      }

      var deep = await authoring.createDeck(name: 'd0', at: t0);
      for (var i = 1; i < 3; i++) {
        deep = await authoring.createDeck(name: 'd$i', at: t0, parentId: deep);
      }

      expect(
        () => authoring.moveDeck(tall, deep, t0),
        throwsA(isA<DeckTooDeep>()),
        reason: 'the height of what is being moved has to count too',
      );
    });

    test('deleting a deck deletes its whole subtree', () async {
      // Deleting only the parent leaves cards no screen can reach and no query
      // excludes — invisible cards that still come due.
      final root = await authoring.createDeck(name: 'A', at: t0);
      final child = await authoring.createDeck(name: 'B', at: t0, parentId: root);
      await authoring.createCard(deckId: child, front: 'f', back: 'v', at: t0);

      expect(await authoring.deleteDeck(root, t0), 2);

      final card = await db.select(db.cards).getSingle();
      expect(card.deletedAt, isNotNull, reason: 'the orphan must not survive');
    });

    test('archiving keeps the cards and their history', () async {
      final deck = await authoring.createDeck(name: 'A', at: t0);
      await authoring.createCard(deckId: deck, front: 'f', back: 'v', at: t0);
      await authoring.archiveDeck(deck, t0);

      final row = await db.select(db.decks).getSingle();
      expect(row.archivedAt, isNotNull);
      expect(row.deletedAt, isNull, reason: 'archiving is not deleting');
      expect((await db.select(db.cards).get()).length, 1);
    });
  });

  group('the character limit (§5.4)', () {
    test('a card at the limit is accepted', () async {
      final deck = await authoring.createDeck(name: 'A', at: t0);
      await authoring.createCard(
        deckId: deck,
        front: 'a' * kFrontMaxGraphemes,
        back: 'b' * kBackMaxGraphemes,
        at: t0,
      );
      expect((await db.select(db.cards).get()).length, 1);
    });

    test('one grapheme over is refused, on either side', () async {
      final deck = await authoring.createDeck(name: 'A', at: t0);

      expect(
        () => authoring.createCard(
          deckId: deck,
          front: 'a' * (kFrontMaxGraphemes + 1),
          back: 'v',
          at: t0,
        ),
        throwsA(isA<CardTooLong>()),
      );
      expect(
        () => authoring.createCard(
          deckId: deck,
          front: 'f',
          back: 'b' * (kBackMaxGraphemes + 1),
          at: t0,
        ),
        throwsA(isA<CardTooLong>()),
      );
    });

    test('the limit is counted in graphemes, not code units', () async {
      // 120 emoji is 120 characters to the user, whatever the byte count.
      final deck = await authoring.createDeck(name: 'A', at: t0);
      await authoring.createCard(
        deckId: deck,
        front: '👍🏽' * kFrontMaxGraphemes,
        back: 'v',
        at: t0,
      );
      expect((await db.select(db.cards).get()).length, 1);
    });

    test('editing past the limit is refused and changes nothing', () async {
      final deck = await authoring.createDeck(name: 'A', at: t0);
      final card =
          await authoring.createCard(deckId: deck, front: 'curto', back: 'v', at: t0);

      expect(
        () => authoring.editCard(
          cardId: card,
          front: 'a' * (kFrontMaxGraphemes + 1),
          at: t0,
        ),
        throwsA(isA<CardTooLong>()),
      );
      expect((await db.select(db.cards).getSingle()).front, 'curto');
    });
  });

  group('editing never disturbs the schedule (§3)', () {
    test('fixing a typo keeps months of history', () async {
      final study = StudyService(
        db,
        deviceId: 'phone',
        params: FsrsParams(weights: defaultFsrsWeights),
      );
      final deck = await authoring.createDeck(name: 'A', at: t0);
      final card = await authoring.createCard(
        deckId: deck,
        front: 'O que foi a Revolucao Gloriosa?',
        back: 'v',
        at: t0,
      );

      var at = t0;
      for (var i = 0; i < 5; i++) {
        final state = await study.recordReview(cardId: card, grade: Grade.good, at: at);
        at = state.dueAt!;
      }
      final before = await study.stateOf(card);

      await authoring.editCard(
        cardId: card,
        front: 'O que foi a Revolução Gloriosa?', // one accent
        at: at,
      );

      final after = await study.stateOf(card);
      expect(after.dueAt, before.dueAt);
      expect(after.stability, before.stability);
      expect(after.reps, before.reps);
    });
  });

  group('bulk operations (§5.10)', () {
    Future<List<String>> threeCards(String deck) async {
      return [
        for (var i = 0; i < 3; i++)
          await authoring.createCard(deckId: deck, front: 'f$i', back: 'v$i', at: t0),
      ];
    }

    test('cards move between decks in one go', () async {
      final from = await authoring.createDeck(name: 'A', at: t0);
      final to = await authoring.createDeck(name: 'B', at: t0);
      final cards = await threeCards(from);

      expect(await authoring.moveCards(cards, to, t0), 3);
      // Compared unordered: UUIDv7 orders by time, and three cards created in
      // the same millisecond are separated only by their random bits. The list
      // is deterministic, it just is not creation order at that resolution.
      expect(await authoring.listCards(deckId: to), unorderedEquals(cards));
      expect(await authoring.listCards(deckId: from), isEmpty);
    });

    test('tagging merges rather than replacing', () async {
      final deck = await authoring.createDeck(name: 'A', at: t0);
      final card = await authoring.createCard(
        deckId: deck,
        front: 'f',
        back: 'v',
        at: t0,
        tags: ['historia'],
      );

      await authoring.addTags([card], ['Revolução', 'HISTORIA'], t0);

      final tags =
          (jsonDecode((await db.select(db.cards).getSingle()).tags) as List).cast<String>();
      expect(tags, containsAll(['historia', 'revolução']));
      expect(tags.length, 2, reason: 'case-folded, so historia is not duplicated');
    });

    test('cards are deleted in one go', () async {
      final deck = await authoring.createDeck(name: 'A', at: t0);
      final cards = await threeCards(deck);

      expect(await authoring.deleteCards(cards.take(2).toList(), t0), 2);
      expect(await authoring.listCards(deckId: deck), [cards[2]]);
    });

    test('an empty selection is a no-op, not an error', () async {
      expect(await authoring.moveCards(const [], 'qualquer', t0), 0);
      expect(await authoring.deleteCards(const [], t0), 0);
    });

    test('the list filters by tag and by state', () async {
      final deck = await authoring.createDeck(name: 'A', at: t0);
      final cards = await threeCards(deck);
      await authoring.addTags([cards[0]], ['prova'], t0);

      expect(await authoring.listCards(deckId: deck, tag: 'prova'), [cards[0]]);

      final study = StudyService(
        db,
        deviceId: 'phone',
        params: FsrsParams(weights: defaultFsrsWeights),
      );
      await study.suspend(cards[1], t0);
      expect(await authoring.listCards(deckId: deck, status: 'suspended'), [cards[1]]);
    });
  });

  group('the outbox is fed by every write (§6.4)', () {
    test('an edit re-queues the row for push', () async {
      final deck = await authoring.createDeck(name: 'A', at: t0);
      final card = await authoring.createCard(deckId: deck, front: 'f', back: 'v', at: t0);

      await db.customStatement('UPDATE cards SET server_seq = 5');
      expect((await db.select(db.cards).getSingle()).serverSeq, 5);

      await authoring.editCard(cardId: card, front: 'trocado', at: t0);
      expect(
        (await db.select(db.cards).getSingle()).serverSeq,
        isNull,
        reason: 'an edited row has to travel again',
      );
    });

    test('a bulk move re-queues every row it touched', () async {
      final from = await authoring.createDeck(name: 'A', at: t0);
      final to = await authoring.createDeck(name: 'B', at: t0);
      final cards = [
        for (var i = 0; i < 3; i++)
          await authoring.createCard(deckId: from, front: 'f$i', back: 'v', at: t0),
      ];
      await db.customStatement('UPDATE cards SET server_seq = 5');

      await authoring.moveCards(cards, to, t0);
      final pending =
          await (db.select(db.cards)..where((t) => t.serverSeq.isNull())).get();
      expect(pending.length, 3);
    });
  });
}
