import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:api_client/api_client.dart';

import '../providers.dart';
import '../providers_sync.dart';
import '../theme.dart';
import 'generation/approval_screen.dart';
import 'generation/create_flow_screen.dart';
import 'generation/generating_screen.dart';
import 'home_screen.dart' show SettingsAction;
import 'modes/modes_screen.dart';
import 'study_screen.dart';

/// Estudar no aparelho — §5.2.
///
/// O terminal Mnemos é a superfície de leitura preferida, e continua sendo.
/// Mas estudar só pelo aplicativo não é um plano B: é o que vale antes de o
/// terminal chegar, quando ele fica em casa, e para quem nunca vai comprar um.
/// Um produto que só funciona com o hardware junto tem o tamanho do hardware.
///
/// A Home é navegação e permanece assim; esta é a tela onde o estudo mora,
/// para que a decisão de manter a Home limpa não custe o loop inteiro.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key, this.embedded = false});

  /// Verdadeiro quando é uma aba, e não uma tela empilhada: sem seta de
  /// voltar, e as configurações na barra.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memory = ref.watch(accumulatedMemoryProvider);
    final queue = ref.watch(queueProvider);
    final goal = ref.watch(dailyGoalProvider);
    final studied = ref.watch(studiedTodayProvider);
    final open = ref.watch(openGenerationsProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hoje'),
        automaticallyImplyLeading: !embedded,
        actions: embedded ? const [SettingsAction()] : null,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(queueProvider)
            ..invalidate(accumulatedMemoryProvider)
            ..invalidate(studiedTodayProvider)
            ..invalidate(openGenerationsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            // Antes da manchete: uma geração parada no meio é a única coisa
            // nesta tela que o servidor está esperando a pessoa resolver, e no
            // plano grátis ela é irrepetível (§7.7.1).
            for (final job in open) ...[
              _OpenGeneration(job: job),
              const SizedBox(height: 18),
            ],
            const Text('Sua memória acumulada',
                style: TextStyle(fontSize: 13, color: AppColors.faint)),
            const SizedBox(height: 6),
            memory.when(
              loading: () => const Text('—', style: _headline),
              error: (e, _) => Text('$e', style: const TextStyle(color: AppColors.again)),
              // §2.3 — a manchete é o que a pessoa guardou, nunca quantos
              // cards ela tem.
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
                onCreate: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CreateFlowScreen()),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ModesScreen()),
                ),
                child: const Text('Outros modos'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _headline =
      TextStyle(fontSize: 30, fontWeight: FontWeight.w500, color: AppColors.ink);
}

/// O caminho de volta para uma geração deixada no meio.
///
/// Dois estados, porque são duas esperas diferentes: o servidor ainda
/// escrevendo, e os cards já escritos esperando um sim ou não. Só o segundo é
/// uma cobrança — o primeiro é informação, e é dito sem botão.
class _OpenGeneration extends ConsumerWidget {
  const _OpenGeneration({required this.job});

  final OpenGeneration job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting = job.isWaitingOnMe;
    final title = waiting
        ? '${job.pending} ${job.pending == 1 ? 'card espera' : 'cards esperam'} sua aprovação'
        : 'Gerando seus cards';

    return Material(
      color: waiting ? AppColors.petrol : AppColors.mist.withValues(alpha: .45),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => waiting
                ? ApprovalScreen(jobId: job.id, deckId: job.deckId)
                : GeneratingScreen(jobId: job.id, deckId: job.deckId),
          ));
          ref
            ..invalidate(openGenerationsProvider)
            ..invalidate(queueProvider)
            ..invalidate(hasAnyCardsProvider);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
          child: Row(
            children: [
              Icon(
                waiting ? Icons.fact_check_outlined : Icons.auto_awesome,
                size: 22,
                color: waiting ? AppColors.ivory : AppColors.petrol,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: waiting ? AppColors.ivory : AppColors.graphite,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      // O assunto é o que identifica a geração para quem a
                      // pediu; o nome do baralho ainda pode nem estar aqui.
                      job.topic ?? job.stage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: waiting
                            ? AppColors.ivory.withValues(alpha: .75)
                            : AppColors.sage,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 22,
                color: waiting ? AppColors.ivory : AppColors.sage,
              ),
            ],
          ),
        ),
      ),
    );
  }
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
        border: Border.all(color: AppColors.hairline),
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
                  backgroundColor: Colors.white,
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

  /// Nada vencendo e nada existindo são situações diferentes, e dizer a quem
  /// não tem card nenhum que a memória dele segue trabalhando é falso.
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
          border: Border.all(color: AppColors.hairline),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            const Text('Seu primeiro baralho',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            const Text(
              'Diga o que você quer aprender e a IA escreve os cards. '
              'Você aprova um por um.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.auto_awesome, size: 19),
              label: const Text('Criar com IA'),
            ),
          ],
        ),
      );
    }

    // §5.2 — com cards que existem e nada vencendo, o estado zerado é uma
    // mensagem de conclusão, não uma tela vazia e triste.
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
