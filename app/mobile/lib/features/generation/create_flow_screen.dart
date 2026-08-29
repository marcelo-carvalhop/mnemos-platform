import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../providers_sync.dart';
import '../../theme.dart';
import '../editor_screen.dart';
import 'capture_screen.dart';
import 'error_copy.dart';
import 'generating_screen.dart';
import 'paywall_screen.dart';

/// Criar conteúdo, começando pela IA.
///
/// A ordem aqui é a tese: descrever o que se quer aprender é a primeira coisa
/// que a tela pede, e escrever à mão é o caminho ao lado. Antes, criar um
/// baralho era um `AlertDialog` com um campo "Nome" — o que produzia um
/// baralho vazio e transferia todo o trabalho para o usuário. Um nome não é
/// conteúdo.
///
/// **O baralho e os cards nascem juntos.** O usuário não escolhe um destino
/// porque ainda não existe destino: o que ele descreve vira o nome do baralho
/// e o assunto da geração na mesma ação.
///
/// A cota aparece antes de qualquer campo, não depois do erro. O plano grátis
/// é uma geração para a vida da conta (§7.7.1), e uma interface que só conta
/// isso depois de gasto tirou algo que a pessoa não sabia que tinha.
class CreateFlowScreen extends ConsumerStatefulWidget {
  const CreateFlowScreen({super.key});

  @override
  ConsumerState<CreateFlowScreen> createState() => _CreateFlowScreenState();
}

class _CreateFlowScreenState extends ConsumerState<CreateFlowScreen> {
  final _subject = TextEditingController();
  final _focus = FocusNode();
  String _level = 'intermediario';
  int _count = 12;
  bool _busy = false;
  String? _problem;

  /// Exemplos concretos, não categorias. "História" é vago e produz cards
  /// vagos; o que o modelo precisa é de um recorte, e mostrar recortes ensina
  /// mais que qualquer texto de ajuda.
  static const _examples = [
    'Revolução Gloriosa de 1688',
    'Ciclo de Krebs',
    'Controle de constitucionalidade',
    'Present perfect em inglês',
    'Farmacologia dos beta-bloqueadores',
    'Teorema de Bayes',
  ];

  static const _levels = {
    'basico': 'Básico',
    'intermediario': 'Médio',
    'avancado': 'Avançado',
  };

  @override
  void dispose() {
    _subject.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Cria o baralho e enfileira a geração numa ação só.
  ///
  /// O baralho é local e gratuito; a geração é que custa. Se a cota acabou, o
  /// baralho **permanece** — escrever cards à mão nele continua livre, e
  /// apagar o trabalho de alguém porque o servidor disse 402 seria punir a
  /// pessoa por uma decisão comercial nossa.
  Future<void> _generate() async {
    final subject = _subject.text.trim();
    if (subject.isEmpty) return;

    setState(() {
      _busy = true;
      _problem = null;
    });
    HapticFeedback.selectionClick();

    final authoring = await ref.read(authoringServiceProvider.future);
    final deckId = await authoring.createDeck(
      name: _deckNameFrom(subject),
      at: ref.read(clockProvider)(),
    );
    ref
      ..invalidate(decksProvider)
      ..invalidate(deckCardCountsProvider);

    // O baralho existe agora, mas só neste telefone, e o servidor recusa gerar
    // dentro de um baralho que não conhece (§7.3 → 404). Empurrar o outbox faz
    // parte da mesma ação: sem isso a pessoa vê "algo deu errado" por um
    // detalhe de sincronização que não é dela. `pushAll` respeita a ordem de
    // dependências e é idempotente, então não custa nada quando não há nada a
    // enviar.
    try {
      await ref.read(syncClientProvider).pushAll();
    } on Object {
      // Offline, ou o servidor fora do ar. Não há o que dizer ainda: a
      // geração falha logo abaixo e a copy de lá é a certa.
    }

    try {
      final job = await ref.read(generationApiProvider).create(
            sourceType: 'topic',
            targetDeckId: deckId,
            topic: subject,
            requestedCount: _count,
            level: _level,
          );
      // Existe uma geração aberta a partir de agora; Hoje precisa saber, para
      // que sair desta tela não perca o caminho de volta.
      ref.invalidate(openGenerationsProvider);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => GeneratingScreen(jobId: job.id, deckId: deckId),
      ));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final failure = GenerationFailure.forException(e);

      if (failure.showsPaywall) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PaywallScreen()),
        );
        ref.invalidate(quotaProvider);
        if (!mounted) return;
        // O baralho ficou. Levar para o editor é a saída honesta de um
        // paywall: o caminho grátis existe e está a um toque.
        setState(() => _problem =
            'O baralho "${_deckNameFrom(subject)}" foi criado. Você pode '
            'escrever os cards à mão — isso é livre, sempre.');
        return;
      }
      setState(() => _problem = '${failure.title}. ${failure.detail}');
    }
  }

  /// O nome do baralho sai do que a pessoa escreveu, sem pedir duas vezes.
  ///
  /// O campo aceita quatro linhas, e um `\n` no meio do nome quebra a lista de
  /// baralhos, que reserva uma linha por card. Espaço em branco vira um espaço
  /// só — o assunto continua sendo o que a pessoa escreveu, com a pontuação
  /// que ela usou.
  static String _deckNameFrom(String subject) {
    final trimmed = subject.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (trimmed.length <= 42) return trimmed;
    final cut = trimmed.substring(0, 42);
    final lastSpace = cut.lastIndexOf(' ');
    return '${lastSpace > 20 ? cut.substring(0, lastSpace) : cut}…';
  }

  Future<void> _manual() async {
    final controller = TextEditingController();
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.ivory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          22,
          22,
          MediaQuery.of(sheet).viewInsets.bottom + 22,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Grabber(),
            const SizedBox(height: 18),
            Text('Baralho em branco',
                style: Theme.of(sheet).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(
              'Você escreve os cards. Livre, sempre.',
              style: TextStyle(fontSize: 13, color: AppColors.sage),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Nome do baralho'),
              onSubmitted: (v) => Navigator.of(sheet).pop(v.trim()),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(sheet).pop(controller.text.trim()),
              child: const Text('Criar'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;

    final authoring = await ref.read(authoringServiceProvider.future);
    final deckId = await authoring.createDeck(name: name, at: ref.read(clockProvider)());
    ref
      ..invalidate(decksProvider)
      ..invalidate(deckCardCountsProvider);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => EditorScreen(deckId: deckId, deckName: name),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final quota = ref.watch(quotaProvider);
    final remaining = quota.valueOrNull?.remaining;
    final spent = remaining == 0;
    final ready = _subject.text.trim().isNotEmpty && !_busy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Criar'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 32),
          children: [
            _QuotaChip(remaining: remaining, loading: quota.isLoading),
            const SizedBox(height: 26),
            Text(
              'O que você quer aprender?',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(height: 1.25),
            ),
            const SizedBox(height: 8),
            const Text(
              'Descreva o assunto. Quanto mais estreito o recorte, melhores '
              'os cards.',
              style: TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.sage),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _subject,
              focusNode: _focus,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 16, height: 1.4),
              // O servidor recusa acima disso (§7.3). Cortar na colagem é
              // melhor que deixar a pessoa pedir e receber um 422 — sem
              // contador, porque ninguém digita vinte mil caracteres aqui e um
              // "0/20000" só sujaria a tela.
              inputFormatters: [LengthLimitingTextInputFormatter(kTopicMaxChars)],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Ex.: Revolução Gloriosa e o parlamentarismo inglês',
                hintStyle: TextStyle(fontSize: 14.5, color: AppColors.mist),
              ),
            ),
            const SizedBox(height: 14),
            _Examples(
              examples: _examples,
              onPick: (e) {
                setState(() => _subject.text = e);
                _focus.requestFocus();
                HapticFeedback.selectionClick();
              },
            ),
            const SizedBox(height: 28),
            // Só aparece quando há assunto: perguntar nível e quantidade a
            // quem ainda não disse o que quer estudar é ruído.
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _subject.text.trim().isEmpty
                  ? const SizedBox(width: double.infinity)
                  : _Refinements(
                      level: _level,
                      levels: _levels,
                      count: _count,
                      onLevel: (v) => setState(() => _level = v),
                      onCount: (v) => setState(() => _count = v),
                    ),
            ),
            const SizedBox(height: 26),
            if (_problem != null) ...[
              _Problem(text: _problem!),
              const SizedBox(height: 18),
            ],
            if (spent)
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PaywallScreen()),
                ),
                icon: const Icon(Icons.lock_outline, size: 19),
                label: const Text('Assinar para gerar'),
              )
            else
              FilledButton.icon(
                onPressed: ready ? _generate : null,
                icon: _busy
                    ? const SizedBox(
                        height: 17,
                        width: 17,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.ivory),
                      )
                    : const Icon(Icons.auto_awesome, size: 19),
                label: Text(_busy ? 'Preparando…' : 'Criar com IA'),
              ),
            const SizedBox(height: 12),
            // Os outros dois caminhos de IA, disponíveis mas não no centro:
            // digitar um assunto é mais rápido que fotografar.
            Row(
              children: [
                Expanded(
                  child: _Alternative(
                    icon: Icons.photo_camera_outlined,
                    label: 'Foto ou PDF',
                    onTap: _busy
                        ? null
                        : () => Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                  builder: (_) => const CaptureScreen()),
                            ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Alternative(
                    icon: Icons.edit_outlined,
                    label: 'Escrever eu mesmo',
                    onTap: _busy ? null : _manual,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Center(
              child: Text(
                'Nada vira card sem você aprovar, um por vez.',
                style: TextStyle(fontSize: 12, color: AppColors.sage),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A cota, dita antes de qualquer campo.
class _QuotaChip extends StatelessWidget {
  const _QuotaChip({required this.remaining, required this.loading});

  final int? remaining;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final (text, icon, colour) = switch (remaining) {
      null when loading => ('Verificando sua cota…', Icons.more_horiz, AppColors.sage),
      // -1 é "estamos sem conexão e não sabemos". Chutar a favor ou contra
      // seria pior que dizer.
      -1 || null => ('Sem conexão — não sei quanto resta', Icons.cloud_off_outlined,
          AppColors.sage),
      0 => ('Sua geração grátis já foi usada', Icons.lock_outline, AppColors.terracotta),
      1 => ('1 geração grátis disponível', Icons.auto_awesome, AppColors.petrol),
      final r => ('$r gerações disponíveis', Icons.auto_awesome, AppColors.petrol),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Container(
        key: ValueKey(text),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.mist.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: colour),
            const SizedBox(width: 8),
            Flexible(
              child: Text(text,
                  style: TextStyle(fontSize: 12.5, color: colour, height: 1.3)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Examples extends StatelessWidget {
  const _Examples({required this.examples, required this.onPick});

  final List<String> examples;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: examples.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => InkWell(
          onTap: () => onPick(examples[i]),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.mist),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(examples[i],
                style: const TextStyle(fontSize: 12.5, color: AppColors.petrol)),
          ),
        ),
      ),
    );
  }
}

class _Refinements extends StatelessWidget {
  const _Refinements({
    required this.level,
    required this.levels,
    required this.count,
    required this.onLevel,
    required this.onCount,
  });

  final String level;
  final Map<String, String> levels;
  final int count;
  final ValueChanged<String> onLevel;
  final ValueChanged<int> onCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Nível', style: TextStyle(fontSize: 12, color: AppColors.sage)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: [
            for (final e in levels.entries)
              ButtonSegment(value: e.key, label: Text(e.value)),
          ],
          selected: {level},
          showSelectedIcon: false,
          onSelectionChanged: (v) => onLevel(v.first),
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: AppColors.mist,
            selectedForegroundColor: AppColors.graphite,
            side: const BorderSide(color: AppColors.mist),
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(
              child: Text('Quantos cards', style: TextStyle(fontSize: 14)),
            ),
            Text('$count',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.petrol)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: AppColors.petrol,
            inactiveTrackColor: AppColors.mist,
            thumbColor: AppColors.petrol,
            overlayColor: AppColors.petrol.withValues(alpha: .12),
            trackHeight: 3,
          ),
          child: Slider(
            value: count.toDouble(),
            min: 5,
            max: 30,
            divisions: 5,
            onChanged: (v) => onCount(v.round()),
          ),
        ),
      ],
    );
  }
}

class _Alternative extends StatelessWidget {
  const _Alternative({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.mist),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, size: 19, color: enabled ? AppColors.petrol : AppColors.mist),
            const SizedBox(height: 7),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    color: enabled ? AppColors.graphite : AppColors.mist)),
          ],
        ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.mist.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.graphite)),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.mist,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
