import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../providers_sync.dart';
import '../../providers_today.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../ui/ui.dart';
import 'error_copy.dart';

/// Revisar o que a IA escreveu — artboard 06.
///
/// §7.8 — nada vira card sem uma decisão humana. O design troca a lista
/// rolável por **um card de cada vez**: numa lista, aprovar oito é oito toques
/// distraídos; um de cada vez obriga a ler o que se está aprovando, que é o
/// ponto inteiro desta tela.
class ApprovalScreen extends ConsumerStatefulWidget {
  const ApprovalScreen({super.key, required this.jobId, required this.deckId});

  final String jobId;
  final String deckId;

  @override
  ConsumerState<ApprovalScreen> createState() => _ApprovalScreenState();
}

class _ApprovalScreenState extends ConsumerState<ApprovalScreen> {
  ApprovalQueue? _queue;
  GenerationFailure? _failure;
  bool _busy = false;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final queue = await ref.read(generationApiProvider).queue(widget.jobId);
      if (mounted) setState(() => _queue = queue);
    } on Object catch (e) {
      if (mounted) setState(() => _failure = GenerationFailure.forException(e));
    }
  }

  Future<void> _decide(PendingCard card, String? decision) async {
    // Otimista: o julgamento é de quem está lendo, e esperar uma ida ao
    // servidor entre um card e outro faria revisar vinte parecer trabalho.
    //
    // O índice **não** avança. Decidir tira o card da lista de indecisos, e a
    // lista encurtando já traz o próximo para a mesma posição; somar um em
    // cima disso pulava um card a cada decisão — quem revisava oito via
    // quatro, e os outros quatro saíam aprovados em massa no fim sem terem
    // sido lidos.
    setState(() {
      _queue = _replace(card.id, decision);
      final undecided = _queue?.cards.where((c) => c.decision == null).length ?? 1;
      _index = _index.clamp(0, undecided == 0 ? 0 : undecided - 1);
    });
    try {
      await ref.read(generationApiProvider).decide(card.id, decision);
    } on Object {
      if (!mounted) return;
      setState(() => _queue = _replace(card.id, card.decision));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não consegui salvar essa decisão. Tente de novo.')),
      );
    }
  }

  /// Descartar, com o caminho de volta aberto.
  ///
  /// §7.8 — descartar é a decisão que apaga trabalho, e era a única aqui sem
  /// nenhuma rede: um toque no botão redondo e o card sumia. Confirmar cada
  /// descarte transformaria uma revisão de vinte cards em quarenta toques, e
  /// por isso o desfazer vem depois do ato, não antes.
  Future<void> _discard(PendingCard card, int position) async {
    await _decide(card, 'discarded');
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Card descartado.'),
          action: SnackBarAction(
            label: 'Desfazer',
            onPressed: () {
              _decide(card, null);
              if (mounted) setState(() => _index = position);
            },
          ),
        ),
      );
  }

  /// "Aprovar todos" com a conta na frente.
  ///
  /// É a única ação em massa da tela e não tem volta depois de gravada. Ela
  /// morava num `TextButton` de canto, com o mesmo peso visual de um link.
  Future<void> _approveRest(int remaining) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(remaining == 1
            ? 'Aprovar o card restante?'
            : 'Aprovar os $remaining cards restantes?'),
        content: Text(
          remaining == 1
              ? 'Ele vira card sem passar pela sua leitura.'
              : 'Eles viram cards sem passar pela sua leitura, um a um.',
          style: MnemosText.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continuar revisando'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(remaining == 1 ? 'Aprovar' : 'Aprovar os $remaining'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _finish(approveRest: true);
  }

  ApprovalQueue? _replace(String id, String? decision) {
    final queue = _queue;
    if (queue == null) return null;
    final cards = [
      for (final c in queue.cards)
        if (c.id == id)
          PendingCard(
            id: c.id,
            front: c.front,
            back: c.back,
            tags: c.tags,
            position: c.position,
            decision: decision,
          )
        else
          c,
    ];
    return ApprovalQueue(
      cards: cards,
      decided: cards.where((c) => c.decision != null).length,
      total: cards.length,
    );
  }

  Future<void> _finish({required bool approveRest}) async {
    setState(() => _busy = true);
    final api = ref.read(generationApiProvider);
    try {
      if (approveRest) await api.approveRemaining(widget.jobId);
      final created = await api.close(widget.jobId);

      // Os cards foram criados no servidor; é o pull que os traz para cá.
      await ref.read(syncControllerProvider.notifier).syncNow();
      ref
        ..invalidate(queueProvider)
        ..invalidate(decksProvider)
        ..invalidate(deckMaturityProvider)
        ..invalidate(deckCardCountsProvider)
        ..invalidate(dueByDeckProvider)
        ..invalidate(quotaProvider);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(created == 1 ? '1 card criado' : '$created cards criados')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final failure = GenerationFailure.forException(e);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${failure.title}. ${failure.detail}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    if (failure != null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(MnemosSpacing.xxl),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(failure.title, style: MnemosText.screenTitleWrapped),
                  const SizedBox(height: MnemosSpacing.md),
                  Text(failure.detail, style: MnemosText.bodySmall),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final queue = _queue;
    if (queue == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final undecided = queue.cards.where((c) => c.decision == null).toList();
    final approved = queue.cards.where((c) => c.decision == 'approved').length;
    final discarded = queue.cards.where((c) => c.decision == 'discarded').length;

    if (undecided.isEmpty) return _allDecided(queue.total);

    final position = _index.clamp(0, undecided.length - 1);
    final card = undecided[position];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            MnemosSpacing.screen,
            MnemosSpacing.sm,
            MnemosSpacing.screen,
            MnemosSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Havia dois `X` na tela com consequências opostas: o do topo
              // fechava a revisão, o do rodapé apagava o card. Sobrou um, e o
              // que apagava virou um botão que diz o que faz.
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18, color: MnemosColors.muted),
                    label: const Text('Decidir depois'),
                    style: TextButton.styleFrom(foregroundColor: MnemosColors.muted),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : () => _approveRest(undecided.length),
                    child: const Text('Aprovar todos'),
                  ),
                ],
              ),
              const SizedBox(height: MnemosSpacing.md),
              _Progress(
                total: queue.total,
                decided: queue.decided,
                cards: queue.cards,
              ),
              const SizedBox(height: MnemosSpacing.sm),
              // Um contador só. O topo dizia "3 de 8" (o card em que você
              // está) e o rodapé "2 de 8 decididos" — os dois verdadeiros e,
              // um do lado do outro, incompreensíveis. Este é o número que
              // responde "quanto falta", que é a pergunta de quem revisa.
              //
              // A API devolve o agregado `decided`, não a divisão entre
              // aprovados e descartados de sessões anteriores; somar as
              // decisões desta sessão é o que se pode afirmar sem inventar.
              Text(
                '${queue.decided + approved + discarded} de ${queue.total} decididos',
                textAlign: TextAlign.center,
                style: MnemosText.bodySmall,
              ),
              const SizedBox(height: MnemosSpacing.xl),
              Expanded(child: SingleChildScrollView(child: _Card(card: card))),
              const SizedBox(height: MnemosSpacing.lg),
              Row(
                children: [
                  // Largura intrínseca e não `Expanded`: com flex 1 contra
                  // flex 2 e nenhum piso, "Descartar" quebrava em `Descarta` /
                  // `r` num telefone estreito. Um rótulo de botão partido no
                  // meio da palavra lê como defeito, e esta é a tela em que a
                  // pessoa decide o que fica e o que some.
                  IntrinsicWidth(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _discard(card, position),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MnemosColors.muted,
                        minimumSize: const Size(120, 58),
                        padding: const EdgeInsets.symmetric(
                          horizontal: MnemosSpacing.lg,
                        ),
                      ),
                      child: const Text('Descartar', maxLines: 1, softWrap: false),
                    ),
                  ),
                  const SizedBox(width: MnemosSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : () => _decide(card, 'approved'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(58),
                      ),
                      child: const Text('Aprovar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Todas as decisões tomadas: só falta gravar.
  Widget _allDecided(int total) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MnemosSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Eyebrow('tudo decidido'),
              const SizedBox(height: MnemosSpacing.md),
              Text(
                'Todos os $total cards\nforam decididos.',
                style: MnemosText.screenTitleWrapped,
              ),
              const SizedBox(height: MnemosSpacing.xxl),
              FilledButton(
                onPressed: _busy ? null : () => _finish(approveRest: false),
                child: Text(_busy ? 'Criando…' : 'Criar os cards'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A régua de segmentos: um por card do job.
///
/// O total vem do job, não da página de cards que a API devolveu — ela traz
/// só os indecisos, e desenhar a régua com eles faria a barra encolher a cada
/// aprovação, como se o trabalho aumentasse ao ser feito.
class _Progress extends StatelessWidget {
  const _Progress({
    required this.total,
    required this.decided,
    required this.cards,
  });

  final int total;
  final int decided;
  final List<PendingCard> cards;

  @override
  Widget build(BuildContext context) {
    // Decisões desta sessão, que a API ainda não devolveu num novo `decided`.
    final approved = cards.where((c) => c.decision == 'approved').length;
    final discarded = cards.where((c) => c.decision == 'discarded').length;
    final done = decided + approved + discarded;

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$done de $total cards decididos.',
      child: SizedBox(
        height: 4,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < total; i++) ...[
              if (i > 0) const SizedBox(width: MnemosSpacing.xs),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: switch (i) {
                      _ when i < done => MnemosColors.settled,
                      _ when i == done => MnemosColors.primary,
                      _ => MnemosColors.line,
                    },
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// O card em julgamento: frente, verso e as etiquetas propostas.
class _Card extends StatelessWidget {
  const _Card({required this.card});

  final PendingCard card;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // As duas folhas atrás dizem, sem contar, que há mais na pilha.
        Positioned(
          left: 14,
          right: 14,
          top: 12,
          child: Container(
            height: 120,
            decoration: ShapeDecoration(
        color: MnemosColors.soft,
        shape: squircle(MnemosRadii.sheet, side: BorderSide(color: MnemosColors.hairline)),
      ),
          ),
        ),
        Positioned(
          left: 7,
          right: 7,
          top: 6,
          child: Container(
            height: 120,
            decoration: ShapeDecoration(
        color: MnemosColors.softer,
        shape: squircle(MnemosRadii.sheet, side: BorderSide(color: MnemosColors.hairline)),
      ),
          ),
        ),
        SurfaceCard(
          radius: MnemosRadii.sheet,
          padding: const EdgeInsets.all(MnemosSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('frente'),
              const SizedBox(height: MnemosSpacing.md),
              Text(card.front, style: MnemosText.prompt),
              const SizedBox(height: MnemosSpacing.xl),
              const Divider(),
              const SizedBox(height: MnemosSpacing.lg),
              const Eyebrow('verso'),
              const SizedBox(height: MnemosSpacing.md),
              Text(card.back, style: MnemosText.bodyLong),
              if (card.tags.isNotEmpty) ...[
                const SizedBox(height: MnemosSpacing.xl),
                Wrap(
                  spacing: MnemosSpacing.sm,
                  runSpacing: MnemosSpacing.sm,
                  children: [
                    for (final tag in card.tags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: MnemosSpacing.md,
                          vertical: 5,
                        ),
                        decoration: ShapeDecoration(
        shape: squircle(MnemosRadii.card, side: BorderSide(color: MnemosColors.line)),
      ),
                        child: Text(tag.toUpperCase(), style: MnemosText.monoSmall),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
