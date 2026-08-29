import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:modes/modes.dart';

import '../../providers.dart';
import '../../providers_modes.dart';
import '../../theme.dart';
import 'counts_badge.dart';

/// Screen `28 Múltipla escolha` — §5.9.
///
/// The one alternative mode that writes to the log, so it says so at the top
/// and the grade it infers is never *fácil* (§5.2).
class MultipleChoiceScreen extends ConsumerStatefulWidget {
  const MultipleChoiceScreen({super.key, required this.queue});

  final List<String> queue;

  @override
  ConsumerState<MultipleChoiceScreen> createState() => _MultipleChoiceScreenState();
}

class _MultipleChoiceScreenState extends ConsumerState<MultipleChoiceScreen> {
  List<MultipleChoiceQuestion>? _questions;
  int _index = 0;
  int? _chosen;
  int _correct = 0;
  DateTime? _shownAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mode = await ref.read(multipleChoiceProvider.future);
    final built = await mode.build(widget.queue);
    if (!mounted) return;
    setState(() {
      _questions = built;
      _shownAt = ref.read(clockProvider)();
    });
  }

  Future<void> _choose(int index) async {
    final questions = _questions;
    if (questions == null || _chosen != null) return;

    final now = ref.read(clockProvider)();
    final question = questions[_index];
    final correct = index == question.answerIndex;
    setState(() {
      _chosen = index;
      if (correct) _correct++;
    });

    final mode = await ref.read(multipleChoiceProvider.future);
    await mode.answer(
      question: question,
      chosenIndex: index,
      elapsed: now.difference(_shownAt ?? now),
      at: now,
    );
    ref.invalidate(accumulatedMemoryProvider);
    ref.invalidate(studiedTodayProvider);
  }

  void _next() {
    setState(() {
      _index++;
      _chosen = null;
      _shownAt = ref.read(clockProvider)();
    });
  }

  @override
  Widget build(BuildContext context) {
    final questions = _questions;

    if (questions == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // §5.9 builds questions from other answers in the same deck; a deck too
    // small to supply distractors cannot produce an honest question.
    if (questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Múltipla escolha')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Este baralho ainda é pequeno demais para montar alternativas '
              'convincentes. Crie mais alguns cards e volte.',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.5, color: AppColors.muted),
            ),
          ),
        ),
      );
    }

    if (_index >= questions.length) {
      return _Summary(correct: _correct, total: questions.length);
    }

    final question = questions[_index];

    return Scaffold(
      appBar: AppBar(title: Text('${_index + 1} / ${questions.length}')),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: CountsBadge(counts: true),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                children: [
                  Text(
                    question.prompt,
                    style: const TextStyle(fontSize: 20, height: 1.35, color: AppColors.ink),
                  ),
                  const SizedBox(height: 28),
                  for (var i = 0; i < question.options.length; i++) ...[
                    _Option(
                      text: question.options[i],
                      state: _stateOf(i, question.answerIndex),
                      onTap: () => _choose(i),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
            if (_chosen != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _next,
                    child: Text(
                        _index + 1 >= questions.length ? 'Ver resultado' : 'Continuar'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  _OptionState _stateOf(int index, int answerIndex) {
    if (_chosen == null) return _OptionState.idle;
    if (index == answerIndex) return _OptionState.correct;
    if (index == _chosen) return _OptionState.wrong;
    return _OptionState.dimmed;
  }
}

enum _OptionState { idle, correct, wrong, dimmed }

class _Option extends StatelessWidget {
  const _Option({required this.text, required this.state, required this.onTap});

  final String text;
  final _OptionState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (border, fill, colour) = switch (state) {
      _OptionState.idle => (AppColors.hairline, Colors.white, AppColors.ink),
      _OptionState.correct => (AppColors.good, AppColors.goodBg, AppColors.good),
      _OptionState.wrong => (AppColors.again, AppColors.againBg, AppColors.again),
      _OptionState.dimmed => (AppColors.hairline, Colors.white, AppColors.faint),
    };

    return InkWell(
      onTap: state == _OptionState.idle ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: border, width: state == _OptionState.idle ? 1 : 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(text, style: TextStyle(fontSize: 15, height: 1.35, color: colour)),
      ),
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.correct, required this.total});

  final int correct;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memory = ref.watch(accumulatedMemoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Fim')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // §5.11 — memory leads, the count follows.
              Text(
                memory.valueOrNull?.label ?? '—',
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w500, color: AppColors.navy),
              ),
              const SizedBox(height: 6),
              const Text('de memória guardada',
                  style: TextStyle(fontSize: 13, color: AppColors.faint)),
              const SizedBox(height: 24),
              Text('$correct de $total certas',
                  style: const TextStyle(fontSize: 15, color: AppColors.muted)),
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
