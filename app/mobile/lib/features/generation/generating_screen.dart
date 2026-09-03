import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers_sync.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../ui/ui.dart';
import 'approval_screen.dart';
import 'error_copy.dart';
import 'paywall_screen.dart';

/// A espera — artboard 05.
///
/// §5.5 — quatro etapas visíveis o tempo todo, não só a atual. Quem espera
/// quer saber quanto falta, e uma etapa futura à vista é essa resposta; a
/// versão anterior mostrava três bolinhas e nenhuma noção de progresso dentro
/// da etapa em curso.
class GeneratingScreen extends ConsumerStatefulWidget {
  const GeneratingScreen({
    super.key,
    required this.jobId,
    required this.deckId,
    this.topic,
  });

  final String jobId;
  final String deckId;

  /// O que foi pedido, quando a tela sabe. O design mostra o assunto em
  /// destaque: é o que dá sentido à espera.
  final String? topic;

  @override
  ConsumerState<GeneratingScreen> createState() => _GeneratingScreenState();
}

class _GeneratingScreenState extends ConsumerState<GeneratingScreen> {
  static const _statuses = ['queued', 'reading', 'generating', 'ready'];

  /// As quatro etapas como o design as nomeia. São quatro para os quatro
  /// estados que o servidor reporta — a lista não inventa uma etapa a mais do
  /// que o backend sabe distinguir.
  static const _steps = [
    'Material interpretado',
    'Conceitos separados',
    'Escrevendo perguntas',
    'Revisando duplicatas',
  ];

  Timer? _poll;
  GenerationJob? _job;
  GenerationFailure? _failure;
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
    _tick();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    if (!mounted) return;
    _attempts++;

    try {
      final job = await ref.read(generationApiProvider).get(widget.jobId);
      if (!mounted) return;
      setState(() => _job = job);

      if (job.isReady) {
        _poll?.cancel();
        await Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ApprovalScreen(jobId: job.id, deckId: widget.deckId),
        ));
      } else if (job.isFinished) {
        _poll?.cancel();
        setState(() => _failure = GenerationFailure.forCode(job.errorCode));
      }
    } on Offline {
      // O trabalho roda no servidor com ou sem este telefone à vista. Perder a
      // rede aqui não perde nada, então só vira erro depois de insistir.
      if (_attempts > 15 && mounted) {
        setState(() => _failure = GenerationFailure.forCode('network_unavailable'));
      }
    } on Object catch (e) {
      if (!mounted) return;
      _poll?.cancel();
      setState(() => _failure = GenerationFailure.forException(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    if (failure != null) return _Failed(failure: failure);

    final status = _job?.status ?? 'queued';
    final index = _statuses.indexOf(status).clamp(0, _statuses.length - 1);
    final progress = (index + 1) / (_statuses.length + 1);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            MnemosSpacing.screen,
            MnemosSpacing.sm,
            MnemosSpacing.screen,
            MnemosSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: MnemosColors.muted),
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                tooltip: 'Continuar em segundo plano',
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // §5.5 — o servidor nomeia a etapa; o app não inventa
                    // texto a partir de um status que talvez não reconheça.
                    Eyebrow('gerando · ${_job?.stage ?? 'na fila'}'),
                    const SizedBox(height: MnemosSpacing.md),
                    Text(
                      widget.topic ?? 'Escrevendo os seus cards',
                      style: MnemosText.screenTitleWrapped,
                    ),
                    const SizedBox(height: MnemosSpacing.xxl),
                    MeterBar(fraction: progress, height: 8, track: MnemosColors.line),
                    const SizedBox(height: MnemosSpacing.xxl),
                    for (final (i, label) in _steps.indexed) ...[
                      if (i > 0) const SizedBox(height: MnemosSpacing.lg),
                      StepRow(
                        label: label,
                        state: switch (i.compareTo(index)) {
                          < 0 => MnemosStepState.done,
                          0 => MnemosStepState.active,
                          _ => MnemosStepState.pending,
                        },
                        detail: i == index && (_job?.cardCount ?? 0) > 0
                            ? '${_job!.cardCount}'
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
              const SurfaceCard(
                radius: MnemosRadii.card,
                child: Text(
                  'Pode fechar o app. Avisamos quando os cards estiverem prontos '
                  'para revisão.',
                  style: MnemosText.bodySmall,
                ),
              ),
              const SizedBox(height: MnemosSpacing.lg),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Continuar em segundo plano'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A geração falhou — §10.
///
/// A cópia vem do código, nunca da prosa do servidor, e diz em voz alta se a
/// geração foi gasta. Com uma por conta, é a primeira coisa que se quer saber.
class _Failed extends StatelessWidget {
  const _Failed({required this.failure});

  final GenerationFailure failure;

  @override
  Widget build(BuildContext context) {
    // Um erro sem nenhum sinal cromático é indistinguível de qualquer outra
    // tela do app: antes eram título preto e botão lavanda sobre o mesmo fundo
    // de sempre, sem ícone e sem cor. Tirando o texto, esta tela era igual à de
    // conectar o terminal. Nas falhas do iOS há sempre um glifo de estado
    // acima do título.
    final paywall = failure.showsPaywall;
    return Scaffold(
      body: SafeArea(
        child: StatusScreen(
          icon: paywall
              ? Icons.lock_outline
              : Icons.error_outline,
          tone: paywall ? StatusTone.neutral : StatusTone.problem,
          eyebrow: 'não deu certo',
          title: failure.title,
          message: failure.detail,
          action: (paywall || failure.canRetry)
              ? () {
                  if (paywall) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const PaywallScreen()),
                    );
                  } else {
                    Navigator.of(context).pop();
                  }
                }
              : null,
          actionLabel: paywall ? 'Ver a assinatura' : 'Tentar de novo',
          secondary: () => Navigator.of(context).pop(),
          secondaryLabel: 'Voltar',
        ),
      ),
    );
  }
}
