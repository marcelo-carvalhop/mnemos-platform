import 'package:authoring/authoring.dart';
import 'package:domain/domain.dart';
import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:store/store.dart';

import '../../providers.dart';
import '../../providers_sync.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../ui/ui.dart';
import '../create/create_screen.dart';
import '../sign_in_screen.dart';

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
    _controller.nextPage(duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
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
    final deckId = await AuthoringService(db, deviceId: deviceId).createDeck(name: name, at: now);

    await db
        .into(db.goalHistory)
        .insert(
          GoalHistoryCompanion.insert(
            id: Uuid7.generate(now: now),
            effectiveFromLocalDate: const DayBucket(timezoneName: 'America/Sao_Paulo').today(now),
            dailyGoal: _goal,
            createdAt: now.millisecondsSinceEpoch,
            deviceId: deviceId,
          ),
        );

    await db
        .into(db.userSettings)
        .insert(
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
      // CreateScreen é o corpo de uma aba: o Scaffold e a área segura vêm do
      // AppShell. Aberta sozinha numa rota ela ficava sem Material por baixo —
      // fundo preto, texto sublinhado de amarelo e o título sob a barra de
      // status.
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (route) => Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Fechar',
                onPressed: () => Navigator.of(route).pop(),
              ),
            ),
            body: SafeArea(
              top: false,
              child: CreateScreen(deckId: deckId, initialTopic: _subject.text),
            ),
          ),
        ),
      );
    }
  }

  /// "Já tenho conta": entrar traz os baralhos, a meta e o histórico da
  /// conta, então não há primeiro baralho nem meta para perguntar.
  Future<void> _signIn() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (route) => SignInScreen(
          onCancel: () => Navigator.of(route).pop(),
          onSignedIn: () async {
            await markOnboardingDone(ref.read(databaseProvider));
            ref.read(syncControllerProvider.notifier).syncNow();
            ref.invalidate(quotaProvider);
            if (route.mounted) Navigator.of(route).pop();
            if (mounted) widget.onDone();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // A boas-vindas é a capa, não o passo 1 de 4: a barra entra na
            // segunda tela. Opacidade, e não remoção, para o conteúdo não pular.
            AnimatedOpacity(
              opacity: _page == 0 ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: Padding(
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
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _Welcome(onNext: _next, onHaveAccount: _signIn),
                  _Subject(
                    controller: _subject,
                    suggestions: _suggestions,
                    onPick: (s) => setState(() => _subject.text = s),
                    onNext: _next,
                  ),
                  _Goal(value: _goal, onChanged: (v) => setState(() => _goal = v), onNext: _next),
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
  const _Welcome({required this.onNext, required this.onHaveAccount});

  final VoidCallback onNext;
  final VoidCallback onHaveAccount;

  @override
  Widget build(BuildContext context) {
    // Opção A do canvas "Mnemos Boas-vindas": o card vem antes de qualquer
    // frase. Quem nunca ouviu falar de repetição espaçada entende o produto
    // vendo uma pergunta e os quatro graus — a frase só confirma.
    return Stack(
      children: [
        const Positioned.fill(child: _GridBackdrop()),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  BrandMark(size: 22),
                  SizedBox(width: 9),
                  Text(
                    'Mnemos',
                    style: TextStyle(
                      fontFamily: MnemosFonts.sans,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.36,
                      color: MnemosColors.ink,
                    ),
                  ),
                ],
              ),
              const Spacer(flex: 2),
              const _CardStack(),
              const Spacer(flex: 3),
              Text.rich(
                const TextSpan(
                  children: [
                    TextSpan(text: 'O que você aprendeu,\n'),
                    TextSpan(
                      text: 'de volta na hora certa.',
                      style: TextStyle(color: MnemosColors.quiet),
                    ),
                  ],
                ),
                style: MnemosText.display.copyWith(fontSize: 32, height: 1.06, letterSpacing: -1.1),
              ),
              const SizedBox(height: 14),
              Text(
                'Cada card volta pouco antes de você esquecer. Você estuda menos '
                'e lembra por anos.',
                style: MnemosText.bodyLong.copyWith(fontSize: 15.5, color: MnemosColors.faint),
              ),
              const Spacer(flex: 2),
              FilledButton(onPressed: onNext, child: const Text('Começar')),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: onHaveAccount,
                style: OutlinedButton.styleFrom(
                  backgroundColor: MnemosColors.raised,
                  foregroundColor: MnemosColors.ink,
                  side: const BorderSide(color: MnemosColors.line),
                ),
                child: const Text('Já tenho conta'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A grade de 32 px que esmaece para as bordas, como no herói da landing.
class _GridBackdrop extends StatelessWidget {
  const _GridBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const RadialGradient(
          center: Alignment(0, -0.45),
          radius: 1.1,
          colors: [Color(0xFF000000), Color(0x00000000)],
          stops: [0.15, 1],
        ).createShader(bounds),
        child: const CustomPaint(painter: _GridPainter(), size: Size.infinite),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MnemosColors.hairline
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Um card de estudo de verdade, com dois outros empilhados atrás.
class _CardStack extends StatelessWidget {
  const _CardStack();

  @override
  Widget build(BuildContext context) {
    Widget behind(double angle, Offset offset, Color color) => Positioned.fill(
      child: Transform.translate(
        offset: offset,
        child: Transform.rotate(
          angle: angle,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: MnemosColors.line),
              borderRadius: BorderRadius.circular(MnemosRadii.card),
            ),
          ),
        ),
      ),
    );

    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          height: 272,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              behind(0.052, const Offset(6, 10), MnemosColors.soft),
              behind(0.026, const Offset(3, 5), MnemosColors.sunken),
              Positioned.fill(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  decoration: BoxDecoration(
                    color: MnemosColors.raised,
                    border: Border.all(color: MnemosColors.line),
                    borderRadius: BorderRadius.circular(MnemosRadii.card),
                    boxShadow: const [
                      BoxShadow(color: Color(0x1A0F1C3D), blurRadius: 32, offset: Offset(0, 8)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'REDES DE COMPUTADORES',
                              style: MnemosText.eyebrowSmall.copyWith(fontSize: 11),
                            ),
                          ),
                          Text('3 / 12', style: MnemosText.monoSmall.copyWith(fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'O que o TCP garante que o UDP não garante?',
                        style: MnemosText.prompt.copyWith(fontSize: 21, height: 1.36),
                      ),
                      const Spacer(),
                      const Divider(height: 1, color: MnemosColors.hairline),
                      const SizedBox(height: 12),
                      const Row(
                        children: [
                          _GradeChip(
                            'Errei',
                            '10 min',
                            MnemosColors.again,
                            MnemosColors.againSurface,
                            MnemosColors.dueLine,
                          ),
                          SizedBox(width: 6),
                          _GradeChip(
                            'Difícil',
                            '2 d',
                            MnemosColors.hard,
                            MnemosColors.hardSurface,
                            MnemosColors.line,
                          ),
                          SizedBox(width: 6),
                          _GradeChip(
                            'Bom',
                            '5 d',
                            MnemosColors.good,
                            MnemosColors.goodSurface,
                            MnemosColors.goodLine,
                          ),
                          SizedBox(width: 6),
                          _GradeChip(
                            'Fácil',
                            '12 d',
                            MnemosColors.easy,
                            MnemosColors.easySurface,
                            MnemosColors.easyLine,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradeChip extends StatelessWidget {
  const _GradeChip(this.label, this.interval, this.ink, this.fill, this.border);

  final String label;
  final String interval;
  final Color ink;
  final Color fill;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(MnemosRadii.card),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: MnemosFonts.sans,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              interval,
              style: TextStyle(fontFamily: MnemosFonts.mono, fontSize: 10.5, color: ink),
            ),
          ],
        ),
      ),
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
        const Text('O que você quer estudar?', style: MnemosText.screenTitleWrapped),
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
        const Text('Quanto por dia?', style: MnemosText.screenTitleWrapped),
        const SizedBox(height: 10),
        Text(
          'Dá para mudar depois, a qualquer momento.',
          style: MnemosText.bodyLong.copyWith(fontSize: 15, color: MnemosColors.muted),
        ),
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
                  Text(title, style: MnemosText.itemTitle.copyWith(fontSize: 16)),
                  const SizedBox(height: 3),
                  Text(detail, style: MnemosText.caption),
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

class _FreeGeneration extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    // Beta: quem tem conta gera sem cota. Falar em "uma geração" aqui seria
    // ensinar uma regra que não vale.
    final beta = ref.watch(quotaProvider).valueOrNull?.plan == 'beta';
    return _Page(
      children: [
        const SizedBox(height: 30),
        Text(beta ? 'Gerações à vontade' : 'Sua geração grátis',
            style: MnemosText.screenTitleWrapped),
        const SizedBox(height: 12),
        // §7.7.1 — it is one per lifetime, and it does not expire. Spending it
        // without saying so is taking something the user did not know they
        // had.
        Text(
          beta
              ? 'Durante o beta, você gera cards por IA sem limite. Comece por aqui.'
              : 'Você tem uma geração por IA para usar quando quiser. Ela não expira.',
          style: MnemosText.bodyLong.copyWith(fontSize: 15, color: MnemosColors.muted),
        ),
        const SizedBox(height: 26),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: ShapeDecoration(color: MnemosColors.raised, shape: squircle(14)),
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
        Text(
          beta
              ? 'Depois, dá para gerar também de um texto, de um PDF ou da foto do caderno.'
              : 'Ou guarde para fotografar seu caderno depois — costuma impressionar mais.',
          style: TextStyle(fontSize: 12.5, height: 1.5, color: MnemosColors.faint),
        ),
        const Spacer(),
        // Ação da IA: o gradiente dela, como o "Gerar" da tela Criar.
        AiButton(
          onPressed: busy ? null : onGenerate,
          child: const Text('Gerar meu primeiro baralho'),
        ),
        const SizedBox(height: 10),
        // A real second option, given the same weight the copy claims it has.
        OutlinedButton(
          onPressed: busy ? null : onSkip,
          child: Text(beta ? 'Agora não' : 'Guardar para depois'),
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
