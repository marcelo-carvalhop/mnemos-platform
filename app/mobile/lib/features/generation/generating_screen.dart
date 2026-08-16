import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers_sync.dart';
import '../../theme.dart';
import 'approval_screen.dart';
import 'error_copy.dart';
import 'paywall_screen.dart';

/// Screen `19 Gerando` — §5.5.
///
/// The spike measured 10 to 24 seconds, so this screen exists for long enough
/// to matter. Two decisions follow from that: it names the stage instead of
/// animating a bar that has no idea how far along it is, and it says the
/// session can be left — because a progress screen that traps someone is what
/// makes twenty seconds feel like a minute.
class GeneratingScreen extends ConsumerStatefulWidget {
  const GeneratingScreen({super.key, required this.jobId, required this.deckId});

  final String jobId;
  final String deckId;

  @override
  ConsumerState<GeneratingScreen> createState() => _GeneratingScreenState();
}

class _GeneratingScreenState extends ConsumerState<GeneratingScreen> {
  static const _stages = ['queued', 'reading', 'generating', 'ready'];

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
      // The job is running on the server whether or not this phone can see it.
      // Losing the network here loses nothing, so it is not reported until it
      // has been failing for a while.
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
    final stageIndex = _stages.indexOf(status).clamp(0, _stages.length - 1);

    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                // §5.5 — the server names the stage; the app does not invent
                // copy from a status it might not recognise.
                _job?.stage ?? 'na fila',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w500, color: AppColors.ink),
              ),
              const SizedBox(height: 12),
              const Text(
                'Costuma levar de 10 a 30 segundos.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 6),
              const Text(
                'Pode sair desta tela — o trabalho continua no servidor.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.faint),
              ),
              const SizedBox(height: 36),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    _Step(
                      label: const ['Lendo', 'Gerando', 'Pronto'][i],
                      done: stageIndex > i + 0,
                      active: stageIndex == i + 1 || (i == 0 && stageIndex <= 1),
                    ),
                    if (i < 2)
                      Container(
                        width: 26,
                        height: 1.5,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        color: AppColors.hairline,
                      ),
                  ],
                ],
              ),
              const SizedBox(height: 40),
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

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.done, required this.active});

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colour = done || active ? AppColors.navy : AppColors.faint;

    return Column(
      children: [
        SizedBox(
          height: 16,
          width: 16,
          child: done
              ? const Icon(Icons.check_circle, size: 16, color: AppColors.navy)
              : active
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.hairline,
                      ),
                    ),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 11, color: colour)),
      ],
    );
  }
}

/// Screen `23 Estados de erro` — §10.
///
/// The copy comes from the code, never from the server's prose, and it says
/// out loud whether the generation was spent. With one per lifetime, that is
/// the first thing anyone wants to know.
class _Failed extends ConsumerWidget {
  const _Failed({required this.failure});

  final GenerationFailure failure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.error_outline, size: 34, color: AppColors.hard),
              const SizedBox(height: 20),
              Text(
                failure.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w500, color: AppColors.ink),
              ),
              const SizedBox(height: 12),
              Text(
                failure.detail,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.muted),
              ),
              const SizedBox(height: 32),
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
