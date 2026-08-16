import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme.dart';
import 'deck_manage_screen.dart';
import 'editor_screen.dart';

/// Screen `02 Baralhos`.
///
/// Shows the proportion **mature**, never "68% concluído" — §13 records that
/// correction, because nothing is ever concluded in spaced repetition.
class DecksScreen extends ConsumerWidget {
  const DecksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = ref.watch(decksProvider);
    final maturity = ref.watch(deckMaturityProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Seus baralhos')),
      body: decks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rows) => rows.isEmpty
            ? const _Empty()
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final deck = rows[i];
                  final stats = maturity.valueOrNull?[deck.id];
                  return _DeckTile(
                    name: deck.name,
                    total: stats?.total ?? 0,
                    mature: stats?.mature ?? 0,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EditorScreen(deckId: deck.id, deckName: deck.name),
                      ),
                    ),
                    // §5.10 — managing a deck is a different intent from
                    // adding to it, so it gets its own affordance rather than
                    // a long press nobody discovers.
                    onManage: () => Navigator.of(context).push(
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

class _DeckTile extends StatelessWidget {
  const _DeckTile({
    required this.name,
    required this.total,
    required this.mature,
    required this.onTap,
    required this.onManage,
  });

  final String name;
  final int total;
  final int mature;
  final VoidCallback onTap;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : mature / total;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.hairline),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                ),
                Text('${(ratio * 100).round()}%',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.accent)),
                IconButton(
                  icon: const Icon(Icons.more_horiz, size: 20, color: AppColors.faint),
                  tooltip: 'Gerenciar',
                  onPressed: onManage,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 5,
                backgroundColor: AppColors.hairline,
                valueColor: const AlwaysStoppedAnimation(AppColors.navy),
              ),
            ),
            const SizedBox(height: 8),
            // The wording matters: "maduros", not "concluído" (§5.2).
            Text('$mature de $total maduros',
                style: const TextStyle(fontSize: 12, color: AppColors.faint)),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Nenhum baralho ainda.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted),
        ),
      ),
    );
  }
}
