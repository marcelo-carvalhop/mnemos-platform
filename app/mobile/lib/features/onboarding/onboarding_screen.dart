import 'package:authoring/authoring.dart';
import 'package:domain/domain.dart';
import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:store/store.dart';

import '../../providers.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../ui/ui.dart';
import '../create/create_screen.dart';

/// Screens `13`–`16` — §5.1.
///
/// Four steps, and the fourth is the one that matters commercially. §7.7.1
/// makes the free tier one generation for the lifetime of the account, so an
/// onboarding that quietly spends it has taken something the user did not know
/// they had. It says what it costs, and **"guardar para depois" is a real
/// choice**, not a dark-pattern decline — the app is fully usable without ever
/// generating anything.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  final _subject = TextEditingController();
  int _page = 0;
  int _goal = 25;
  bool _finishing = false;

  static const _suggestions = [
    'Redes de Computadores',
    'TCP/IP',
    'Roteamento',
    'Segurança de Redes',
    'Sistemas Distribuídos',
    'Protocolos',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _subject.dispose();
    super.dispose();
  }

  void _next() {
    _controller.nextPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  /// Writes what the four steps collected, then hands over.
  ///
  /// A deck and a goal, nothing else. Onboarding is not the place to invent
  /// content: §5.1's empty state is a screen, and an app that starts with four
  /// cards someone else wrote is an app that starts with a lie.
  Future<String> _commit() async {
    final db = ref.read(databaseProvider);
    final now = ref.read(clockProvider)();
    final deviceId = await ref.read(deviceIdProvider.future);

    final name = _subject.text.trim().isEmpty ? 'Meu primeiro baralho' : _subject.text.trim();
    final deckId = await AuthoringService(db, deviceId: deviceId).createDeck(
      name: name,
      at: now,
    );

    await db.into(db.goalHistory).insert(
          GoalHistoryCompanion.insert(
            id: Uuid7.generate(now: now),
            effectiveFromLocalDate:
                const DayBucket(timezoneName: 'America/Sao_Paulo').today(now),
            dailyGoal: _goal,
            createdAt: now.millisecondsSinceEpoch,
            deviceId: deviceId,
          ),
        );

    await db.into(db.userSettings).insert(
          UserSettingsCompanion.insert(
            key: 'timezone',
            value: 'America/Sao_Paulo',
            updatedAt: now.millisecondsSinceEpoch,
            deviceId: deviceId,
            serverSeq: const Value.absent(),
          ),
          mode: InsertMode.insertOrReplace,
        );

    await markOnboardingDone(db);
    ref.invalidate(decksProvider);
    ref.invalidate(dailyGoalProvider);
    return deckId;
  }

  Future<void> _finish({required bool generate}) async {
    setState(() => _finishing = true);
    final deckId = await _commit();
    if (!mounted) return;

    widget.onDone();
    if (generate) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CreateScreen(deckId: deckId),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                children: [
                  for (var i = 0; i < 4; i++)
                    Expanded(
                      child: Container(
                        height: 3,
                        margin: EdgeInsets.only(right: i == 3 ? 0 : 6),
                        decoration: ShapeDecoration(
        color: i <= _page ? MnemosColors.primary : MnemosColors.hairline,
        shape: squircle(2),
      ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _Welcome(onNext: _next),
                  _Subject(
                    controller: _subject,
                    suggestions: _suggestions,
                    onPick: (s) => setState(() => _subject.text = s),
                    onNext: _next,
                  ),
                  _Goal(
                    value: _goal,
                    onChanged: (v) => setState(() => _goal = v),
                    onNext: _next,
                  ),
                  _FreeGeneration(
                    subject: _subject.text.trim(),
                    busy: _finishing,
                    onGenerate: () => _finish(generate: true),
                    onSkip: () => _finish(generate: false),
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

// ---------------------------------------------------------------------------
// 13 — boas-vindas
// ---------------------------------------------------------------------------

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _Page(
      children: [
        const Spacer(),
        const Eyebrow('mnemos'),
        const SizedBox(height: MnemosSpacing.lg),
        const Text(
          'Estude menos.\nLembre por\nanos.',
          style: MnemosText.display,
        ),
        const SizedBox(height: MnemosSpacing.xl),
        Text(
          'Cards curtos, revisados na hora certa. Estude aqui pelo app, '
          'ou no terminal Mnemos quando quiser ler sem distrações.',
          style: MnemosText.bodyLong.copyWith(fontSize: 16, color: MnemosColors.muted),
        ),
        const SizedBox(height: MnemosSpacing.xl),
        const _TerminalTeaser(),
        const Spacer(),
        FilledButton(onPressed: onNext, child: const Text('Começar')),
        const SizedBox(height: MnemosSpacing.md),
        TextButton(
          onPressed: onNext,
          child: const Text('Já tenho conta'),
        ),
      ],
    );
  }
}

/// O desenho do T5 ao lado da frase que explica o que ele é.
///
/// O aparelho é a parte do produto que ninguém adivinha por um ícone: mostrar
/// um card na tela dele diz em dois segundos o que um parágrafo não diria.
class _TerminalTeaser extends StatelessWidget {
  const _TerminalTeaser();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 96,
          height: 132,
          padding: const EdgeInsets.all(MnemosSpacing.md),
          decoration: ShapeDecoration(
        color: MnemosColors.raised,
        shape: squircle(10, side: BorderSide(color: MnemosColors.line)),
      ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'T5',
                style: MnemosText.eyebrowSmall.copyWith(
                  fontSize: 9,
                  color: MnemosColors.fainter,
                ),
              ),
              Text(
                'O que o TCP garante?',
                style: MnemosText.cardTitle.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  height: 1.3,
                ),
              ),
              Text(
                '3/12',
                style: MnemosText.monoSmall.copyWith(
                  fontSize: 9,
                  color: MnemosColors.fainter,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: MnemosSpacing.lg),
        Expanded(
          child: Text(
            'Um aparelho de tinta eletrônica que só faz uma coisa: te perguntar '
            'a coisa certa na hora certa.',
            style: MnemosText.bodySmall.copyWith(fontSize: 13.5, height: 1.6),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 14 — o que estudar
// ---------------------------------------------------------------------------

class _Subject extends StatelessWidget {
  const _Subject({
    required this.controller,
    required this.suggestions,
    required this.onPick,
    required this.onNext,
  });

  final TextEditingController controller;
  final List<String> suggestions;
  final ValueChanged<String> onPick;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _Page(
      children: [
        const SizedBox(height: 30),
        const Text('O que você quer estudar?',
            style: MnemosText.screenTitleWrapped),
        const SizedBox(height: 10),
        Text(
          'Pode ser uma matéria ou um assunto específico que você queira memorizar.',
          style: MnemosText.bodyLong.copyWith(fontSize: 15, color: MnemosColors.muted),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Ex.: Redes de Computadores',
            hintStyle: TextStyle(fontSize: 13.5, color: MnemosColors.faint),
          ),
        ),
        const SizedBox(height: 20),
        const Eyebrow('sugestões'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in suggestions)
              ActionChip(
                label: Text(s),
                onPressed: () => onPick(s),
                backgroundColor: MnemosColors.raised,
                side: BorderSide.none,
              ),
          ],
        ),
        const Spacer(),
        // Deliberately not required: someone who does not know yet should not
        // be blocked at step two of an app they have not seen.
        FilledButton(onPressed: onNext, child: const Text('Continuar')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 15 — meta diária
// ---------------------------------------------------------------------------

class _Goal extends StatelessWidget {
  const _Goal({required this.value, required this.onChanged, required this.onNext});

  final int value;
  final ValueChanged<int> onChanged;
  final VoidCallback onNext;

  /// The minute estimates come from §9's own arithmetic — roughly 30 seconds a
  /// card — rather than from optimism.
  static const _options = [
    (10, 'Leve', '10 cards · cerca de 5 min'),
    (25, 'Médio', '25 cards · cerca de 12 min'),
    (50, 'Intenso', '50 cards · cerca de 25 min'),
  ];

  @override
  Widget build(BuildContext context) {
    return _Page(
      children: [
        const SizedBox(height: 30),
        const Text('Quanto por dia?',
            style: MnemosText.screenTitleWrapped),
        const SizedBox(height: 10),
        Text('Dá para mudar depois, a qualquer momento.',
            style: MnemosText.bodyLong.copyWith(fontSize: 15, color: MnemosColors.muted)),
        const SizedBox(height: 26),
        for (final (goal, title, detail) in _options) ...[
          _Option(
            title: title,
            detail: detail,
            selected: value == goal,
            onTap: () => onChanged(goal),
          ),
          const SizedBox(height: 10),
        ],
        const Spacer(),
        FilledButton(onPressed: onNext, child: const Text('Continuar')),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: squircle(MnemosRadii.control),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? MnemosColors.raised : MnemosColors.canvas,
          border: Border.all(
            color: selected ? MnemosColors.primary : MnemosColors.hairline,
            width: selected ? 1.6 : 1,
          ),
          borderRadius: BorderRadius.circular(MnemosRadii.control),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: MnemosText.itemTitle.copyWith(fontSize: 16)),
                  const SizedBox(height: 3),
                  Text(detail,
                      style: MnemosText.caption),
                ],
              ),
            ),
            if (selected) const Icon(Icons.check_circle, size: 20, color: MnemosColors.primary),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 16 — a geração grátis
// ---------------------------------------------------------------------------

class _FreeGeneration extends StatelessWidget {
  const _FreeGeneration({
    required this.subject,
    required this.busy,
    required this.onGenerate,
    required this.onSkip,
  });

  final String subject;
  final bool busy;
  final VoidCallback onGenerate;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return _Page(
      children: [
        const SizedBox(height: 30),
        const Text('Sua geração grátis',
            style: MnemosText.screenTitleWrapped),
        const SizedBox(height: 12),
        // §7.7.1 — it is one per lifetime, and it does not expire. Spending it
        // without saying so is taking something the user did not know they
        // had.
        Text(
          'Você tem uma geração por IA para usar quando quiser. Ela não expira.',
          style: MnemosText.bodyLong.copyWith(fontSize: 15, color: MnemosColors.muted),
        ),
        const SizedBox(height: 26),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: ShapeDecoration(
        color: MnemosColors.raised,
        shape: squircle(14),
      ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subject.isEmpty ? 'Usar agora' : 'Usar agora em $subject',
                style: MnemosText.itemTitle,
              ),
              const SizedBox(height: 6),
              const Text(
                'Cria um baralho inicial a partir do que você respondeu.',
                style: MnemosText.caption,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Ou guarde para fotografar seu caderno depois — costuma impressionar mais.',
          style: TextStyle(fontSize: 12.5, height: 1.5, color: MnemosColors.faint),
        ),
        const Spacer(),
        FilledButton(
          onPressed: busy ? null : onGenerate,
          child: const Text('Gerar meu primeiro baralho'),
        ),
        const SizedBox(height: 10),
        // A real second option, given the same weight the copy claims it has.
        OutlinedButton(
          onPressed: busy ? null : onSkip,
          child: const Text('Guardar para depois'),
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text(
            'Criar cards e estudar são livres, sempre — no app e no Mnemos.',
            style: TextStyle(fontSize: 11.5, color: MnemosColors.faint),
          ),
        ),
      ],
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}
