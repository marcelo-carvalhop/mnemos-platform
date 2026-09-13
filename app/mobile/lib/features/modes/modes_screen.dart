import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../providers_modes.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../ui/ui.dart';
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
      body: SafeArea(
        bottom: false,
        child: ScreenBody(
          children: [
            const BackHeader(label: 'Hoje'),
            const SizedBox(height: MnemosSpacing.md),
            const Text('Outros modos', style: MnemosText.screenTitle),
            const SizedBox(height: MnemosSpacing.sm),
            const Text(
              'Todos partem dos mesmos cards. Só a múltipla escolha entra no '
              'seu cronograma.',
              style: MnemosText.bodySmall,
            ),
            const SizedBox(height: MnemosSpacing.xl),
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
            const SizedBox(height: MnemosSpacing.md),
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
            const SizedBox(height: MnemosSpacing.md),
            _ModeTile(
            title: 'Simulado cronometrado',
            description: 'Formato de prova: sem resposta durante, resultado só no fim.',
            icon: Icons.timer_outlined,
            counts: false,
            enabled: true,
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SimuladoSetupScreen())),
          ),
            const SizedBox(height: MnemosSpacing.md),
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
    // Desabilitado não some nem apaga: o ladrilho continua legível e a linha
    // de apoio troca a descrição pela razão. Um bloco a 50% de opacidade diz
    // "quebrado"; este diz "ainda não".
    return SurfaceCard(
      onTap: enabled ? onTap : null,
      background: enabled ? MnemosColors.raised : MnemosColors.sunken,
      border: enabled ? MnemosColors.line : MnemosColors.hairline,
      padding: const EdgeInsets.all(MnemosSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // O selo desce para a própria linha: ele diz "conta para o
          // agendamento", que é longo, e disputando a linha do título fazia
          // "Múltipla escolha" quebrar em duas. O título é o que a pessoa
          // procura ao varrer a lista; ele não cede espaço.
          Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: enabled ? MnemosColors.primary : MnemosColors.fainter,
              ),
              const SizedBox(width: MnemosSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: MnemosText.itemTitle.copyWith(
                    color: enabled ? MnemosColors.ink : MnemosColors.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MnemosSpacing.sm),
          Text(
            enabled ? description : (disabledReason ?? description),
            style: MnemosText.bodySmall,
          ),
          const SizedBox(height: MnemosSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: CountsBadge(counts: counts),
          ),
        ],
      ),
    );
  }
}
