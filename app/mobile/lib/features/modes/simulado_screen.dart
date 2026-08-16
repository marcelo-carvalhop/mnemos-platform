import 'dart:async';

import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:modes/modes.dart';

import '../../providers.dart';
import '../../providers_modes.dart';
import '../../theme.dart';
import 'counts_badge.dart';

/// Screen `30 Simulado — preparar` — §5.9.
class SimuladoSetupScreen extends ConsumerStatefulWidget {
  const SimuladoSetupScreen({super.key});

  @override
  ConsumerState<SimuladoSetupScreen> createState() => _SimuladoSetupScreenState();
}

class _SimuladoSetupScreenState extends ConsumerState<SimuladoSetupScreen> {
  String? _deckId;
  int _questions = kSimuladoDefaultQuestions;
  int _minutes = kSimuladoDefaultMinutes;

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Simulado')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const CountsBadge(counts: false, expanded: true),
          const SizedBox(height: 24),
          const Text('Baralho', style: TextStyle(fontSize: 12, color: AppColors.faint)),
          const SizedBox(height: 8),
          decks.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
            data: (rows) => DropdownButtonFormField<String?>(
              value: _deckId,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos')),
                for (final d in rows)
                  DropdownMenuItem(value: d.id, child: Text(d.name)),
              ],
              onChanged: (v) => setState(() => _deckId = v),
            ),
          ),
          const SizedBox(height: 24),
          _Stepper(
            label: 'Questões',
            value: _questions,
            min: 5,
            max: 60,
            step: 5,
            onChanged: (v) => setState(() => _questions = v),
          ),
          const SizedBox(height: 18),
          _Stepper(
            label: 'Minutos',
            value: _minutes,
            min: 5,
            max: 120,
            step: 5,
            onChanged: (v) => setState(() => _minutes = v),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () async {
              final paper = await ref.read(simuladoProvider).build(
                    deckId: _deckId,
                    questions: _questions,
                    timeLimit: Duration(minutes: _minutes),
                  );
              if (!context.mounted) return;
              if (paper.questions.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Não há cards suficientes para montar a prova.')));
                return;
              }
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => SimuladoRunScreen(paper: paper)),
              );
            },
            child: const Text('Começar'),
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
        IconButton(
          onPressed: value > min ? () => onChanged(value - step) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 42,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        ),
        IconButton(
          onPressed: value < max ? () => onChanged(value + step) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

/// Screen `31 Simulado — prova` — §5.9.
///
/// Exam format: no feedback during. The card's back is never shown here, and
/// the user marks themselves only at the end.
class SimuladoRunScreen extends ConsumerStatefulWidget {
  const SimuladoRunScreen({super.key, required this.paper});

  final Simulado paper;

  @override
  ConsumerState<SimuladoRunScreen> createState() => _SimuladoRunScreenState();
}

class _SimuladoRunScreenState extends ConsumerState<SimuladoRunScreen> {
  late final DateTime _startedAt = ref.read(clockProvider)();
  Timer? _ticker;
  int _index = 0;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final elapsed = ref.read(clockProvider)().difference(_startedAt);
      setState(() => _elapsed = elapsed);
      if (widget.paper.remaining(elapsed) == Duration.zero) _finish();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _finish() {
    _ticker?.cancel();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => SimuladoMarkScreen(
        paper: widget.paper,
        // Questions never reached are not wrong (§5.9) — running out of time
        // says nothing about whether they were known.
        reached: _index,
        elapsed: _elapsed,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.paper.remaining(_elapsed);
    final question = widget.paper.questions[_index];
    final low = remaining.inSeconds <= 60;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('${_index + 1} / ${widget.paper.questions.length}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                _clock(remaining),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: low ? AppColors.again : AppColors.navy,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    question.prompt,
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(fontSize: 21, height: 1.4, color: AppColors.ink),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                'Responda de cabeça. As respostas aparecem só no fim.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.faint),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (_index + 1 >= widget.paper.questions.length) {
                      setState(() => _index++);
                      _finish();
                    } else {
                      setState(() => _index++);
                    }
                  },
                  child: Text(_index + 1 >= widget.paper.questions.length
                      ? 'Entregar'
                      : 'Próxima'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _clock(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:'
      '${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

/// Screen `32 Simulado — correção` — §5.9.
///
/// Self-marked: the app cannot judge free text against the back of a card.
/// Nothing marked here is written to the review log.
class SimuladoMarkScreen extends ConsumerStatefulWidget {
  const SimuladoMarkScreen({
    super.key,
    required this.paper,
    required this.reached,
    required this.elapsed,
  });

  final Simulado paper;
  final int reached;
  final Duration elapsed;

  @override
  ConsumerState<SimuladoMarkScreen> createState() => _SimuladoMarkScreenState();
}

class _SimuladoMarkScreenState extends ConsumerState<SimuladoMarkScreen> {
  final _correct = <String>{};
  final _wrong = <String>{};

  @override
  Widget build(BuildContext context) {
    final seen = widget.paper.questions.take(widget.reached).toList();
    final result = ref.read(simuladoProvider).score(
          widget.paper,
          correctCardIds: _correct,
          wrongCardIds: _wrong,
          elapsed: widget.elapsed,
        );
    final marked = _correct.length + _wrong.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Correção'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const CountsBadge(counts: false, expanded: true),
          const SizedBox(height: 20),
          if (marked == seen.length && seen.isNotEmpty) ...[
            Text(
              '${(result.score * 100).round()}%',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 34, fontWeight: FontWeight.w500, color: AppColors.navy),
            ),
            Text(
              '${result.correctCardIds.length} de ${result.answered} certas'
              '${result.unanswered.isEmpty ? "" : " · ${result.unanswered.length} não respondidas"}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.faint),
            ),
            const SizedBox(height: 20),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Marque o que você acertou. $marked de ${seen.length}.',
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ),
          for (final q in seen) ...[
            _MarkTile(
              prompt: q.prompt,
              expected: q.expected,
              value: _correct.contains(q.cardId)
                  ? true
                  : _wrong.contains(q.cardId)
                      ? false
                      : null,
              onMark: (right) => setState(() {
                _correct.remove(q.cardId);
                _wrong.remove(q.cardId);
                (right ? _correct : _wrong).add(q.cardId);
              }),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Terminar'),
          ),
        ],
      ),
    );
  }
}

class _MarkTile extends StatelessWidget {
  const _MarkTile({
    required this.prompt,
    required this.expected,
    required this.value,
    required this.onMark,
  });

  final String prompt;
  final String expected;
  final bool? value;
  final ValueChanged<bool> onMark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.hairline),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(prompt, style: const TextStyle(fontSize: 15, height: 1.35)),
          const SizedBox(height: 8),
          Text(expected,
              style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MarkButton(
                  label: 'Errei',
                  colour: AppColors.again,
                  background: AppColors.againBg,
                  selected: value == false,
                  onTap: () => onMark(false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MarkButton(
                  label: 'Acertei',
                  colour: AppColors.good,
                  background: AppColors.goodBg,
                  selected: value == true,
                  onTap: () => onMark(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MarkButton extends StatelessWidget {
  const _MarkButton({
    required this.label,
    required this.colour,
    required this.background,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color colour;
  final Color background;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? background : AppColors.ivory,
          border: Border.all(color: selected ? colour : AppColors.hairline),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                color: selected ? colour : AppColors.muted,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
  }
}
