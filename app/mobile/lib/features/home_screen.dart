import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../providers_sync.dart';
import '../theme.dart';
import 'decks_screen.dart';
import 'generation/capture_screen.dart';
import 'generation/generate_screen.dart';
import 'progress_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'sync_badge.dart';
import 'modes/modes_screen.dart';
import 'study_screen.dart';
import 'terminal_screen.dart';

/// Screen `01 Hoje` / `25 Hoje com criar`.
///
/// The central element is what has to be studied today (§5.2), and the
/// headline is accumulated memory — never a count of cards, which §2.3
/// forbids.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memory = ref.watch(accumulatedMemoryProvider);
    final queue = ref.watch(queueProvider);
    final goal = ref.watch(dailyGoalProvider);
    final studied = ref.watch(studiedTodayProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hoje'),
        actions: [
          const SyncBadge(),
          IconButton(
            icon: const Icon(Icons.devices_other_outlined, size: 21),
            tooltip: 'Terminal Mnemos',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TerminalScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search, size: 21),
            tooltip: 'Buscar',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 21),
            tooltip: 'Configurações',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        // §5.2's create button, absent from the four-tab nav in the canvas.
        backgroundColor: AppColors.navy,
        foregroundColor: AppColors.ivory,
        onPressed: () => _showCreate(context),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Pull-to-refresh is the one place a user explicitly asks for the
          // network; everywhere else syncing is the app's job, not theirs.
          await ref.read(syncControllerProvider.notifier).syncNow();
          ref.invalidate(queueProvider);
          ref.invalidate(accumulatedMemoryProvider);
          ref.invalidate(studiedTodayProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const Text('Sua memória acumulada',
                style: TextStyle(fontSize: 13, color: AppColors.faint)),
            const SizedBox(height: 6),
            memory.when(
              loading: () => const Text('—', style: _headline),
              error: (e, _) => Text('$e', style: const TextStyle(color: AppColors.again)),
              data: (m) => Text(m.label, style: _headline),
            ),
            const SizedBox(height: 4),
            const Text('de conhecimento guardado',
                style: TextStyle(fontSize: 13, color: AppColors.faint)),
            const SizedBox(height: 28),
            _GoalCard(goal: goal, studied: studied),
            const SizedBox(height: 24),
            queue.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('$e'),
              data: (cards) => _StudyAction(
                cards: cards,
                hasAnyCards: ref.watch(hasAnyCardsProvider).valueOrNull ?? true,
                onCreate: () => _showCreate(context),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DecksScreen()),
                  ),
                  child: const Text('Seus baralhos'),
                ),
                // §5.9 lives one tap from Hoje, not buried in settings.
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProgressScreen()),
                  ),
                  child: const Text('Progresso'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ModesScreen()),
                  ),
                  child: const Text('Outros modos'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// §5.3 offers the two ways of making cards side by side, the manual one
  /// first: it is free forever, and it is what most cards will be.
  void _showCreate(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppColors.navy),
              title: const Text('Escrever um card'),
              subtitle: const Text('Livre, sempre'),
              onTap: () {
                Navigator.of(sheet).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DecksScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined, color: AppColors.navy),
              title: const Text('Gerar por tópico'),
              subtitle: const Text('Usa sua cota de geração'),
              onTap: () {
                Navigator.of(sheet).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GenerateScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.navy),
              title: const Text('Foto ou PDF'),
              subtitle: const Text('Usa sua cota de geração'),
              onTap: () {
                Navigator.of(sheet).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CaptureScreen()),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static const _headline =
      TextStyle(fontSize: 30, fontWeight: FontWeight.w500, color: AppColors.ink);
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.studied});

  final AsyncValue<int> goal;
  final AsyncValue<int> studied;

  @override
  Widget build(BuildContext context) {
    final target = goal.valueOrNull ?? 0;
    final done = studied.valueOrNull ?? 0;
    final ratio = target == 0 ? 0.0 : (done / target).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: ratio,
                  strokeWidth: 4,
                  backgroundColor: AppColors.ivory,
                  valueColor: const AlwaysStoppedAnimation(AppColors.navy),
                ),
                Text('${(ratio * 100).round()}%',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$done / $target cards',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                const Text('meta de hoje',
                    style: TextStyle(fontSize: 12, color: AppColors.faint)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StudyAction extends StatelessWidget {
  const _StudyAction({
    required this.cards,
    required this.hasAnyCards,
    required this.onCreate,
  });

  final List<String> cards;

  /// Nothing due and nothing existing are different situations, and telling
  /// someone with no cards that their memory is working on its own is both
  /// false and faintly absurd.
  final bool hasAnyCards;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty && !hasAnyCards) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.fill,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            const Text('Seu primeiro card',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            const Text(
              'Escreva uma pergunta que você quer lembrar daqui a um ano.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onCreate, child: const Text('Criar um card')),
          ],
        ),
      );
    }

    // §5.2 — with cards that exist and nothing due, the zeroed state is a
    // message of completion rather than a sad empty screen.
    if (cards.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.goodBg,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Column(
          children: [
            Icon(Icons.check_circle_outline, color: AppColors.good, size: 30),
            SizedBox(height: 10),
            Text('Nada vencendo agora',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            SizedBox(height: 6),
            Text(
              'Sua memória segue trabalhando sozinha.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ],
        ),
      );
    }

    return FilledButton(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StudyScreen(queue: cards)),
      ),
      child: Text('Estudar agora · ${cards.length}'),
    );
  }
}
