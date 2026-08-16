import 'package:drift/drift.dart';

import 'database.dart';

/// Search over cards (§5.10).
///
/// Goes through `cards_fts`, whose tokenizer is configured with
/// `remove_diacritics 2` — not optional in Portuguese: without it, searching
/// "funcao" does not find "função" and the feature reads as broken by anyone
/// typing on a keyboard without accents, which is most people in a hurry.
extension CardSearch on AppDatabase {
  /// Cards matching [query], most relevant first.
  ///
  /// Returns nothing for an empty or punctuation-only query rather than
  /// everything: a search box that dumps the whole collection on a stray
  /// keystroke is worse than one that waits.
  Future<List<Card>> searchCards(String query, {int limit = 50}) async {
    final terms = _terms(query);
    if (terms.isEmpty) return const [];

    final rows = await customSelect(
      '''
      SELECT c.* FROM cards_fts f
        JOIN cards c ON c.rowid = f.rowid
       WHERE cards_fts MATCH ?1
         AND c.deleted_at IS NULL
       ORDER BY bm25(cards_fts)
       LIMIT ?2
      ''',
      variables: [Variable<String>(terms), Variable<int>(limit)],
      readsFrom: {cards},
    ).get();

    return rows.map((r) => cards.map(r.data)).toList();
  }

  /// Turns what someone typed into an FTS5 query.
  ///
  /// Every term is quoted and given a prefix `*`, so "revol glor" finds
  /// "Revolução Gloriosa" while the user is still typing. Quoting matters:
  /// FTS5 reads bare `-`, `"` and `*` as syntax, and an unbalanced quote is a
  /// SQL error rather than an empty result — a search box must never be able
  /// to throw because of what was typed into it.
  static String _terms(String query) {
    final words = query
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '';
    return words.map((w) => '"${w.replaceAll('"', '')}"*').join(' ');
  }
}
