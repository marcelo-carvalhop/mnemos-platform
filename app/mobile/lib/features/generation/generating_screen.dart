import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers_sync.dart';
import '../../theme.dart';
import 'approval_screen.dart';
import 'error_copy.dart';
import 'paywall_screen.dart';

/// A espera — §5.5.
///
/// O spike mediu de 10 a 24 segundos, então esta tela existe tempo suficiente
/// para importar. Duas decisões vêm daí:
///
/// * **Nomeia o estágio** em vez de animar uma barra que não sabe onde está.
///   O servidor manda o nome ("lendo o material", "escrevendo os cards"), o app
///   não inventa.
/// * **Diz que dá para sair.** Uma tela de progresso que prende alguém é o que
///   faz vinte segundos parecerem um minuto. O trabalho continua no servidor.
class GeneratingScreen extends ConsumerStatefulWidget {
  const GeneratingScreen({super.key, required this.jobId, required this.deckId});

  final String jobId;
  final String deckId;

  @override
  ConsumerState<GeneratingScreen> createState() => _GeneratingScreenState();
}

class _GeneratingScreenState extends ConsumerState<GeneratingScreen>
    with SingleTickerProviderStateMixin {
  static const _stages = ['queued', 'reading', 'generating', 'ready'];

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

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
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _tick() async {
    if (!mounted) return;
    _attempts++;

    try {
      final job = await ref.read(generationApiProvider).get(widget.jobId);
      if (!mounted) return;
      final changed = job.status != _job?.status;
      setState(() => _job = job);
      if (changed) HapticFeedback.selectionClick();

      if (job.isReady) {
        _poll?.cancel();
        HapticFeedback.mediumImpact();
        await Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ApprovalScreen(jobId: job.id, deckId: widget.deckId),
        ));
      } else if (job.isFinished) {
        _poll?.cancel();
        setState(() => _failure = GenerationFailure.forCode(job.errorCode));
      }
    } on Offline {
      // O trabalho roda no servidor, com ou sem este telefone olhando. Perder
      // a rede aqui não perde nada, então não vira erro antes de insistir.
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
    final reached = _stages.indexOf(status).clamp(0, _stages.length - 1);

    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: FadeTransition(
                  opacity: Tween(begin: .35, end: 1.0).animate(
                    CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      size: 34, color: AppColors.petrol),
                ),
              ),
              const SizedBox(height: 26),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, .25),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  // §5.5 — o servidor nomeia o estágio.
                  _job?.stage ?? 'na fila',
                  key: ValueKey(status),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w600,
                    color: AppColors.graphite,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Costuma levar de 10 a 30 segundos.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: AppColors.sage),
              ),
              const SizedBox(height: 36),
              _Steps(reached: reached),
              const Spacer(),
              const Text(
                'Pode sair desta tela — o trabalho continua no servidor e os '
                'cards esperam sua aprovação.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.sage),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  side: const BorderSide(color: AppColors.mist),
                  foregroundColor: AppColors.petrol,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Continuar em segundo plano'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Três marcos com a linha entre eles preenchendo conforme o estágio avança.
class _Steps extends StatelessWidget {
  const _Steps({required this.reached});

  final int reached;

  static const _labels = ['Lendo', 'Escrevendo', 'Pronto'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 3; i++) ...[
          _Dot(
            label: _labels[i],
            done: reached > i + 1,
            active: reached == i + 1 || (i == 0 && reached <= 1),
          ),
          if (i < 2)
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: reached > i + 1 ? 1 : 0),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOut,
                builder: (context, value, _) => Container(
                  height: 1.5,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: AppColors.mist,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: value,
                    child: Container(color: AppColors.petrol),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.label, required this.done, required this.active});

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 18,
          width: 18,
          child: done
              ? const Icon(Icons.check_circle, size: 18, color: AppColors.petrol)
              : active
                  ? const CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.petrol)
                  : Container(
                      margin: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.mist,
                      ),
                    ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: done || active ? AppColors.graphite : AppColors.sage,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

/// §10 — a copy vem do código, nunca da prosa do servidor, e diz em voz alta
/// se a geração foi gasta. Com uma por vida, é a primeira coisa que se quer
/// saber.
class _Failed extends ConsumerWidget {
  const _Failed({required this.failure});

  final GenerationFailure failure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                failure.showsPaywall ? Icons.lock_outline : Icons.error_outline,
                size: 32,
                color: failure.showsPaywall ? AppColors.petrol : AppColors.brass,
              ),
              const SizedBox(height: 22),
              Text(
                failure.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                  color: AppColors.graphite,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                failure.detail,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.sage),
              ),
              const Spacer(),
              if (failure.showsPaywall)
                FilledButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const PaywallScreen()),
                  ),
                  child: const Text('Ver a assinatura'),
                )
              else
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(failure.canRetry ? 'Tentar de novo' : 'Voltar'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
