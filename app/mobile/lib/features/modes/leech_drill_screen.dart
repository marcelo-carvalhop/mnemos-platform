import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers_modes.dart';
import '../../theme.dart';
import 'counts_badge.dart';

/// Screen `29 Só os que erro muito` — §5.9.
///
/// Extra practice. The banner is not decoration: §5.9 says plainly that a user
/// who believes this is getting work done will distort their own schedule.
/// There is no grade bar, because there is nothing to record.
class LeechDrillScreen extends ConsumerStatefulWidget {
  const LeechDrillScreen({super.key});

  @override
  ConsumerState<LeechDrillScreen> createState() => _LeechDrillScreenState();
}

class _LeechDrillScreenState extends ConsumerState<LeechDrillScreen> {
  int _index = 0;
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final leeches = ref.watch(leechesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Só os que erro muito')),
      body: leeches.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (cards) {
          if (cards.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nenhum card seu voltou ao começo vezes o bastante para entrar aqui.',
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 1.5, color: AppColors.muted),
                ),
              ),
            );
          }

          if (_index >= cards.length) {
            return _Done(onPop: () => Navigator.of(context).pop());
          }

          final card = cards[_index];

          return SafeArea(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: CountsBadge(counts: false, expanded: true),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: _revealed ? null : () => setState(() => _revealed = true),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'errado ${card.lapses} vezes',
                            style: const TextStyle(fontSize: 12, color: AppColors.hard),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            card.front,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 22, height: 1.35, color: AppColors.ink),
                          ),
                          if (_revealed) ...[
                            const SizedBox(height: 28),
                            const SizedBox(
                              width: 40,
                              child: Divider(color: AppColors.hairline, thickness: 1.5),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              card.back,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 17, height: 1.5, color: AppColors.muted),
                            ),
                          ] else ...[
                            const SizedBox(height: 40),
                            const Text('Toque para revelar',
                                style: TextStyle(fontSize: 13, color: AppColors.faint)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (_revealed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: SizedBox(
                      width: double.infinity,
                      // One button, not four: there is no grade to give,
                      // because nothing is being recorded.
                      child: FilledButton(
                        onPressed: () => setState(() {
                          _index++;
                          _revealed = false;
                        }),
                        child: Text(_index + 1 >= cards.length
                            ? 'Terminar'
                            : 'Próximo · ${_index + 1}/${cards.length}'),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.onPop});

  final VoidCallback onPop;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.fitness_center_outlined, size: 40, color: AppColors.hard),
            const SizedBox(height: 18),
            const Text('Treino feito',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            const Text(
              'Seu cronograma continua igual. Estes cards voltam na hora que já iam voltar.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.muted),
            ),
            const SizedBox(height: 30),
            FilledButton(onPressed: onPop, child: const Text('Voltar')),
          ],
        ),
      ),
    );
  }
}
