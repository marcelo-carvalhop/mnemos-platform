import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'primitives.dart';

/// Componentes com significado de domínio.
///
/// [primitives.dart] tem as formas; este arquivo tem as formas que já sabem o
/// que estão dizendo — que coral quer dizer vencido, que menta quer dizer
/// firme, que uma barra de três segmentos é a maturidade de um baralho.

// ---------------------------------------------------------------------------
// Medidores
// ---------------------------------------------------------------------------

/// Uma barra de proporção simples: trilho cinza, preenchimento colorido.
class MeterBar extends StatelessWidget {
  const MeterBar({
    super.key,
    required this.fraction,
    this.color = MnemosColors.primary,
    this.track = MnemosColors.line,
    this.height = 6,
    this.semanticLabel,
  });

  /// Entre 0 e 1. Valores fora da faixa são presos, porque um medidor que
  /// estoura a própria caixa é sempre um defeito de cálculo a montante.
  final double fraction;
  final Color color;
  final Color track;
  final double height;

  /// O que a barra diz, em palavras.
  ///
  /// Uma proporção desenhada é invisível para quem usa leitor de tela, e o
  /// número que ela ilustra nem sempre está escrito ao lado. Sem isto a barra
  /// é um retângulo mudo.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Container(color: track),
            FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              child: Container(color: color),
            ),
          ],
        ),
      ),
    );

    if (semanticLabel == null) return bar;
    return Semantics(label: semanticLabel, container: true, child: bar);
  }
}

/// A barra de maturidade de um baralho: vencendo, maduros, o resto.
///
/// Três segmentos proporcionais em vez de três números soltos — a proporção é
/// a informação, e ela se lê antes de qualquer legenda.
class SegmentBar extends StatelessWidget {
  const SegmentBar({
    super.key,
    required this.segments,
    this.height = 8,
    this.semanticLabel,
  });

  /// Pares de (peso, cor). Peso zero é omitido: um segmento de largura nula
  /// vira um risco de 1px que o olho lê como uma quarta categoria.
  final List<({int weight, Color color})> segments;
  final double height;

  /// A mesma proporção dita em palavras. Aqui não é só uma conveniência: a
  /// cor é o **único** codificador de qual segmento é qual, então sem texto a
  /// barra não é apenas invisível ao leitor de tela — ela também não se lê sem
  /// distinguir coral de lavanda.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final visible = segments.where((s) => s.weight > 0).toList();

    final bar = visible.isEmpty
        ? MeterBar(fraction: 0, height: height, track: MnemosColors.line)
        : SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, s) in visible.indexed) ...[
                  if (i > 0) const SizedBox(width: MnemosSpacing.xs),
                  Expanded(
                    flex: s.weight,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
        color: s.color,
        shape: squircle(MnemosRadii.bar + 1),
      ),
                    ),
                  ),
                ],
              ],
            ),
          );

    if (semanticLabel == null) return bar;
    return Semantics(label: semanticLabel, container: true, child: bar);
  }
}

/// A legenda de uma [SegmentBar]: ponto colorido + contagem.
class LegendDot extends StatelessWidget {
  const LegendDot({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // O ponto é decoração de uma legenda que já está escrita ao lado;
        // repeti-lo no leitor de tela só faria "círculo, 3 vencendo".
        ExcludeSemantics(
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: MnemosSpacing.xs),
        Text(label, style: MnemosText.caption.copyWith(color: MnemosColors.muted)),
      ],
    );
  }
}

/// Um ladrilho de estatística: sobrancelha, numeral, medidor.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.meter,
    this.color,
  });

  final String label;
  final String value;
  final String? unit;
  final Widget? meter;

  /// A cor do numeral, pela métrica que ele mede — ver a regra em
  /// `tokens.dart`. Nulo é a contagem neutra, em tinta.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      radius: MnemosRadii.card,
      padding: const EdgeInsets.all(MnemosSpacing.lg),
      // O medidor cola na base e o numeral fica no topo: numa fileira de
      // ladrilhos de altura igual, o que sobra de altura tem de virar respiro
      // entre os dois, não um vazio pendurado no rodapé de um deles.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow(label, small: true),
              const SizedBox(height: MnemosSpacing.xs),
              Numeral(value, unit: unit, color: color),
            ],
          ),
          if (meter != null) ...[
            const SizedBox(height: MnemosSpacing.md),
            meter!,
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Marcadores
// ---------------------------------------------------------------------------

/// A pílula coral que diz quantos cards de um baralho vencem hoje.
///
/// Só aparece quando há algo vencendo. Um badge "0 hoje" seria ruído com cara
/// de alerta.
class DueBadge extends StatelessWidget {
  const DueBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: MnemosSpacing.sm, vertical: MnemosSpacing.xs),
      decoration: ShapeDecoration(
        color: MnemosColors.due,
        shape: squircle(MnemosRadii.card),
      ),
      child: Text(
        '$count hoje',
        style: MnemosText.caption.copyWith(
          color: MnemosColors.onDue,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Um chip de filtro ou de escolha — "Todos", "Vencendo", "5", "8", "12".
class MnemosChip extends StatelessWidget {
  const MnemosChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.expand = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Chips de contagem dividem a largura em partes iguais; chips de filtro se
  /// ajustam ao texto.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final chip = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(expand ? MnemosRadii.control : MnemosRadii.card),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: expand ? 0 : MnemosSpacing.md,
          vertical: expand ? MnemosSpacing.md : MnemosSpacing.sm,
        ),
        alignment: expand ? Alignment.center : null,
        decoration: ShapeDecoration(
            color: selected ? MnemosColors.primary : null,
            shape: squircle(expand ? MnemosRadii.control : MnemosRadii.card,
                side: selected
                    ? BorderSide.none
                    : BorderSide(color: MnemosColors.line)),
          ),
        child: Text(
          label,
          style: MnemosText.labelSmall.copyWith(
            color: selected ? MnemosColors.onDark : MnemosColors.muted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            fontSize: expand ? 14 : 13,
          ),
        ),
      ),
    );

    return expand ? Expanded(child: chip) : chip;
  }
}

/// Um dos quatro ladrilhos de origem da tela Criar: tópico, PDF, foto, à mão.
class SourceTile extends StatelessWidget {
  const SourceTile({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        customBorder: squircle(MnemosRadii.card),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: MnemosSpacing.sm,
            vertical: MnemosSpacing.md,
          ),
          decoration: ShapeDecoration(
            color: selected ? MnemosColors.primary : MnemosColors.raised,
            shape: squircle(MnemosRadii.card,
                side: selected
                    ? BorderSide.none
                    : BorderSide(color: MnemosColors.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? MnemosColors.onDark : MnemosColors.primaryDeep,
              ),
              const SizedBox(height: MnemosSpacing.sm),
              Text(
                label,
                style: MnemosText.labelSmall.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? MnemosColors.onDark : MnemosColors.primaryDeep,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Listas
// ---------------------------------------------------------------------------

/// A linha compacta de baralho da tela Hoje: faixa de cor, nome, legenda,
/// badge de vencimento.
class DeckRow extends StatelessWidget {
  const DeckRow({
    super.key,
    required this.name,
    required this.detail,
    required this.accent,
    this.dueCount = 0,
    this.onTap,
  });

  final String name;
  final String detail;
  final Color accent;
  final int dueCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      radius: MnemosRadii.card,
      padding: const EdgeInsets.symmetric(
        horizontal: MnemosSpacing.lg,
        vertical: MnemosSpacing.lg,
      ),
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
              width: 4,
              decoration: ShapeDecoration(
        color: accent,
        shape: squircle(2),
      ),
            ),
            const SizedBox(width: MnemosSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, style: MnemosText.itemTitle),
                  const SizedBox(height: MnemosSpacing.xs),
                  Text(detail, style: MnemosText.caption),
                ],
              ),
            ),
            if (dueCount > 0) ...[
              const SizedBox(width: MnemosSpacing.md),
              DueBadge(count: dueCount),
            ],
          ],
        ),
      ),
    );
  }
}

/// O item de uma lista de cards, dentro de um baralho.
///
/// A variante `due` troca o fundo para o coral pálido: numa lista longa, o que
/// vence hoje precisa se separar do que não vence sem depender de leitura.
class CardTile extends StatelessWidget {
  const CardTile({
    super.key,
    required this.front,
    required this.back,
    this.trailing,
    this.deck,
    this.due = false,
    this.onTap,
  });

  final String front;
  final String back;
  final String? trailing;

  /// De qual baralho o card veio.
  ///
  /// Só a busca usa: dentro de um baralho a resposta é óbvia, e numa lista de
  /// resultados vindos de baralhos diferentes a sua ausência deixava a pessoa
  /// sem saber onde o card que ela achou realmente mora.
  final String? deck;

  final bool due;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      radius: MnemosRadii.control,
      padding: const EdgeInsets.symmetric(
        horizontal: MnemosSpacing.md,
        vertical: MnemosSpacing.md,
      ),
      background: due ? MnemosColors.dueSurface : MnemosColors.raised,
      border: due ? MnemosColors.dueLine : MnemosColors.hairline,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (deck != null) ...[
                  Eyebrow(deck!, small: true),
                  const SizedBox(height: MnemosSpacing.xs),
                ],
                Text(front, style: MnemosText.itemPrompt, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: MnemosSpacing.xs),
                Text(
                  back,
                  style: MnemosText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: MnemosSpacing.md),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(trailing!, style: MnemosText.monoSmall),
            ),
          ],
        ],
      ),
    );
  }
}

/// Um grupo de cards sob uma sobrancelha com ponto colorido e contagem —
/// `● VENCENDO HOJE 2`.
class BucketSection extends StatelessWidget {
  const BucketSection({
    super.key,
    required this.label,
    required this.color,
    required this.children,
    this.detail,
  });

  final String label;
  final Color color;
  final List<Widget> children;

  /// Uma segunda leitura da mesma pilha, quando ela existe e é diferente da
  /// primeira — "2 na fila de hoje" abaixo de "VENCENDO HOJE 3". A contagem
  /// da sobrancelha conta cards; a fila honra o teto diário. Enquanto as duas
  /// apareciam sem se explicar, a tela se contradizia a oito pixels de
  /// distância.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: MnemosSpacing.sm),
            Eyebrow(label),
            const SizedBox(width: MnemosSpacing.sm),
            Text('${children.length}', style: MnemosText.monoSmall),
          ],
        ),
        if (detail != null) ...[
          const SizedBox(height: MnemosSpacing.xs),
          Text(detail!, style: MnemosText.caption),
        ],
        const SizedBox(height: MnemosSpacing.sm),
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const SizedBox(height: MnemosSpacing.sm),
          child,
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Progresso de uma tarefa longa
// ---------------------------------------------------------------------------

/// Onde uma etapa está: já feita, acontecendo agora, ainda por vir.
enum MnemosStepState { done, active, pending }

/// Uma linha da lista de etapas da geração.
///
/// O design mostra as quatro etapas o tempo todo, não só a atual: quem espera
/// quer saber quanto falta, e uma etapa futura visível é essa resposta.
class StepRow extends StatelessWidget {
  const StepRow({
    super.key,
    required this.label,
    required this.state,
    this.detail,
  });

  final String label;
  final MnemosStepState state;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    // O estado da etapa está só na forma do marcador — bolinha cheia, anel,
    // anel apagado. Quem não vê a bolinha ouviria quatro rótulos iguais e
    // nenhuma noção de progresso, então o estado vira palavra aqui.
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$label — ${switch (state) {
        MnemosStepState.done => 'concluída',
        MnemosStepState.active => 'em andamento',
        MnemosStepState.pending => 'ainda não começou',
      }}${detail == null ? '' : ', $detail'}',
      child: _row(),
    );
  }

  Widget _row() {
    return Row(
      children: [
        _marker(),
        const SizedBox(width: MnemosSpacing.md),
        Flexible(
          child: Text(
            label,
          style: MnemosText.body.copyWith(
            color: switch (state) {
              MnemosStepState.done => MnemosColors.muted,
              MnemosStepState.active => MnemosColors.ink,
              MnemosStepState.pending => MnemosColors.faint,
            },
              fontWeight:
                  state == MnemosStepState.active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        if (detail != null) ...[
          const SizedBox(width: MnemosSpacing.sm),
          Text(detail!, style: MnemosText.monoSmall),
        ],
      ],
    );
  }

  Widget _marker() {
    const size = 22.0;
    return switch (state) {
      MnemosStepState.done => Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: MnemosColors.settled,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, size: 13, color: MnemosColors.onDark),
        ),
      MnemosStepState.active => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: MnemosColors.primary, width: 2),
          ),
        ),
      MnemosStepState.pending => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: MnemosColors.line, width: 2),
          ),
        ),
    };
  }
}

/// Uma linha de uma lista agrupada.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.value,
    this.trailing,
    this.onTap,
  });

  /// Obrigatório de propósito. **Se uma linha do grupo tem ícone, todas têm** —
  /// é a regra que Ajustes do iOS segue a ponto de inventar um glifo para itens
  /// que não têm um natural. Sem ela a coluna de texto pula: aqui "Dispositivo"
  /// começava em x≈120 e "Seus dados", logo abaixo, em x≈40. Três linhas do
  /// mesmo grupo, duas margens.
  final IconData icon;
  final String title;
  final String? detail;

  /// O valor à direita, cinza — "America/Sao_Paulo", "1 de 1 disponível".
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MnemosSpacing.lg,
        vertical: MnemosSpacing.md,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: MnemosColors.primary),
          const SizedBox(width: MnemosSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: MnemosText.body),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(detail!, style: MnemosText.caption),
                ],
              ],
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: MnemosSpacing.sm),
            Flexible(
              child: Text(
                value!,
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: MnemosText.caption,
              ),
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: MnemosSpacing.sm),
            trailing!,
          ] else if (onTap != null) ...[
            const SizedBox(width: MnemosSpacing.xs),
            const Icon(Icons.chevron_right, size: 20, color: MnemosColors.fainter),
          ],
        ],
      ),
    );

    return ConstrainedBox(
      // 48 e não 44: o mínimo do iOS é 44 pt, e uma linha com título e apoio
      // passa disso de qualquer forma — o piso é para as que só têm título.
      constraints: const BoxConstraints(minHeight: 48),
      child: onTap == null ? row : InkWell(onTap: onTap, child: row),
    );
  }
}

/// Um grupo de linhas numa superfície só, com um cabeçalho acima.
///
/// A lista *inset grouped* de Ajustes: linhas claras sobre o canvas, separador
/// recuado até a coluna do texto, altura de linha constante. Antes as nove
/// linhas de Configurações flutuavam direto sobre o fundo, sem superfície e sem
/// separador — não dava para saber onde uma terminava e a outra começava, nem
/// quais eram tocáveis (só três das nove levavam a algum lugar).
class SettingGroup extends StatelessWidget {
  const SettingGroup({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: MnemosSpacing.xs,
            bottom: MnemosSpacing.sm,
          ),
          child: Eyebrow(title),
        ),
        DecoratedBox(
          decoration: ShapeDecoration(
            color: MnemosColors.raised,
            shape: squircle(
              MnemosRadii.card,
              side: const BorderSide(color: MnemosColors.line),
            ),
          ),
          child: Column(
            children: [
              for (final (i, child) in children.indexed) ...[
                // O separador começa depois do ícone, nunca na margem: é o que
                // amarra o texto numa coluna só.
                if (i > 0)
                  const Padding(
                    padding: EdgeInsets.only(left: 52),
                    child: Divider(height: 1, thickness: 1),
                  ),
                child,
              ],
            ],
          ),
        ),
      ],
    );
  }
}
