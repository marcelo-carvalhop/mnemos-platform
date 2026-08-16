import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme.dart';

/// Screen `22 Cota esgotada` — §5.13, §7.7.
///
/// Not an error screen. The free tier is one generation for the lifetime of
/// the account, so this is the conversion moment of the whole funnel, and the
/// thing it has to say first is that nothing was taken away: writing cards by
/// hand and studying stay free forever. That is what buys the time for someone
/// to decide.
class PaywallScreen extends ConsumerWidget {
  const PaywallScreen({super.key, this.reason});

  /// What they were trying to do when they got here, so the screen can be
  /// specific instead of generic.
  final String? reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            const Icon(Icons.landscape_outlined, size: 40, color: AppColors.navy),
            const SizedBox(height: 20),
            const Text(
              'Você usou sua\ngeração grátis',
              style: TextStyle(
                fontSize: 26,
                height: 1.25,
                fontWeight: FontWeight.w500,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Criar cards à mão e estudar continuam livres, sempre. '
              'A assinatura libera gerar por IA sem limite.',
              style: TextStyle(fontSize: 14, height: 1.55, color: AppColors.muted),
            ),
            if (reason != null) ...[
              const SizedBox(height: 12),
              Text(reason!,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.faint)),
            ],
            const SizedBox(height: 28),
            const _Benefit(
              icon: Icons.auto_awesome_outlined,
              title: 'Gerar por tópico, PDF e foto',
              detail: 'Sem limite mensal.',
            ),
            const _Benefit(
              icon: Icons.sync_outlined,
              title: 'Backup e vários aparelhos',
              detail: 'Seu histórico continua onde você parou.',
            ),
            const _Benefit(
              icon: Icons.insights_outlined,
              title: 'Progresso completo',
              detail: 'Retenção real e o que está prestes a vencer.',
            ),
            const SizedBox(height: 28),
            FilledButton(
              // The store flow is a human gate: it needs a sandbox account and
              // a signed build, neither of which exists yet. Refusing to fake
              // a purchase is deliberate — a button that pretends to charge is
              // worse than one that says it is not ready.
              onPressed: null,
              child: const Text('Assinar'),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'A compra ainda não está ligada nesta build.',
                style: TextStyle(fontSize: 11, color: AppColors.faint),
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Continuar sem assinar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.title, required this.detail});

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: AppColors.accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
                const SizedBox(height: 3),
                Text(detail,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.faint)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
