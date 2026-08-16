import 'package:drift/native.dart';
import 'package:store/store.dart';
import 'package:test/test.dart';

/// §5.10 — search over cards.
///
/// The FTS index and its triggers existed and nothing had ever searched
/// through them. `remove_diacritics 2` in particular was chosen for a reason
/// that only a test states: it is what makes a Brazilian typing without
/// accents find their own cards.
void main() {
  late AppDatabase db;
  var rowId = 0;

  Future<String> card(String front, String back, {bool deleted = false}) async {
    final id = 'card-${rowId++}';
    await db.customStatement(
      'INSERT INTO cards (id, deck_id, front, back, tags, updated_at, deleted_at, device_id) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [id, 'deck', front, back, '[]', 1, deleted ? 1 : null, 'test'],
    );
    return id;
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement(
      "INSERT INTO decks (id, name, updated_at, device_id, origin, version) "
      "VALUES ('deck', 'Baralho', 1, 'test', 'own', 1)",
    );
  });

  tearDown(() => db.close());

  test('a word in the front is found', () async {
    await card('O que é uma função afim?', 'Uma reta.');
    await card('O que é o teorema de Pitágoras?', 'a² + b² = c².');

    final hits = await db.searchCards('função');

    expect(hits.map((c) => c.front), ['O que é uma função afim?']);
  });

  test('typing without accents finds the accented card', () async {
    // The whole reason for `remove_diacritics 2`. Without it this returns
    // nothing and the feature reads as broken.
    await card('O que é uma função afim?', 'Uma reta.');

    expect(await db.searchCards('funcao'), hasLength(1));
    expect(await db.searchCards('FUNCAO'), hasLength(1));
  });

  test('the back is searched too', () async {
    await card('Quem depôs Jaime II?', 'Guilherme de Orange.');

    expect((await db.searchCards('Orange')).single.front, contains('Jaime'));
  });

  test('a prefix matches while the user is still typing', () async {
    await card('Revolução Gloriosa', 'Inglaterra, 1688.');

    expect(await db.searchCards('revol glor'), hasLength(1));
  });

  test('a deleted card is not a result', () async {
    // A tombstone is still a row (§6.3); it is not still a card.
    await card('Card apagado', 'Verso', deleted: true);

    expect(await db.searchCards('apagado'), isEmpty);
  });

  test('an edited card is found by its new text and not its old', () async {
    // The FTS index is kept in step by trigger; nobody has to remember.
    final id = await card('Texto antigo', 'Verso');
    await db.customStatement(
      'UPDATE cards SET front = ?, updated_at = 2 WHERE id = ?',
      ['Texto novo', id],
    );

    expect(await db.searchCards('novo'), hasLength(1));
    expect(await db.searchCards('antigo'), isEmpty);
  });

  test('an empty or punctuation-only query returns nothing, not everything',
      () async {
    await card('Alguma coisa', 'Outra coisa');

    for (final query in ['', '   ', '!!!', '-', '"']) {
      expect(await db.searchCards(query), isEmpty, reason: 'query: "$query"');
    }
  });

  test('FTS5 syntax typed by a user is text, not syntax', () async {
    // An unbalanced quote or a bare `-` is a SQL error in FTS5, and a search
    // box must never be able to throw because of what was typed into it.
    await card('Roteamento IP', 'Tabela de rotas');

    for (final query in ['roteamento"', 'ip -rota', 'tcp*', 'NEAR(a b)', '(']) {
      await expectLater(db.searchCards(query), completes, reason: 'query: "$query"');
    }
  });

  test('results are capped', () async {
    for (var i = 0; i < 30; i++) {
      await card('Pergunta comum $i', 'Verso');
    }

    expect(await db.searchCards('comum', limit: 10), hasLength(10));
  });
}
