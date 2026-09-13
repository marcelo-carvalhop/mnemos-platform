import 'dart:async';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../providers_sync.dart';
import '../theme/tokens.dart';

/// Screens `04 Card frente`, `05 Card verso` and `26 Card verso corrigido`.
///
/// The four grade buttons each show the interval they would produce (§5.8.3),
/// read from the scheduler rather than guessed — the canvas shipped without
/// them, and the spec calls that what separates a serious app from a toy.
class StudyScreen extends ConsumerStatefulWidget {
  const StudyScreen({super.key, required this.queue});

  final List<String> queue;

  @override
  ConsumerState<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends ConsumerState<StudyScreen> {
  int _index = 0;
  bool _revealed = false;

  String? get _cardId => _index < widget.queue.length ? widget.queue[_index] : null;

  Future<void> _answer(Grade grade) async {
    final cardId = _cardId;
    if (cardId == null) return;

    final study = await ref.read(studyServiceProvider.future);
    // Written on the spot: leaving mid-session must preserve what was already
    // reviewed (§5.8).
    await study.recordReview(
      cardId: cardId,
      grade: grade,
      at: ref.read(clockProvider)(),
    );

    ref.invalidate(accumulatedMemoryProvider);
    ref.invalidate(studiedTodayProvider);
    // The count only; the push waits for the end of the session, because
    // a request per card would be a request per card.
    unawaited(ref.read(syncControllerProvider.notifier).refreshPending());

    if (!mounted) return;
    final finished = _index + 1 >= widget.queue.length;
    setState(() {
      _index++;
      _revealed = false;
    });
    if (finished) {
      // §5.2 — with the queue empty, Hoje must show the completion state
      // rather than a button offering four cards that are no longer due.
      ref.invalidate(queueProvider);
      // §11.5 — rescheduled from what is actually left, so an empty queue
      // cancels the reminder instead of nagging about nothing.
      unawaited(refreshReminder(ref));
      unawaited(ref.read(syncControllerProvider.notifier).syncNow());
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardId = _cardId;
    if (cardId == null) return const _SessionSummary();

    final card = ref.watch(cardProvider(cardId));

    return Scaffold(
      appBar: AppBar(
        title: Text('${_index + 1} / ${widget.queue.length}'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(
              value: (_index + 1) / widget.queue.length,
              minHeight: 3,
              backgroundColor: MnemosColors.hairline,
              valueColor: const AlwaysStoppedAnimation(MnemosColors.primary),
            ),
            Expanded(
              child: card.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
                data: (row) => row == null
                    ? const Center(child: Text('Card não encontrado'))
                    : _CardFace(
                        front: row.front,
                        back: row.back,
                        revealed: _revealed,
                        onReveal: () => setState(() => _revealed = true),
                      ),
              ),
            ),
            if (_revealed) _GradeBar(cardId: cardId, onGrade: _answer),
          ],
        ),
      ),
    );
  }
}

class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.front,
    required this.back,
    required this.revealed,
    required this.onReveal,
  });

  final String front;
  final String back;
  final bool revealed;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: revealed ? null : onReveal,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              front,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, height: 1.35, color: MnemosColors.ink),
            ),
            if (revealed) ...[
              const SizedBox(height: 28),
              const SizedBox(
                width: 40,
                child: Divider(color: MnemosColors.hairline, thickness: 1.5),
              ),
              const SizedBox(height: 28),
              Text(
                back,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, height: 1.5, color: MnemosColors.muted),
              ),
            ] else ...[
              const SizedBox(height: 40),
              const Text('Toque para revelar',
                  style: TextStyle(fontSize: 13, color: MnemosColors.faint)),
            ],
          ],
        ),
      ),
    );
  }
}

/// The four grades, each labelled with the interval it produces.
class _GradeBar extends ConsumerWidget {
  const _GradeBar({required this.cardId, required this.onGrade});

  final String cardId;
  final void Function(Grade) onGrade;

  static const _labels = {
    Grade.again: ('Errei', MnemosColors.again, MnemosColors.againSurface),
    Grade.hard: ('Difícil', MnemosColors.hard, MnemosColors.hardSurface),
    Grade.good: ('Bom', MnemosColors.good, MnemosColors.goodSurface),
    Grade.easy: ('Fácil', MnemosColors.easy, MnemosColors.easySurface),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(previewProvider(cardId));

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
      child: Column(
        children: [
          const Text('Como você lembrou?',
              style: TextStyle(fontSize: 13, color: MnemosColors.faint)),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final grade in Grade.values) ...[
                Expanded(
                  child: _GradeButton(
                    label: _labels[grade]!.$1,
                    colour: _labels[grade]!.$2,
                    background: _labels[grade]!.$3,
                    interval: preview.valueOrNull?[grade],
                    onTap: () => onGrade(grade),
                  ),
                ),
                if (grade != Grade.easy) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _GradeButton extends StatelessWidget {
  const _GradeButton({
    required this.label,
    required this.colour,
    required this.background,
    required this.interval,
    required this.onTap,
  });

  final String label;
  final Color colour;
  final Color background;
  final Duration? interval;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(label,
                style: TextStyle(fontSize: 13, color: colour, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(
              interval == null ? '—' : formatInterval(interval!),
              style: TextStyle(fontSize: 12, color: colour.withValues(alpha: .85)),
            ),
          ],
        ),
      ),
    );
  }
}

/// "10 min", "3 dias", "2 semanas", "1 mês" — the labels the canvas shows.
String formatInterval(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  if (d.inHours < 24) return '${d.inHours} h';
  if (d.inDays < 14) return '${d.inDays} ${d.inDays == 1 ? "dia" : "dias"}';
  if (d.inDays < 60) {
    final weeks = (d.inDays / 7).round();
    return '$weeks ${weeks == 1 ? "semana" : "semanas"}';
  }
  if (d.inDays < 365) {
    final months = (d.inDays / 30.44).round();
    return '$months ${months == 1 ? "mês" : "meses"}';
  }
  final years = (d.inDays / 365).round();
  return '$years ${years == 1 ? "ano" : "anos"}';
}

class _SessionSummary extends ConsumerWidget {
  const _SessionSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memory = ref.watch(accumulatedMemoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Sessão concluída')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.landscape_outlined, size: 48, color: MnemosColors.primary),
              const SizedBox(height: 20),
              const Text('Um pouco mais alto',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              // §5.11 — the summary leads with memory, never with a card count.
              Text(
                memory.valueOrNull?.label ?? '—',
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w500, color: MnemosColors.primary),
              ),
              const SizedBox(height: 6),
              const Text('de memória guardada',
                  style: TextStyle(fontSize: 13, color: MnemosColors.faint)),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Voltar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
