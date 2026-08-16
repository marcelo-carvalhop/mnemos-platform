import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme.dart';
import 'deck_manage_screen.dart';
import 'editor_screen.dart';

/// Biblioteca do Mnemos.
///
/// Esta tela existe apenas para criar, abrir e organizar conteúdo. Métricas de
/// retenção, maturidade e sequência pertencem exclusivamente a Estatísticas.
class DecksScreen extends ConsumerWidget {
  const DecksScreen({super.key});

  Future<void> _createDeck(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Novo baralho'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nome',
            border: OutlineInputBorder(),
          ),
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

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditorScreen(deckId: deckId, deckName: name),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = ref.watch(decksProvider);
    final counts = ref.watch(deckCardCountsProvider).valueOrNull ?? const <String, int>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Biblioteca'),
        actions: [
          IconButton(
            tooltip: 'Novo baralho',
            icon: const Icon(Icons.add),
            onPressed: () => _createDeck(context, ref),
          ),
        ],
      ),
      body: decks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rows) => rows.isEmpty
            ? _Empty(onCreate: () => _createDeck(context, ref))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final deck = rows[i];
                  final total = counts[deck.id] ?? 0;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 5),
                    title: Text(deck.name),
                    subtitle: Text('$total ${total == 1 ? 'card' : 'cards'}'),
                    trailing: IconButton(
                      tooltip: 'Gerenciar',
                      icon: const Icon(Icons.more_horiz, color: AppColors.sage),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DeckManageScreen(
                            deckId: deck.id,
                            deckName: deck.name,
                          ),
                        ),
                      ),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EditorScreen(
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

class _Empty extends StatelessWidget {
  const _Empty({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Nenhum baralho.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: onCreate, child: const Text('Criar baralho')),
          ],
        ),
      ),
    );
  }
}
