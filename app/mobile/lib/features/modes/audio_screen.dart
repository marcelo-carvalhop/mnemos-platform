import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:modes/modes.dart';

import '../../providers_modes.dart';
import '../../theme.dart';
import 'counts_badge.dart';

/// Screen `33 Áudio` — §5.9, §11.6.
///
/// The playlist comes from `modes`, which is testable in plain Dart; this
/// screen only speaks it. On-device and offline: nothing about what the user
/// is studying goes anywhere.
///
/// No grade buttons — the user has headphones in and their hands elsewhere —
/// and therefore no review row.
class AudioScreen extends ConsumerStatefulWidget {
  const AudioScreen({super.key, required this.queue});

  final List<String> queue;

  @override
  ConsumerState<AudioScreen> createState() => _AudioScreenState();
}

class _AudioScreenState extends ConsumerState<AudioScreen> {
  final _tts = FlutterTts();
  List<AudioStep>? _steps;
  int _index = 0;
  bool _playing = false;
  Timer? _pauseTimer;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    // Brazilian Portuguese, since every card is written in it (§1).
    await _tts.setLanguage('pt-BR');
    await _tts.setSpeechRate(.45);
    await _tts.awaitSpeakCompletion(true);

    final steps = await ref.read(audioSessionProvider).build(widget.queue);
    if (!mounted) return;
    setState(() => _steps = steps);
  }

  @override
  void dispose() {
    _pauseTimer?.cancel();
    _tts.stop();
    super.dispose();
  }

  Future<void> _play() async {
    setState(() => _playing = true);
    final steps = _steps ?? const [];

    while (mounted && _playing && _index < steps.length) {
      final step = steps[_index];
      switch (step) {
        case Speak(:final text):
          await _tts.speak(text);
        case Pause(:final duration):
          final completer = Completer<void>();
          _pauseTimer = Timer(duration, completer.complete);
          await completer.future;
      }
      if (!mounted || !_playing) return;
      setState(() => _index++);
    }

    if (mounted) setState(() => _playing = false);
  }

  Future<void> _stop() async {
    _pauseTimer?.cancel();
    setState(() => _playing = false);
    await _tts.stop();
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    if (steps == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final current = _index < steps.length ? steps[_index] : null;
    final speaking = current is Speak ? current : null;
    final done = _index >= steps.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Áudio')),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: CountsBadge(counts: false, expanded: true),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (done)
                        const Text('Fim da sessão',
                            style: TextStyle(fontSize: 20, color: AppColors.muted))
                      else ...[
                        Text(
                          speaking == null
                              ? '…'
                              : speaking.isFront
                                  ? 'pergunta'
                                  : 'resposta',
                          style: const TextStyle(fontSize: 12, color: AppColors.faint),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          speaking?.text ?? 'pensando…',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            height: 1.4,
                            color: speaking == null ? AppColors.faint : AppColors.ink,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filled(
                    iconSize: 34,
                    padding: const EdgeInsets.all(18),
                    onPressed: done
                        ? null
                        : _playing
                            ? _stop
                            : _play,
                    icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
