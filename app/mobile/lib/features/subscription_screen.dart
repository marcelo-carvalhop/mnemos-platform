import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers_sync.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../ui/ui.dart';
import 'generation/paywall_screen.dart';

/// Screen `35 Assinatura` — §5.13.
///
/// Distinct from the paywall on purpose. The paywall is the moment someone is
/// asked to pay; this is where someone who already pays comes to check what
/// they have, restore it on a new phone, or leave. Mixing them produces a
/// screen that sells to people who already bought.
///
/// Everything here that talks to a store is a human gate: it needs a sandbox
/// account, a signed build, and products configured on both platforms, none of
/// which exists yet. The screen says so rather than pretending — a button that
/// looks like it charges and does nothing is worse than one that admits it is
/// not ready.
class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quota = ref.watch(quotaProvider);
    final plan = quota.valueOrNull?.plan ?? 'free';
    final paying = plan != 'free' && plan != 'unknown';

    return Scaffold(
      
      body: SafeArea(
        bottom: false,
        child: ScreenBody(
          children: [
            BackHeader(label: 'Configurações'),
            const SizedBox(height: MnemosSpacing.md),
            const Text('Assinatura', style: MnemosText.screenTitle),
            const SizedBox(height: MnemosSpacing.xl),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: ShapeDecoration(
        color: paying ? MnemosColors.softer : MnemosColors.raised,
        shape: squircle(16),
      ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paying ? 'Assinatura ativa' : 'Plano grátis',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: paying ? MnemosColors.settled : MnemosColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  switch (quota.valueOrNull) {
                    null => 'Verificando…',
                    (remaining: -1, limit: _, plan: _) =>
                      'Sem conexão — não dá para confirmar agora.',
                    (remaining: 0, limit: _, plan: _) =>
                      'Sua geração grátis já foi usada.',
                    (remaining: final r, limit: final l, plan: _) => r == 1
                        ? '1 de $l geração disponível.'
                        : '$r de $l gerações disponíveis.',
                  },
                  style: const TextStyle(fontSize: 13, height: 1.45, color: MnemosColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          // §5.13 — the thing worth saying to someone deciding whether to pay
          // *or* to stop: nothing they made is held hostage.
          const Text('O que continua se você não assinar',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          const _Kept('Todos os seus cards, para sempre'),
          const _Kept('Todo o histórico e o agendamento'),
          const _Kept('Escrever cards à mão, sem limite'),
          const _Kept('Exportar tudo quando quiser'),
          const SizedBox(height: 8),
          const Text(
            'A assinatura paga a geração por IA, que custa por uso. O resto é '
            'seu e roda no seu aparelho.',
            style: TextStyle(fontSize: 12.5, height: 1.5, color: MnemosColors.faint),
          ),
          const SizedBox(height: 30),
          if (!paying)
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PaywallScreen()),
              ),
              child: const Text('Ver a assinatura'),
            ),
          const SizedBox(height: 10),
          OutlinedButton(
            // A real requirement, not a nicety: §8.3 says a reinstall must be
            // able to get its entitlement back, and a user who paid and cannot
            // restore is a refund and a review.
            onPressed: null,
            child: const Text('Restaurar compras'),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text(
              'A compra pelo app ainda não está disponível.',
              style: TextStyle(fontSize: 11.5, color: MnemosColors.faint),
            ),
          ),
          if (paying) ...[
            const SizedBox(height: 26),
            const Text(
              'Para cancelar, use a assinatura na loja do seu aparelho — é lá '
              'que a cobrança vive, e cancelar por aqui não pararia nada.',
              style: TextStyle(fontSize: 12.5, height: 1.5, color: MnemosColors.faint),
            ),
          ],
        ],
      ),
        ),
    );
  }
}

class _Kept extends StatelessWidget {
  const _Kept(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check, size: 16, color: MnemosColors.settled),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13.5, height: 1.4, color: MnemosColors.ink)),
          ),
        ],
      ),
    );
  }
}
