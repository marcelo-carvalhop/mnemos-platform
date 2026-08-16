import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../providers_sync.dart';
import '../../theme.dart';
import 'error_copy.dart';

/// Screen `21 Conteúdo detectado` — §7.8, §5.7.
///
/// Nothing generated becomes a card without a human saying so, one card at a
/// time. Three things follow, and all three are load-bearing:
///
/// * **Undo is mandatory.** A discard is a decision, not a deletion, so it can
///   be taken back — which is why the server models `decision` as a column.
/// * **The counter is honest**: "7 de 24" says how much is left to judge, and
///   leaving halfway keeps the position.
/// * **Approve-all exists**, because reading 24 cards one by one is a real
///   cost and a user who trusts the output should not be punished for it.
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
    // Optimistic: the judgement is the user's, and waiting for a round trip
    // between cards would make reviewing twenty of them feel like work.
    setState(() => _queue = _replace(card.id, decision));
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

      // The cards were created on the server; a pull is what brings them here.
      await ref.read(syncControllerProvider.notifier).syncNow();
      ref.invalidate(queueProvider);
      ref.invalidate(decksProvider);
      ref.invalidate(deckMaturityProvider);
      ref.invalidate(quotaProvider);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(created == 1 ? '1 card criado' : '$created cards criados'),
        ),
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
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text('${failure.title}\n\n${failure.detail}',
                textAlign: TextAlign.center,
                style: const TextStyle(height: 1.5, color: AppColors.muted)),
          ),
        ),
      );
    }

    final queue = _queue;
    if (queue == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final approved = queue.cards.where((c) => c.decision == 'approved').length;
    final undecided = queue.total - queue.decided;

    return Scaffold(
      appBar: AppBar(
        title: Text('${queue.decided} de ${queue.total}'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            // Leaving mid-way is fine: the decisions are on the server, and
            // the queue resumes where it was (§7.8).
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Depois'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(
              value: queue.total == 0 ? 0 : queue.decided / queue.total,
              minHeight: 3,
              backgroundColor: AppColors.hairline,
              valueColor: const AlwaysStoppedAnimation(AppColors.navy),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                itemCount: queue.cards.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _CardTile(
                  card: queue.cards[i],
                  onDecide: (d) => _decide(queue.cards[i], d),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.hairline)),
              ),
              child: Column(
                children: [
                  Text(
                    undecided == 0
                        ? '$approved de ${queue.total} aprovados'
                        : '$undecided ainda sem decisão',
                    style: const TextStyle(fontSize: 12, color: AppColors.faint),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (undecided > 0) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy ? null : () => _finish(approveRest: true),
                            child: const Text('Aprovar restantes'),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy || approved == 0
                              ? null
                              : () => _finish(approveRest: false),
                          child: Text(approved == 0
                              ? 'Nada aprovado'
                              : 'Criar $approved ${approved == 1 ? "card" : "cards"}'),
                        ),
                      ),
                    ],
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

class _CardTile extends StatelessWidget {
  const _CardTile({required this.card, required this.onDecide});

  final PendingCard card;
  final ValueChanged<String?> onDecide;

  @override
  Widget build(BuildContext context) {
    final approved = card.decision == 'approved';
    final discarded = card.decision == 'discarded';

    return Opacity(
      opacity: discarded ? .55 : 1,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: approved ? AppColors.goodBg : AppColors.ivory,
          border: Border.all(
            color: approved
                ? AppColors.good
                : discarded
                    ? AppColors.hairline
                    : AppColors.hairline,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              card.front,
              style: TextStyle(
                fontSize: 15,
                height: 1.35,
                decoration: discarded ? TextDecoration.lineThrough : null,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(card.back,
                style: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.muted)),
            if (card.tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                children: [
                  for (final tag in card.tags)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.fill,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(tag,
                          style: const TextStyle(fontSize: 10, color: AppColors.faint)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (card.decision == null)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => onDecide('discarded'),
                      child: const Text('Descartar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => onDecide('approved'),
                      child: const Text('Aprovar'),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Icon(
                    approved ? Icons.check_circle_outline : Icons.remove_circle_outline,
                    size: 15,
                    color: approved ? AppColors.good : AppColors.faint,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    approved ? 'Aprovado' : 'Descartado',
                    style: TextStyle(
                      fontSize: 12,
                      color: approved ? AppColors.good : AppColors.faint,
                    ),
                  ),
                  const Spacer(),
                  // §5.7 makes undo mandatory. Sending null is un-deciding,
                  // which is a state the server models on purpose.
                  TextButton(
                    onPressed: () => onDecide(null),
                    child: const Text('Desfazer'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
