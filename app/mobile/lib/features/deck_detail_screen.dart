import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../providers_today.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../ui/ui.dart';
import 'deck_actions.dart';
import 'device_screen.dart';
import 'editor_screen.dart';

/// O baralho por dentro — artboard 03.
///
/// Substitui a antiga "Gerenciar baralho", que era uma lista de ações e não
/// mostrava um único card. O design inverte a ênfase: o baralho é o conteúdo,
/// as ações destrutivas vão para o menu. Renomear, arquivar e apagar
/// continuam aqui, com as mesmas garantias de antes (§5.10) — arquivar não é
/// apagar, e apagar leva o histórico junto.
class DeckDetailScreen extends ConsumerStatefulWidget {
  const DeckDetailScreen({super.key, required this.deckId, required this.deckName});

  final String deckId;
  final String deckName;

  @override
  ConsumerState<DeckDetailScreen> createState() => _DeckDetailScreenState();
}

class _DeckDetailScreenState extends ConsumerState<DeckDetailScreen> {
  late String _name = widget.deckName;

  Future<void> _menu() async {
    final outcome = await showDeckActions(
      context,
      ref,
      deckId: widget.deckId,
      name: _name,
    );
    if (outcome == null || !mounted) return;

    switch (outcome.action) {
      case DeckAction.renamed:
        setState(() => _name = outcome.name!);
      // Arquivar e apagar tiram o baralho da lista; ficar olhando para a tela
      // de um baralho que não existe mais seria olhar para um fantasma.
      case DeckAction.archived:
      case DeckAction.deleted:
        Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final buckets = ref.watch(deckCardsByBucketProvider(widget.deckId)).valueOrNull;
    final total = ref.watch(deckCardCountsProvider).valueOrNull?[widget.deckId] ?? 0;

    // Duas contagens que não são a mesma coisa e que a tela mostrava lado a
    // lado como se fossem: `queued` é o que a fila de hoje realmente vai
    // pedir, já com o teto diário de §5.8 aplicado, e `overdue` é quantos
    // cards passaram da data. O ladrilho dizia "2 vencendo" e a seção logo
    // abaixo dizia "VENCENDO HOJE 3", ambos corretos e juntos incompreensíveis.
    // Agora cada número carrega o seu próprio rótulo, e quando os dois diferem
    // a seção diz por quê em vez de escolher um em silêncio.
    final queued = ref.watch(dueByDeckProvider).valueOrNull?[widget.deckId] ?? 0;
    final overdue = buckets?.dueToday.length ?? 0;
    final average = ref.watch(deckAverageIntervalProvider(widget.deckId)).valueOrNull;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ScreenBody(
          children: [
            BackHeader(label: 'Biblioteca', onMenu: _menu),
            const SizedBox(height: MnemosSpacing.md),
            Text(_name, style: MnemosText.screenTitleWrapped),
            const SizedBox(height: MnemosSpacing.lg),
            Row(
              children: [
                _Stat(value: '$total', label: 'cards'),
                const SizedBox(width: MnemosSpacing.sm),
                _Stat(
                  value: '$queued',
                  label: 'na fila hoje',
                  color: queued > 0 ? MnemosColors.dueText : null,
                ),
                const SizedBox(width: MnemosSpacing.sm),
                _Stat(
                  value: average == null ? '—' : average.toStringAsFixed(1).replaceAll('.', ','),
                  label: 'dias médios',
                ),
              ],
            ),
            const SizedBox(height: MnemosSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    // O editor é uma tarefa com começo e fim, então cobre a
                    // barra de abas em vez de conviver com ela.
                    onPressed: () => Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(
                        builder: (_) => EditorScreen(deckId: widget.deckId, deckName: _name),
                      ),
                    ),
                    child: const Text('Adicionar card'),
                  ),
                ),
                const SizedBox(width: MnemosSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DeviceScreen()),
                    ),
                    child: const Text('Enviar ao T5'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: MnemosSpacing.xxl),
            if (buckets == null)
              const Center(child: Padding(
                padding: EdgeInsets.all(MnemosSpacing.xxl),
                child: CircularProgressIndicator(),
              ))
            else if (total == 0)
              const SurfaceCard(
                child: Text(
                  'Nenhum card aqui ainda. "Adicionar card" escreve o primeiro.',
                  style: MnemosText.bodySmall,
                ),
              )
            else ...[
              BucketSection(
                label: 'vencendo hoje',
                color: MnemosColors.due,
                detail: queued < overdue
                    ? '$queued ${queued == 1 ? 'entra' : 'entram'} na fila de hoje; '
                        'o resto espera o teto diário abrir.'
                    : null,
                children: [for (final c in buckets.dueToday) _tile(c, due: true)],
              ),
              if (buckets.dueToday.isNotEmpty && buckets.thisWeek.isNotEmpty)
                const SizedBox(height: MnemosSpacing.lg),
              BucketSection(
                label: 'esta semana',
                color: MnemosColors.primary,
                children: [for (final c in buckets.thisWeek) _tile(c)],
              ),
              if (buckets.thisWeek.isNotEmpty && buckets.settled.isNotEmpty)
                const SizedBox(height: MnemosSpacing.lg),
              BucketSection(
                label: 'já firmes',
                color: MnemosColors.settled,
                children: [for (final c in buckets.settled) _tile(c)],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tile(DeckCardView card, {bool due = false}) => CardTile(
        front: card.front,
        back: card.back,
        due: due,
        trailing: (due || card.intervalDays == null) ? null : '${card.intervalDays} d',
      );
}

/// Um dos três números do topo.
class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SurfaceCard(
        radius: MnemosRadii.control,
        padding: const EdgeInsets.all(MnemosSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: color == null
                  ? MnemosText.numeralSmall
                  : MnemosText.numeralSmall.copyWith(color: color),
            ),
            const SizedBox(height: MnemosSpacing.xs),
            Text(label, style: MnemosText.caption.copyWith(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
