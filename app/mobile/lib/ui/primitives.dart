import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Os blocos de construção do design "Mnemos App".
///
/// Cada um existe porque se repete em três ou mais artboards. O que aparece
/// uma vez só continua sendo escrito na tela onde vive — um componente com um
/// único uso é indireção, não reuso.

// ---------------------------------------------------------------------------
// Texto
// ---------------------------------------------------------------------------

/// A sobrancelha em mono e caixa alta: `VENCENDO AGORA`, `SEQUÊNCIA`, `FRENTE`.
///
/// A caixa alta é aplicada aqui, não pedida de quem chama: uma sobrancelha em
/// caixa baixa não é uma variação, é um erro, e o lugar de impedi-lo é este.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color, this.small = false});

  final String text;
  final Color? color;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final style = small ? MnemosText.eyebrowSmall : MnemosText.eyebrow;
    return Text(
      text.toUpperCase(),
      style: color == null ? style : style.copyWith(color: color),
    );
  }
}

/// Um numeral em Literata com a sua unidade ao lado, alinhados pela base.
///
/// O alinhamento é pela linha de base e não pelo centro: "19" e "dias" têm
/// alturas muito diferentes, e centralizá-los faz a unidade flutuar.
class Numeral extends StatelessWidget {
  const Numeral(
    this.value, {
    super.key,
    this.unit,
    this.style,
    this.unitStyle,
    this.color,
  });

  final String value;
  final String? unit;
  final TextStyle? style;
  final TextStyle? unitStyle;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final base = style ?? MnemosText.numeral;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: color == null ? base : base.copyWith(color: color)),
        if (unit != null) ...[
          const SizedBox(width: MnemosSpacing.xs),
          Text(
            unit!,
            // A unidade tem estilo próprio e **não herda a cor do numeral**:
            // a cor marca a métrica, o rótulo é sempre secundário. "86" em
            // menta com "%" também em menta lê como duas coisas do mesmo peso.
            style: unitStyle ?? MnemosText.numeralUnit,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Superfícies
// ---------------------------------------------------------------------------

/// O card padrão: fundo elevado sobre a tela, uma linha de cabelo em volta.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MnemosSpacing.lg),
    this.radius = MnemosRadii.card,
    this.background,
    this.border,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? background;
  final Color? border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final decorated = Container(
      padding: padding,
      decoration: ShapeDecoration(
        color: background ?? MnemosColors.raised,
        shape: squircle(radius, side: BorderSide(color: border ?? MnemosColors.line)),
      ),
      child: child,
    );

    if (onTap == null) return decorated;
    return InkWell(
      onTap: onTap,
      customBorder: squircle(radius),
      child: decorated,
    );
  }
}

/// O bloco-âncora lavanda que abre a tela Hoje.
///
/// §design — "cada tela ganha um bloco-âncora no topo em vez de começar com
/// uma lista solta". Este é o mais forte deles: o único elemento da interface
/// que inverte para fundo escuro.
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(MnemosSpacing.xl),
      decoration: ShapeDecoration(
        color: MnemosColors.primary,
        shape: squircle(MnemosRadii.card),
      ),
      child: child,
    );
  }
}

/// Uma faixa tracejada de convite — "Novo baralho".
///
/// Tracejada porque ainda não é uma coisa: é o lugar onde uma coisa pode
/// nascer. Um contorno cheio a faria parecer um baralho vazio.
class DashedInvite extends StatelessWidget {
  const DashedInvite({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: squircle(MnemosRadii.card),
      child: Container(
        padding: const EdgeInsets.all(MnemosSpacing.xl),
        decoration: ShapeDecoration(
        shape: squircle(MnemosRadii.card, side: BorderSide(color: MnemosColors.track)),
      ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: ShapeDecoration(
        color: MnemosColors.tint,
        shape: squircle(MnemosRadii.control),
      ),
              child: Icon(icon, size: 20, color: MnemosColors.muted),
            ),
            const SizedBox(width: MnemosSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: MnemosText.itemTitle),
                  const SizedBox(height: MnemosSpacing.xs),
                  Text(detail, style: MnemosText.caption),
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
// Cabeçalhos
// ---------------------------------------------------------------------------

/// O topo de uma tela de aba: título grande em serifa, ação opcional à direita.
///
/// O `eyebrow` é a data em Hoje; nas demais telas não existe.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.trailing,
  });

  final String title;
  final String? eyebrow;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null) ...[
                Eyebrow(eyebrow!),
                const SizedBox(height: MnemosSpacing.xs),
              ],
              Text(title, style: MnemosText.screenTitle),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// O botão redondo do canto superior direito — engrenagem, mais, fechar.
class RoundAction extends StatelessWidget {
  const RoundAction({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  /// Preenchido de lavanda quando a ação é a principal da tela (o "+" da
  /// Biblioteca); apenas contornado quando é secundária (a engrenagem).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    // O círculo continua com 40 de diâmetro, que é o que o artboard desenha;
    // o alvo em volta tem 48, que é o que o dedo precisa. Separar os dois é
    // mais honesto que engordar o desenho até o mínimo do Material.
    final button = InkResponse(
      onTap: onTap,
      radius: 24,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: Container(
            width: 40,
            height: 40,
            decoration: ShapeDecoration(
            color: filled ? MnemosColors.primary : null,
            shape: squircle(20,
                side: filled
                    ? BorderSide.none
                    : BorderSide(color: MnemosColors.line)),
          ),
            child: Icon(
              icon,
              size: filled ? 20 : 18,
              color: filled ? MnemosColors.onDark : MnemosColors.muted,
            ),
          ),
        ),
      ),
    );

    final labelled = tooltip == null
        ? button
        : Semantics(button: true, label: tooltip, child: Tooltip(message: tooltip!, child: button));
    return labelled;
  }
}

/// A linha de voltar — `‹ Biblioteca`, com um menu opcional à direita.
///
/// É a **única** saída de nove telas do app, e mesmo assim o alvo tinha 32dp
/// de altura: abaixo dos 44pt da HIG e dos 48dp do Material. Agora tem 48, e o
/// toque começa na margem da tela em vez de num retângulo colado ao glifo.
class BackHeader extends StatelessWidget {
  const BackHeader({super.key, this.label, this.onMenu});

  /// O nome da tela de onde se veio — só quando ela é sempre a mesma.
  ///
  /// Nulo quando a origem é ambígua. Dispositivo se alcança por Hoje **e** por
  /// Configurações → Dispositivo, e um `label: 'Hoje'` fixo mentia em metade
  /// das visitas. Um chevron sozinho não promete destino nenhum, e um botão
  /// que não promete nada não pode mentir.
  final String? label;

  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final label = this.label;

    return Row(
      children: [
        Semantics(
          button: true,
          label: label == null ? 'Voltar' : 'Voltar para $label',
          child: Tooltip(
            message: label == null ? 'Voltar' : 'Voltar para $label',
            child: InkWell(
              onTap: () => Navigator.of(context).maybePop(),
              customBorder: squircle(MnemosRadii.control),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                // Recuo negativo de 6 à esquerda: o vivo óptico do chevron
                // fica ~6 px dentro da caixa do glifo, então sem isso ele
                // começava à direita da margem em que o título grande começa
                // logo abaixo. No iOS os dois compartilham a mesma coluna.
                // `Transform` e não um `Padding` negativo, que o Flutter
                // recusa: o deslocamento é do desenho, não do espaço.
                child: Transform.translate(
                  offset: const Offset(-6, 0),
                  child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 14, MnemosSpacing.sm, 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.chevron_left, size: 22, color: MnemosColors.muted),
                      if (label != null)
                        Text(
                          label,
                          style: MnemosText.body.copyWith(color: MnemosColors.muted),
                        ),
                    ],
                  ),
                ),
                ),
              ),
            ),
          ),
        ),
        const Spacer(),
        if (onMenu != null)
          IconButton(
            onPressed: onMenu,
            icon: const Icon(Icons.more_horiz, color: MnemosColors.muted),
            tooltip: 'Mais ações',
          ),
      ],
    );
  }
}

/// O corpo de uma tela: margem lateral do design e rolagem por padrão.
/// O tom de um estado de tela cheia — decide o glifo e a cor dele.
enum StatusTone { neutral, problem, done }

/// Um estado que ocupa a tela inteira: vazio, erro, ou espera.
///
/// **Centrado no espaço disponível**, não empilhado no topo. Antes cada uma
/// destas telas jogava o conteúdo contra a barra de navegação e deixava 55% a
/// 70% da altura em branco morto — o que não lê como respiro, lê como tela que
/// não terminou de carregar. Lembretes sem lembretes, Fotos sem fotos e
/// Arquivos sem arquivos centram um glifo, um título e uma linha de apoio nos
/// dois eixos, e é isso que faz o vazio parecer projetado.
///
/// A ação vem como **botão secundário de largura de texto**. Um preenchido de
/// largura total no meio do nada grita mais alto que a explicação que ele
/// deveria acompanhar — nenhum estado vazio da Apple usa um.
class StatusScreen extends StatelessWidget {
  const StatusScreen({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.eyebrow,
    this.tone = StatusTone.neutral,
    this.action,
    this.actionLabel,
    this.secondary,
    this.secondaryLabel,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? eyebrow;
  final StatusTone tone;
  final VoidCallback? action;
  final String? actionLabel;
  final VoidCallback? secondary;
  final String? secondaryLabel;

  Color get _iconColor => switch (tone) {
        StatusTone.problem => MnemosColors.destructive,
        StatusTone.done => MnemosColors.settled,
        StatusTone.neutral => MnemosColors.fainter,
      };

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: MnemosSpacing.screen,
          vertical: MnemosSpacing.xl,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: _iconColor),
              const SizedBox(height: MnemosSpacing.lg),
              if (eyebrow != null) ...[
                Eyebrow(eyebrow!),
                const SizedBox(height: MnemosSpacing.sm),
              ],
              Text(title, style: MnemosText.sectionTitle, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: MnemosSpacing.sm),
                Text(
                  message!,
                  style: MnemosText.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null && actionLabel != null) ...[
                const SizedBox(height: MnemosSpacing.xl),
                OutlinedButton(
                  onPressed: action,
                  style: OutlinedButton.styleFrom(
                    // Largura do texto, não da tela.
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: MnemosSpacing.xl,
                    ),
                  ),
                  child: Text(actionLabel!),
                ),
              ],
              if (secondary != null && secondaryLabel != null) ...[
                const SizedBox(height: MnemosSpacing.sm),
                TextButton(onPressed: secondary, child: Text(secondaryLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ScreenBody extends StatelessWidget {
  const ScreenBody({
    super.key,
    required this.children,
    this.scrollable = true,
    this.bottomPadding = MnemosSpacing.xxl,
  });

  final List<Widget> children;
  final bool scrollable;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.fromLTRB(
      MnemosSpacing.screen,
      MnemosSpacing.sm,
      MnemosSpacing.screen,
      bottomPadding,
    );

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );

    if (!scrollable) return Padding(padding: padding, child: column);

    // `SingleChildScrollView` e não `ListView`: estas telas têm conteúdo
    // limitado, e a construção preguiçosa do `ListView` faz um widget fora da
    // dobra simplesmente não existir — o que transforma "está mais abaixo" em
    // "não está lá" para qualquer coisa que procure por ele, testes inclusive.
    return SingleChildScrollView(padding: padding, child: column);
  }
}

/// Confirma o descarte do que foi escrito.
///
/// §5.4 — o editor é a única tela do app onde alguém pode ter dois minutos de
/// digitação na mão. Um gesto de voltar apagava tudo em silêncio; a pergunta
/// custa um toque e evita a perda.
Future<bool> confirmDiscard(BuildContext context) async {
  final leave = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Descartar o que você escreveu?'),
      content: const Text(
        'O texto some e não dá para recuperar.',
        style: MnemosText.bodySmall,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Continuar escrevendo'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: MnemosColors.destructive),
          child: const Text('Descartar'),
        ),
      ],
    ),
  );
  return leave ?? false;
}
