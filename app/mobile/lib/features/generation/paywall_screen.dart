import 'package:flutter/material.dart';

import '../../legal.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../ui/ui.dart';

/// A cota acabou — artboard 09, §5.13 e §7.7.
///
/// Não é uma tela de erro. O nível grátis é uma geração para a vida da conta,
/// então este é o momento de conversão do funil inteiro, e a primeira coisa
/// que a tela precisa dizer é que **nada foi tirado**: escrever à mão e
/// estudar seguem livres para sempre. É isso que compra o tempo de decidir.
///
/// É a única tela do app que inverte para fundo escuro. O design faz isso de
/// propósito: pedir dinheiro é uma mudança de assunto, e fingir que é mais uma
/// tela do fluxo seria mais dissimulado, não mais gentil.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, this.reason});

  /// O que a pessoa tentava fazer ao chegar aqui, para a tela ser específica
  /// em vez de genérica.
  final String? reason;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

enum _Plan { monthly, yearly }

/// §5.13 — a loja é um portão humano: precisa de conta de sandbox, build
/// assinada e produtos configurados nas duas plataformas. Um botão que parece
/// cobrar e não cobra é pior que um que admite não estar pronto.
void _notReady(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('A compra pelo app ainda não está disponível.')),
  );
}

class _PaywallScreenState extends State<PaywallScreen> {
  _Plan _plan = _Plan.yearly;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MnemosColors.primaryDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            MnemosSpacing.screen,
            MnemosSpacing.sm,
            MnemosSpacing.screen,
            MnemosSpacing.xxl,
          ),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: MnemosColors.onPrimaryMuted),
                  padding: EdgeInsets.zero,
                  tooltip: 'Continuar sem assinar',
                ),
              ),
              const SizedBox(height: MnemosSpacing.lg),
                    const SizedBox(height: MnemosSpacing.lg),
                    const Eyebrow(
                      'sua geração grátis acabou',
                      color: MnemosColors.onPrimaryFaint,
                    ),
                    const SizedBox(height: MnemosSpacing.md),
                    Text(
                      'Deixe o Mnemos\nescrever os cards\npor você.',
                      style: MnemosText.displaySmall.copyWith(color: MnemosColors.onDark),
                    ),
                    const SizedBox(height: MnemosSpacing.md),
                    Text(
                      'Criar à mão e estudar continuam livres, sempre.',
                      style: MnemosText.bodyLong.copyWith(
                        fontSize: 14.5,
                        color: MnemosColors.onPrimaryMuted,
                      ),
                    ),
                    if (widget.reason != null) ...[
                      const SizedBox(height: MnemosSpacing.md),
                      Text(
                        widget.reason!,
                        style: MnemosText.caption.copyWith(
                          color: MnemosColors.onPrimaryFaint,
                        ),
                      ),
                    ],
                    const SizedBox(height: MnemosSpacing.xxl),
                    const _Benefit(
                      number: '01',
                      title: 'Gerar sem limite',
                      detail: 'Tópico, PDF e foto do caderno.',
                    ),
                    const _Benefit(
                      number: '02',
                      title: 'Backup e vários aparelhos',
                      detail: 'Seu histórico continua onde parou.',
                    ),
                    const _Benefit(
                      number: '03',
                      title: 'Progresso completo',
                      detail: 'Retenção real e o que está prestes a vencer.',
                    ),
                    const Divider(color: MnemosColors.primaryDarkLine),

              const SizedBox(height: MnemosSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: _PlanCard(
                      label: 'Mensal',
                      price: 'R\$ 19',
                      suffix: '/mês',
                      selected: _plan == _Plan.monthly,
                      onTap: () => setState(() => _plan = _Plan.monthly),
                    ),
                  ),
                  const SizedBox(width: MnemosSpacing.md),
                  Expanded(
                    child: _PlanCard(
                      label: 'Anual',
                      price: 'R\$ 13',
                      suffix: '/mês',
                      note: 'R\$ 156 por ano',
                      badge: '-30%',
                      selected: _plan == _Plan.yearly,
                      onTap: () => setState(() => _plan = _Plan.yearly),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: MnemosSpacing.lg),
              FilledButton(
                // §5.13 — a loja é um portão humano: precisa de conta de
                // sandbox, build assinada e produtos configurados nas duas
                // plataformas, e nada disso existe. Um botão que parece cobrar
                // e não cobra é pior que um que admite não estar pronto.
                onPressed: () => _notReady(context),
                style: FilledButton.styleFrom(
                  backgroundColor: MnemosColors.onDark,
                  foregroundColor: MnemosColors.primaryDark,
                ),
                child: Text(
                  _plan == _Plan.yearly
                      ? 'Assinar por R\$ 156/ano'
                      : 'Assinar por R\$ 19/mês',
                ),
              ),
              const SizedBox(height: MnemosSpacing.md),
              // App Store Review 3.1.2 / Play Billing: o aviso de renovação
              // precisa estar na própria tela de compra, antes do toque.
              Text(
                kRenewalNotice,
                style: MnemosText.caption.copyWith(
                  height: 1.45,
                  color: MnemosColors.onPrimaryFaint,
                ),
              ),
              const SizedBox(height: MnemosSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 3.1.1 — quem troca de aparelho precisa de um caminho de
                  // volta que não passe por pagar de novo.
                  TextButton(
                    onPressed: () => _notReady(context),
                    style: TextButton.styleFrom(
                      foregroundColor: MnemosColors.onPrimaryMuted,
                    ),
                    child: const Text('Restaurar compras'),
                  ),
                  if (hasLegalLinks) ...[
                    Text('·', style: MnemosText.caption.copyWith(
                      color: MnemosColors.onPrimaryFaint)),
                    TextButton(
                      onPressed: () {},
                      style: TextButton.styleFrom(
                        foregroundColor: MnemosColors.onPrimaryMuted,
                      ),
                      child: const Text('Termos'),
                    ),
                    TextButton(
                      onPressed: () {},
                      style: TextButton.styleFrom(
                        foregroundColor: MnemosColors.onPrimaryMuted,
                      ),
                      child: const Text('Privacidade'),
                    ),
                  ],
                ],
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(foregroundColor: MnemosColors.onPrimaryMuted),
                child: const Text('Continuar sem assinar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Uma vantagem numerada, separada por uma linha fina.
class _Benefit extends StatelessWidget {
  const _Benefit({
    required this.number,
    required this.title,
    required this.detail,
  });

  final String number;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(color: MnemosColors.primaryDarkLine),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: MnemosSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  number,
                  style: MnemosText.mono.copyWith(color: MnemosColors.onPrimaryFaint),
                ),
              ),
              const SizedBox(width: MnemosSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: MnemosText.itemTitle.copyWith(
                        fontSize: 15.5,
                        color: MnemosColors.onDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: MnemosText.bodySmall.copyWith(
                        color: MnemosColors.onPrimaryMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Um dos dois planos.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.label,
    required this.price,
    required this.selected,
    required this.onTap,
    this.suffix,
    this.note,
    this.badge,
  });

  final String label;
  final String price;
  final String? suffix;

  /// O valor cobrado de fato, quando o preço exibido é derivado.
  final String? note;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: squircle(MnemosRadii.card),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(MnemosSpacing.md),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected
                    ? MnemosColors.onDark
                    : MnemosColors.onDark.withValues(alpha: 0.22),
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(MnemosRadii.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: MnemosText.bodySmall.copyWith(
                          color: MnemosColors.onPrimaryMuted,
                        ),
                      ),
                    ),
                    if (badge != null)
                      DecoratedBox(
                        decoration: ShapeDecoration(
                          color: MnemosColors.due,
                          shape: squircle(MnemosRadii.control),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: MnemosSpacing.sm,
                            vertical: 3,
                          ),
                          child: Text(
                            badge!,
                            style: MnemosText.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: MnemosColors.onDue,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: MnemosSpacing.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      price,
                      style: MnemosText.numeralSmall.copyWith(color: MnemosColors.onDark),
                    ),
                    if (suffix != null)
                      Text(
                        suffix!,
                        style: MnemosText.bodySmall.copyWith(
                          color: MnemosColors.onPrimaryMuted,
                        ),
                      ),
                  ],
                ),
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      note!,
                      style: MnemosText.caption.copyWith(
                        color: MnemosColors.onPrimaryFaint,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
