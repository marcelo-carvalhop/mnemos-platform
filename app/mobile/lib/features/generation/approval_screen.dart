import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../providers_sync.dart';
import '../../theme.dart';
import 'error_copy.dart';

/// A fila de aprovação — §7.8.
///
/// Nada gerado vira card sem alguém dizer sim, um por vez. Isso era uma lista
/// rolável com dois botões por linha, o que transformava a decisão mais
/// importante do produto — "este card presta?" — num formulário. Aqui é uma
/// pilha: um card por vez, grande, arrastável, com a próxima aparecendo atrás.
///
/// Três coisas que a pilha resolve e a lista não resolvia:
///
/// * **Atenção.** Julgar a qualidade de um card exige lê-lo. Vinte cards
///   empilhados verticalmente convidam a apertar "aprovar restantes" sem ler
///   nenhum, que é exatamente o comportamento que a fila existe para evitar.
/// * **Velocidade.** Arrastar é mais rápido que mirar num botão, e a decisão
///   é binária.
/// * **Reversibilidade.** §5.7 torna o desfazer obrigatório. Numa pilha ele é
///   um só, sempre no mesmo lugar, e devolve o card para o topo.
class ApprovalScreen extends ConsumerStatefulWidget {
  const ApprovalScreen({super.key, required this.jobId, required this.deckId});

  final String jobId;
  final String deckId;

  @override
  ConsumerState<ApprovalScreen> createState() => _ApprovalScreenState();
}

class _ApprovalScreenState extends ConsumerState<ApprovalScreen> {
  List<PendingCard> _cards = const [];
  final List<({PendingCard card, String decision})> _decided = [];
  GenerationFailure? _failure;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final queue = await ref.read(generationApiProvider).queue(widget.jobId);
      if (!mounted) return;
      setState(() {
        // Já decididos ficam fora da pilha, mas contam no total: sair no meio
        // e voltar tem de retomar de onde parou (§7.8).
        _cards = queue.cards.where((c) => c.decision == null).toList();
        _decided.addAll(
          queue.cards
              .where((c) => c.decision != null)
              .map((c) => (card: c, decision: c.decision!)),
        );
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = GenerationFailure.forException(e);
        _loading = false;
      });
    }
  }

  Future<void> _decide(String decision) async {
    if (_cards.isEmpty) return;
    final card = _cards.first;

    HapticFeedback.lightImpact();
    setState(() {
      _cards = _cards.sublist(1);
      _decided.add((card: card, decision: decision));
    });

    // Otimista: o julgamento é do usuário, e esperar a rede entre um card e o
    // seguinte transformaria vinte decisões em vinte esperas.
    try {
      await ref.read(generationApiProvider).decide(card.id, decision);
    } on Object {
      if (!mounted) return;
      setState(() {
        _decided.removeLast();
        _cards = [card, ..._cards];
      });
      _say('Não consegui salvar essa decisão.');
    }
  }

  Future<void> _undo() async {
    if (_decided.isEmpty) return;
    final last = _decided.removeLast();

    HapticFeedback.selectionClick();
    setState(() => _cards = [last.card, ..._cards]);

    try {
      // §5.7 — nulo é uma decisão de "des-decidir", que o servidor modela de
      // propósito, e não um campo ausente.
      await ref.read(generationApiProvider).decide(last.card.id, null);
    } on Object {
      if (!mounted) return;
      setState(() {
        _cards = _cards.sublist(1);
        _decided.add(last);
      });
      _say('Não consegui desfazer.');
    }
  }

  Future<void> _finish({required bool approveRest}) async {
    setState(() => _busy = true);
    final api = ref.read(generationApiProvider);
    try {
      if (approveRest) await api.approveRemaining(widget.jobId);
      final created = await api.close(widget.jobId);

      await ref.read(syncControllerProvider.notifier).syncNow();
      ref
        ..invalidate(queueProvider)
        ..invalidate(decksProvider)
        ..invalidate(deckCardCountsProvider)
        ..invalidate(deckMaturityProvider)
        ..invalidate(hasAnyCardsProvider)
        ..invalidate(quotaProvider)
        // A fila foi respondida: nada mais é devido, e o aviso em Hoje some.
        ..invalidate(openGenerationsProvider);

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      _say(created == 1 ? '1 card criado' : '$created cards criados');
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final failure = GenerationFailure.forException(e);
      _say('${failure.title}. ${failure.detail}');
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    if (failure != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text(
              '${failure.title}\n\n${failure.detail}',
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.5, color: AppColors.sage),
            ),
          ),
        ),
      );
    }

    if (_loading) return const _Loading();

    final approved = _decided.where((d) => d.decision == 'approved').length;
    final total = _cards.length + _decided.length;
    final done = _decided.length;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('$done de $total'),
        leading: IconButton(
          tooltip: 'Depois',
          icon: const Icon(Icons.close),
          // Sair no meio é permitido: as decisões estão no servidor e a fila
          // retoma de onde parou.
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        actions: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: _decided.isEmpty ? 0 : 1,
            child: TextButton.icon(
              onPressed: _decided.isEmpty || _busy ? null : _undo,
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('Desfazer'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _Progress(done: done, total: total),
          Expanded(
            child: _cards.isEmpty
                ? _AllJudged(approved: approved, total: total)
                : _Stack(cards: _cards, onDecide: _decide),
          ),
          _Footer(
            remaining: _cards.length,
            approved: approved,
            busy: _busy,
            onApprove: _cards.isEmpty ? null : () => _decide('approved'),
            onDiscard: _cards.isEmpty ? null : () => _decide('discarded'),
            onApproveRest: _cards.isEmpty
                ? null
                : () => _finish(approveRest: true),
            onCreate: approved == 0 || _busy
                ? null
                : () => _finish(approveRest: false),
            onLeave: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// A pilha. O card do topo se arrasta; o de baixo espera, levemente menor.
class _Stack extends StatefulWidget {
  const _Stack({required this.cards, required this.onDecide});

  final List<PendingCard> cards;
  final ValueChanged<String> onDecide;

  @override
  State<_Stack> createState() => _StackState();
}

class _StackState extends State<_Stack> with SingleTickerProviderStateMixin {
  double _dx = 0;
  bool _settling = false;

  /// Fração da largura a partir da qual soltar decide, em vez de voltar.
  static const _threshold = .28;

  void _onUpdate(DragUpdateDetails d) {
    if (_settling) return;
    setState(() => _dx += d.delta.dx);
  }

  void _onEnd(DragEndDetails d, double width) {
    if (_settling) return;
    final passed = _dx.abs() > width * _threshold;
    final flung = d.velocity.pixelsPerSecond.dx.abs() > 900;

    if (passed || flung) {
      final decision = _dx > 0 ? 'approved' : 'discarded';
      setState(() => _settling = true);
      widget.onDecide(decision);
      // O card sai da lista por cima; a posição volta ao centro para o
      // próximo, sem animar de volta e sem piscar.
      setState(() {
        _dx = 0;
        _settling = false;
      });
    } else {
      setState(() => _dx = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final progress = (_dx / (width * _threshold)).clamp(-1.0, 1.0);
    final next = widget.cards.length > 1 ? widget.cards[1] : null;

    return LayoutBuilder(
      builder: (context, box) => Stack(
        alignment: Alignment.center,
        children: [
          // O próximo, atrás: dá profundidade e diz que a fila continua.
          if (next != null)
            Transform.scale(
              scale: .94 + .04 * progress.abs(),
              child: Opacity(
                opacity: .55 + .35 * progress.abs(),
                child: _Card(card: next, interactive: false),
              ),
            ),
          GestureDetector(
            onHorizontalDragUpdate: _onUpdate,
            onHorizontalDragEnd: (d) => _onEnd(d, width),
            child: AnimatedContainer(
              duration: _dx == 0
                  ? const Duration(milliseconds: 220)
                  : Duration.zero,
              curve: Curves.easeOutCubic,
              transform: Matrix4.identity()
                ..translateByDouble(_dx, 0, 0, 1)
                ..rotateZ(_dx / width * .18),
              transformAlignment: Alignment.center,
              child: _Card(
                card: widget.cards.first,
                interactive: true,
                verdict: progress,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.card,
    required this.interactive,
    this.verdict = 0,
  });

  final PendingCard card;
  final bool interactive;

  /// −1 descartando, +1 aprovando, 0 parado. Tinge a borda e revela o selo.
  final double verdict;

  @override
  Widget build(BuildContext context) {
    final approving = verdict > 0;
    final tint = verdict.abs();
    final edge = Color.lerp(
      AppColors.mist,
      approving ? AppColors.sage : AppColors.terracotta,
      tint,
    )!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 300),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        decoration: BoxDecoration(
          color: const Color(0xFFFBFAF6),
          border: Border.all(color: edge, width: 1 + tint),
          borderRadius: BorderRadius.circular(20),
          boxShadow: interactive
              ? [
                  BoxShadow(
                    color: AppColors.graphite.withValues(alpha: .06),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        // Um card longo — pergunta grande, resposta grande, muitas etiquetas —
        // passava da altura disponível e a coluna transbordava. Rolar é
        // vertical e não briga com o arrasto, que é horizontal.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // O selo fica do lado *oposto* ao arrasto. Arrastando para a
              // direita, a metade do card que continua na tela é a esquerda —
              // um selo na borda direita nasce fora do visor e nunca é lido, que
              // foi exatamente o que apareceu no aparelho.
              if (interactive)
                SizedBox(
                  height: 24,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _Verdict(
                        label: 'APROVAR',
                        colour: AppColors.sage,
                        opacity: verdict > 0 ? tint : 0,
                      ),
                      _Verdict(
                        label: 'DESCARTAR',
                        colour: AppColors.terracotta,
                        opacity: verdict < 0 ? tint : 0,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                card.front,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                  color: AppColors.graphite,
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: SizedBox(
                  width: 34,
                  child: Divider(color: AppColors.mist, thickness: 1.4),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                card.back,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: AppColors.sage,
                ),
              ),
              if (card.tags.isNotEmpty) ...[
                const SizedBox(height: 22),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in card.tags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.mist.withValues(alpha: .5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          tag,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.sage,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({
    required this.label,
    required this.colour,
    required this.opacity,
  });

  final String label;
  final Color colour;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Transform.rotate(
        // Cada selo inclina para longe da sua borda, contra a rotação do card.
        angle: label == 'APROVAR' ? -.18 : .18,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: colour, width: 2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: colour,
            ),
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: total == 0 ? 0 : done / total),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      builder: (context, value, _) => LinearProgressIndicator(
        value: value,
        minHeight: 3,
        backgroundColor: AppColors.mist,
        valueColor: const AlwaysStoppedAnimation(AppColors.petrol),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.remaining,
    required this.approved,
    required this.busy,
    required this.onApprove,
    required this.onDiscard,
    required this.onApproveRest,
    required this.onCreate,
    required this.onLeave,
  });

  final int remaining;
  final int approved;
  final bool busy;
  final VoidCallback? onApprove;
  final VoidCallback? onDiscard;
  final VoidCallback? onApproveRest;
  final VoidCallback? onCreate;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.mist)),
      ),
      child: Column(
        children: [
          if (remaining > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Round(
                  icon: Icons.close,
                  colour: AppColors.terracotta,
                  onTap: busy ? null : onDiscard,
                  tooltip: 'Descartar',
                ),
                const SizedBox(width: 40),
                _Round(
                  icon: Icons.check,
                  colour: AppColors.sage,
                  onTap: busy ? null : onApprove,
                  tooltip: 'Aprovar',
                  filled: true,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Arraste para os lados, ou use os botões.',
              style: const TextStyle(fontSize: 11.5, color: AppColors.sage),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: busy ? null : onApproveRest,
              child: Text('Aprovar os $remaining restantes'),
            ),
          ]
          // Sem nada aprovado não há o que criar, e um botão morto deixava a
          // tela sem saída nenhuma: aprovar, descartar e criar desabilitados
          // ao mesmo tempo. Sair é a ação honesta, e ela funciona.
          else if (approved == 0)
            OutlinedButton(
              onPressed: busy ? null : onLeave,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                side: const BorderSide(color: AppColors.mist),
                foregroundColor: AppColors.petrol,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Voltar'),
            )
          else
            FilledButton(
              onPressed: onCreate,
              child: Text(
                'Criar $approved ${approved == 1 ? "card" : "cards"}',
              ),
            ),
        ],
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({
    required this.icon,
    required this.colour,
    required this.onTap,
    required this.tooltip,
    this.filled = false,
  });

  final IconData icon;
  final Color colour;
  final VoidCallback? onTap;
  final String tooltip;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled && enabled ? colour : Colors.transparent,
            border: Border.all(
              color: enabled ? colour : AppColors.mist,
              width: 1.6,
            ),
          ),
          child: Icon(
            icon,
            size: 26,
            color: filled && enabled
                ? AppColors.ivory
                : (enabled ? colour : AppColors.mist),
          ),
        ),
      ),
    );
  }
}

class _AllJudged extends StatelessWidget {
  const _AllJudged({required this.approved, required this.total});

  final int approved;
  final int total;

  @override
  Widget build(BuildContext context) {
    // Uma fila que chegou vazia não é uma fila terminada. `approved == total`
    // é verdadeiro com zero e zero, e virava "Você aprovou todos" para alguém
    // que não aprovou nada — a geração é que não produziu card algum.
    final nothingCame = total == 0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              nothingCame ? Icons.inbox_outlined : Icons.done_all,
              size: 34,
              color: nothingCame ? AppColors.brass : AppColors.sage,
            ),
            const SizedBox(height: 18),
            Text(
              nothingCame
                  ? 'Nenhum card chegou'
                  : approved == total
                  ? 'Você aprovou todos'
                  : '$approved de $total aprovados',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              nothingCame
                  ? 'Esta geração não produziu nada para aprovar. '
                        'Sua geração não foi gasta.'
                  : 'Eles entram no baralho quando você criar.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.sage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Esqueleto no lugar de um giro: a fila tem forma conhecida, e mostrá-la
/// vazia comunica o que vem melhor que um indicador indeterminado.
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        child: Container(
          width: double.infinity,
          height: 320,
          decoration: BoxDecoration(
            color: AppColors.mist.withValues(alpha: .35),
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }
}
