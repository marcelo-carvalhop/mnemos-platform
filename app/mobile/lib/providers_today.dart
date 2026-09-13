import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device/terminal_local_store.dart';
import 'providers.dart';

/// Composição para a tela Hoje e para o detalhe de um baralho.
///
/// Tudo aqui é leitura sobre tabelas que já existem. Nenhuma migração.

/// Quantos cards de cada baralho estão na fila de hoje.
///
/// Deriva de [queueProvider], **não** de um `due_at <= agora` próprio. Os dois
/// dariam números diferentes: a fila honra os limites diários de §5.8, e uma
/// contagem crua ignoraria o teto. O badge de um baralho e o número do
/// bloco-herói têm de somar, e só somam se vierem da mesma fonte.
final dueByDeckProvider = FutureProvider<Map<String, int>>((ref) async {
  final queue = await ref.watch(queueProvider.future);
  if (queue.isEmpty) return const {};

  final db = ref.watch(databaseProvider);
  final rows = await (db.select(db.cards)..where((t) => t.id.isIn(queue))).get();

  final counts = <String, int>{};
  for (final card in rows) {
    counts[card.deckId] = (counts[card.deckId] ?? 0) + 1;
  }
  return counts;
});

/// O bloco-herói: "12 cards em 2 baralhos".
final dueTodayProvider = FutureProvider<({int cards, int decks})>((ref) async {
  final byDeck = await ref.watch(dueByDeckProvider.future);
  return (
    cards: byDeck.values.fold(0, (sum, n) => sum + n),
    decks: byDeck.length,
  );
});

/// Um card como o detalhe do baralho precisa dele.
class DeckCardView {
  const DeckCardView({
    required this.id,
    required this.front,
    required this.back,
    required this.dueAt,
    required this.intervalDays,
  });

  final String id;
  final String front;
  final String back;
  final DateTime? dueAt;

  /// Intervalo atual em dias — o `28 d` à direita da linha. Nulo para um card
  /// que ainda não foi revisado: ele não tem intervalo, tem estreia.
  final int? intervalDays;
}

/// Os cards de um baralho, repartidos como o artboard 03 os mostra.
///
/// Três baldes em vez de uma lista ordenada por data: a pergunta que a tela
/// responde não é "quando vence cada um", é "o que preciso olhar hoje, o que
/// vem esta semana, e o que já posso esquecer que existe".
final deckCardsByBucketProvider = FutureProvider.family<
    ({List<DeckCardView> dueToday, List<DeckCardView> thisWeek, List<DeckCardView> settled}),
    String>((ref, deckId) async {
  final db = ref.watch(databaseProvider);
  final now = ref.watch(clockProvider)();
  final day = await ref.watch(dayBucketProvider.future);

  final (_, endOfToday) = day.rangeOf(day.today(now));
  final endOfWeek = now.add(const Duration(days: 7));

  final rows = await db.customSelect(
    '''
    SELECT c.id, c.front, c.back, s.due_at, s.last_review_at
    FROM cards c
    LEFT JOIN card_states s ON s.card_id = c.id
    WHERE c.deck_id = ?1 AND c.deleted_at IS NULL
    ORDER BY s.due_at IS NULL, s.due_at
    ''',
    variables: [Variable<String>(deckId)],
    readsFrom: {db.cards, db.cardStates},
  ).get();

  final dueToday = <DeckCardView>[];
  final thisWeek = <DeckCardView>[];
  final settled = <DeckCardView>[];

  for (final row in rows) {
    final dueMs = row.read<int?>('due_at');
    final lastMs = row.read<int?>('last_review_at');
    final due = dueMs == null ? null : DateTime.fromMillisecondsSinceEpoch(dueMs);

    final view = DeckCardView(
      id: row.read<String>('id'),
      front: row.read<String>('front'),
      back: row.read<String>('back'),
      dueAt: due,
      intervalDays: (dueMs == null || lastMs == null)
          ? null
          : Duration(milliseconds: dueMs - lastMs).inDays,
    );

    // Um card nunca revisado vence hoje: ele está esperando a estreia, e
    // escondê-lo em "já firmes" seria dizer que está firme algo que a pessoa
    // nunca viu.
    if (due == null || !due.isAfter(endOfToday)) {
      dueToday.add(view);
    } else if (due.isBefore(endOfWeek)) {
      thisWeek.add(view);
    } else {
      settled.add(view);
    }
  }

  return (dueToday: dueToday, thisWeek: thisWeek, settled: settled);
});

/// O intervalo médio dos cards já revisados de um baralho — os "4,2 dias
/// médios" do artboard 03.
///
/// Nulo quando nenhum card foi revisado ainda: uma média sobre zero revisões
/// seria `0,0 dias`, que se lê como "você esquece tudo em um dia".
final deckAverageIntervalProvider =
    FutureProvider.family<double?, String>((ref, deckId) async {
  final db = ref.watch(databaseProvider);

  final row = await db.customSelect(
    '''
    SELECT AVG(CAST(s.due_at - s.last_review_at AS REAL)) AS avg_ms
    FROM cards c
    JOIN card_states s ON s.card_id = c.id
    WHERE c.deck_id = ?1 AND c.deleted_at IS NULL
      AND s.due_at IS NOT NULL AND s.last_review_at IS NOT NULL
    ''',
    variables: [Variable<String>(deckId)],
    readsFrom: {db.cards, db.cardStates},
  ).getSingle();

  final avgMs = row.read<double?>('avg_ms');
  if (avgMs == null) return null;
  return avgMs / Duration.millisecondsPerDay;
});

/// Quando o terminal ativo sincronizou pela última vez — o "T5 sincronizado
/// há 2 h" do bloco-herói. Nulo quando não há terminal, ou quando ele nunca
/// sincronizou.
final terminalLastSyncProvider = FutureProvider<DateTime?>((ref) async {
  final store = TerminalLocalStore(ref.watch(databaseProvider));
  final terminal = await store.activeTerminal();
  if (terminal == null) return null;

  final last = await store.lastSync(terminal.deviceId);
  return DateTime.tryParse(last?['at']?.toString() ?? '');
});

/// O terminal ativo, para o bloco do T5 e para a tela Dispositivo.
final activeTerminalProvider = FutureProvider<StoredTerminal?>((ref) async {
  return TerminalLocalStore(ref.watch(databaseProvider)).activeTerminal();
});
