import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:store/store.dart' as store;

import '../format.dart';
import '../providers.dart';
import '../providers_today.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../ui/ui.dart';
import 'deck_actions.dart';
import 'deck_detail_screen.dart';
import 'editor_screen.dart';

/// Por que filtro a biblioteca.
enum _Filter { all, due, mature }

/// A Biblioteca — artboard 02.
///
/// Absorve a antiga tela de busca. Ela era um destino separado, alcançado por
/// uma lupa no canto, o que fazia procurar um card parecer outra atividade;
/// aqui o campo está sempre visível e a busca é a mesma tela com outro
/// conteúdo.
class DecksScreen extends ConsumerStatefulWidget {
  const DecksScreen({super.key});

  @override
  ConsumerState<DecksScreen> createState() => _DecksScreenState();
}

class _DecksScreenState extends ConsumerState<DecksScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<store.Card> _results = const [];
  _Filter _filter = _Filter.all;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    // Com debounce: uma consulta por tecla numa coleção de milhares é uma
    // consulta por tecla.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () => _search(query));
    setState(() {});
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      if (mounted) setState(() => _results = const []);
      return;
    }
    final results = await ref.read(databaseProvider).searchCards(query);
    if (mounted) setState(() => _results = results);
  }

  Future<void> _createDeck() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Novo baralho'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nome'),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Criar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;

    final authoring = await ref.read(authoringServiceProvider.future);
    final deckId = await authoring.createDeck(name: name, at: ref.read(clockProvider)());
    ref
      ..invalidate(decksProvider)
      ..invalidate(deckCardCountsProvider);

    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => EditorScreen(deckId: deckId, deckName: name)),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider).valueOrNull ?? const [];
    final counts = ref.watch(deckCardCountsProvider).valueOrNull ?? const <String, int>{};
    final maturity = ref.watch(deckMaturityProvider).valueOrNull ?? const {};
    final due = ref.watch(dueByDeckProvider).valueOrNull ?? const <String, int>{};
    final now = ref.watch(clockProvider)();

    final totalCards = counts.values.fold(0, (sum, n) => sum + n);
    final searching = _query.text.trim().isNotEmpty;

    final visible = switch (_filter) {
      _Filter.all => decks,
      _Filter.due => decks.where((d) => (due[d.id] ?? 0) > 0).toList(),
      _Filter.mature => decks.where((d) => (maturity[d.id]?.mature ?? 0) > 0).toList(),
    };

    // Sem nenhum baralho não há o que buscar nem o que filtrar. Um campo
    // "Buscar em 0 cards" com três chips que filtram o nada é uma tela cheia
    // de controles que não fazem nada — e o que a pessoa precisava era de uma
    // frase dizendo por onde começar.
    if (decks.isEmpty) return _firstDeck();

    return ScreenBody(
      children: [
        // §M14 — o "+" do topo e o convite tracejado faziam exatamente a mesma
        // coisa, e o "+" ainda estava na posição de ação de AppBar, não de
        // criação. Sobrou o convite, que ao menos diz de quantas maneiras dá
        // para criar.
        const ScreenHeader(title: 'Biblioteca'),
        const SizedBox(height: MnemosSpacing.lg),
        TextField(
          controller: _query,
          onChanged: _onQueryChanged,
          style: MnemosText.body.copyWith(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Buscar em ${plural(totalCards, 'card', 'cards')}',
            prefixIcon: const Icon(Icons.search, size: 20, color: MnemosColors.fainter),
            suffixIcon: searching
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Limpar a busca',
                    onPressed: () {
                      _query.clear();
                      _onQueryChanged('');
                    },
                  )
                : null,
          ),
        ),
        const SizedBox(height: MnemosSpacing.md),
        if (searching)
          ..._searchResults(decks)
        else ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (i, entry) in const [
                  (_Filter.all, 'Todos'),
                  (_Filter.due, 'Vencendo'),
                  (_Filter.mature, 'Maduros'),
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: MnemosSpacing.sm),
                  MnemosChip(
                    label: entry.$2,
                    selected: _filter == entry.$1,
                    onTap: () => setState(() => _filter = entry.$1),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: MnemosSpacing.xl),
          for (final deck in visible) ...[
            _DeckCard(
              name: deck.name,
              updated: relativeSince(
                    DateTime.fromMillisecondsSinceEpoch(deck.updatedAt),
                    now,
                  ) ??
                  'sem alterações',
              total: counts[deck.id] ?? 0,
              due: due[deck.id] ?? 0,
              mature: maturity[deck.id]?.mature ?? 0,
              onMenu: () => _deckMenu(deck.id, deck.name),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DeckDetailScreen(deckId: deck.id, deckName: deck.name),
                ),
              ),
            ),
            const SizedBox(height: MnemosSpacing.md),
          ],
          if (visible.isEmpty)
            const SurfaceCard(
              child: Text('Nenhum baralho neste filtro.', style: MnemosText.bodySmall),
            ),
          DashedInvite(
            icon: Icons.add,
            title: 'Novo baralho',
            detail: 'À mão, por tópico, PDF ou foto',
            onTap: _createDeck,
          ),
        ],
      ],
    );
  }

  /// A Biblioteca antes do primeiro baralho.
  ///
  /// §5.1 — um estado vazio é uma tela, não um acidente. Diz o que a
  /// Biblioteca é, o que ela vai guardar, e oferece o caminho preferencial em
  /// vez de deixar a pessoa deduzi-lo de uma linha tracejada.
  Widget _firstDeck() {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: MnemosSpacing.screen),
          child: ScreenHeader(title: 'Biblioteca'),
        ),
        // Um bloco centrado, não três elementos empilhados contra o topo com
        // 900 px vazios embaixo. Lembretes e Fotos resolvem o vazio com um
        // bloco só, e a ação nunca é um preenchido de largura total.
        Expanded(
          child: StatusScreen(
            icon: Icons.library_books_outlined,
            eyebrow: 'ainda vazia',
            title: 'Aqui ficam os seus baralhos',
            message: 'Um baralho é um assunto: uma matéria, um capítulo, um '
                'idioma. Os cards moram dentro dele, e é o baralho que você '
                'escolhe mandar para o Mnemos T5.',
            action: _createDeck,
            actionLabel: 'Criar o primeiro baralho',
          ),
        ),
      ],
    );
  }


  Future<void> _deckMenu(String deckId, String name) async {
    final outcome = await showDeckActions(context, ref, deckId: deckId, name: name);
    if (outcome != null && mounted) setState(() {});
  }

  List<Widget> _searchResults(List<store.Deck> decks) {
    if (_results.isEmpty) {
      return const [
        SurfaceCard(
          child: Text('Nenhum card com esse texto.', style: MnemosText.bodySmall),
        ),
      ];
    }

    final names = {for (final d in decks) d.id: d.name};
    final found = _results.map((c) => c.deckId).toSet().length;

    return [
      // §M17 — um resultado sem procedência é um card órfão: dá para lê-lo e
      // não dá para ir até ele. A contagem também é resposta: "nenhum" e
      // "quarenta e dois" pedem coisas diferentes da pessoa.
      Text(
        '${plural(_results.length, 'resultado', 'resultados')} em '
        '${plural(found, 'baralho', 'baralhos')}',
        style: MnemosText.caption,
      ),
      const SizedBox(height: MnemosSpacing.md),
      for (final (i, card) in _results.indexed) ...[
        if (i > 0) const SizedBox(height: MnemosSpacing.sm),
        CardTile(
          front: card.front,
          back: card.back,
          deck: names[card.deckId] ?? 'baralho removido',
        ),
      ],
    ];
  }
}

/// O card de um baralho: nome, quando mudou, e a proporção do que vence, do
/// que está maduro e do resto.
class _DeckCard extends StatelessWidget {
  const _DeckCard({
    required this.name,
    required this.updated,
    required this.total,
    required this.due,
    required this.mature,
    required this.onTap,
    required this.onMenu,
  });

  final String name;
  final String updated;
  final int total;
  final int due;
  final int mature;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final rest = (total - due - mature).clamp(0, total);

    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        MnemosSpacing.lg,
        MnemosSpacing.md,
        MnemosSpacing.sm,
        MnemosSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: Text(name, style: MnemosText.cardTitle)),
              // Era um `Icon` solto dentro de um card clicável: tocar no "..."
              // abria o baralho, que é a única coisa que um "..." não pode
              // fazer. Agora é botão de verdade, com alvo de 48 e o mesmo menu
              // do detalhe do baralho.
              IconButton(
                onPressed: onMenu,
                tooltip: 'Ações do baralho $name',
                icon: const Icon(Icons.more_horiz, color: MnemosColors.muted, size: 20),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: MnemosSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Atualizado $updated', style: MnemosText.bodySmall),
                const SizedBox(height: MnemosSpacing.md),
                SegmentBar(
                  semanticLabel: '$name: $due vencendo, $mature maduros, $total no total.',
                  segments: [
                    (weight: due, color: MnemosColors.due),
                    (weight: mature, color: MnemosColors.primary),
                    (weight: rest, color: MnemosColors.line),
                  ],
                ),
                const SizedBox(height: MnemosSpacing.md),
                Wrap(
                  spacing: MnemosSpacing.lg,
                  runSpacing: MnemosSpacing.sm,
                  children: [
                    if (due > 0) LegendDot(color: MnemosColors.due, label: '$due vencendo'),
                    LegendDot(color: MnemosColors.primary, label: '$mature maduros'),
                    LegendDot(color: MnemosColors.primary60, label: '$total total'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
