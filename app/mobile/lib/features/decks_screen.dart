import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme.dart';
import 'deck_manage_screen.dart';
import 'generation/create_flow_screen.dart';
import 'home_screen.dart' show SettingsAction;
import 'search_screen.dart';

/// Biblioteca do Mnemos.
///
/// Esta tela existe apenas para criar, abrir e organizar conteúdo. Métricas de
/// retenção, maturidade e sequência pertencem exclusivamente a Estatísticas —
/// a proporção de maduros aparece aqui como barra porque é a única coisa que
/// diz se um baralho está sendo estudado ou apenas guardado.
class DecksScreen extends ConsumerWidget {
  const DecksScreen({super.key});

  void _create(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateFlowScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = ref.watch(decksProvider);
    final counts = ref.watch(deckCardCountsProvider).valueOrNull ?? const <String, int>{};
    final maturity = ref.watch(deckMaturityProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Biblioteca'),
        actions: [
          IconButton(
            tooltip: 'Buscar',
            icon: const Icon(Icons.search, size: 22),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          const SettingsAction(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context),
        backgroundColor: AppColors.petrol,
        foregroundColor: AppColors.ivory,
        // A ação primária da biblioteca é criar conteúdo, e criar conteúdo
        // começa pela IA. "Novo baralho" descrevia a estrutura vazia que
        // sobrava depois.
        icon: const Icon(Icons.auto_awesome, size: 20),
        label: const Text('Criar'),
      ),
      body: decks.when(
        // Esqueleto no lugar de um giro: a lista tem forma conhecida, e
        // mostrá-la vazia comunica o que está vindo.
        loading: () => const _Skeleton(),
        error: (e, _) => Center(child: Text('$e')),
        data: (rows) => rows.isEmpty
            ? _Empty(onCreate: () => _create(context))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final deck = rows[i];
                  final stats = maturity?[deck.id];
                  return _DeckCard(
                    name: deck.name,
                    total: counts[deck.id] ?? 0,
                    mature: stats?.mature ?? 0,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DeckManageScreen(
                          deckId: deck.id,
                          deckName: deck.name,
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _DeckCard extends StatelessWidget {
  const _DeckCard({
    required this.name,
    required this.total,
    required this.mature,
    required this.onTap,
  });

  final String name;
  final int total;
  final int mature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : mature / total;

    return Material(
      color: const Color(0xFFFBFAF6),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.mist),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: AppColors.graphite,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: AppColors.sage, size: 22),
                ],
              ),
              const SizedBox(height: 12),
              if (total == 0)
                const Text(
                  'Sem cards ainda',
                  style: TextStyle(fontSize: 12.5, color: AppColors.sage),
                )
              else ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: ratio),
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOut,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 4,
                      backgroundColor: AppColors.mist,
                      valueColor: const AlwaysStoppedAnimation(AppColors.petrol),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  // §5.2 — "maduros", nunca "concluído": nada é concluído em
                  // repetição espaçada.
                  '$total ${total == 1 ? 'card' : 'cards'} · $mature ${mature == 1 ? 'maduro' : 'maduros'}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.sage),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 30, color: AppColors.petrol),
            const SizedBox(height: 18),
            Text('Comece por um assunto',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Diga o que você quer aprender e a IA escreve os cards. '
              'Você aprova um por um antes de qualquer coisa virar baralho.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.sage),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.auto_awesome, size: 19),
              label: const Text('Criar com IA'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => Container(
        height: 96,
        decoration: BoxDecoration(
          color: AppColors.mist.withValues(alpha: .3),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
