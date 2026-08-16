import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../providers_modes.dart';
import '../../theme.dart';
import 'audio_screen.dart';
import 'counts_badge.dart';
import 'leech_drill_screen.dart';
import 'multiple_choice_screen.dart';
import 'simulado_screen.dart';

/// Screen `27 Modos de estudo` — §5.9.
///
/// All four start from the same cards. The badge on each row is the whole
/// point of the screen: three of them are practice, one of them is study.
class ModesScreen extends ConsumerWidget {
  const ModesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(queueProvider);
    final leeches = ref.watch(leechesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Outros modos')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const Text(
            'Todos partem dos mesmos cards. Só a múltipla escolha entra no seu '
            'cronograma.',
            style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.muted),
          ),
          const SizedBox(height: 22),
          _ModeTile(
            title: 'Múltipla escolha',
            description:
                'O app monta alternativas com respostas de outros cards do mesmo baralho.',
            icon: Icons.checklist_rtl_outlined,
            counts: true,
            enabled: queue.valueOrNull?.isNotEmpty ?? false,
            disabledReason: 'Nada vencendo agora.',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => MultipleChoiceScreen(queue: queue.value ?? const []),
            )),
          ),
          const SizedBox(height: 12),
          _ModeTile(
            title: 'Só os que erro muito',
            description: 'Os cards que mais voltaram para o começo.',
            icon: Icons.replay_outlined,
            counts: false,
            enabled: leeches.valueOrNull?.isNotEmpty ?? false,
            disabledReason: 'Você ainda não tem cards teimosos o bastante.',
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const LeechDrillScreen())),
          ),
          const SizedBox(height: 12),
          _ModeTile(
            title: 'Simulado cronometrado',
            description: 'Formato de prova: sem resposta durante, resultado só no fim.',
            icon: Icons.timer_outlined,
            counts: false,
            enabled: true,
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SimuladoSetupScreen())),
          ),
          const SizedBox(height: 12),
          _ModeTile(
            title: 'Áudio',
            description: 'Lê a frente, dá um tempo, lê o verso. Para o trajeto e a academia.',
            icon: Icons.headphones_outlined,
            counts: false,
            enabled: queue.valueOrNull?.isNotEmpty ?? false,
            disabledReason: 'Nada vencendo agora.',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AudioScreen(queue: queue.value ?? const []),
            )),
          ),
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.title,
    required this.description,
    required this.icon,
    required this.counts,
    required this.enabled,
    required this.onTap,
    this.disabledReason,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool counts;
  final bool enabled;
  final VoidCallback onTap;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : .5,
      child: InkWell(
        onTap: enabled ? onTap : null,
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
                  Icon(icon, size: 20, color: AppColors.navy),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500)),
                  ),
                  CountsBadge(counts: counts),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                enabled ? description : (disabledReason ?? description),
                style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
