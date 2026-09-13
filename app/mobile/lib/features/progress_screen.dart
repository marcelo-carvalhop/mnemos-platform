import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../providers_progress.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../ui/ui.dart';

/// Progresso — artboard 07.
///
/// §9 — uma métrica de cabeçalho só: memória acumulada. Retenção e sequência
/// entram como apoio, dentro do mesmo bloco, e não como cartões concorrentes.
/// O resto da tela responde "o que vem" e "o que já está firme", nunca
/// "quanto você se esforçou".
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScreenBody(
      children: [
        const Text('Progresso', style: MnemosText.screenTitle),
        const SizedBox(height: MnemosSpacing.lg),
        const _MemoryCard(),
        const SizedBox(height: MnemosSpacing.xl),
        _Forecast(),
        const SizedBox(height: MnemosSpacing.xl),
        _Heatmap(),
        const SizedBox(height: MnemosSpacing.xl),
        const _Maturity(),
      ],
    );
  }
}

/// O bloco-âncora: memória acumulada, com retenção e sequência por baixo.
class _MemoryCard extends ConsumerWidget {
  const _MemoryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memory = ref.watch(accumulatedMemoryProvider).valueOrNull;
    final retention = ref.watch(retentionProvider).valueOrNull;
    final streak = ref.watch(streakProvider).valueOrNull;

    // "1 mês" chega como uma frase; o design quer o número em corpo grande e a
    // unidade menor ao lado, então parte na primeira lacuna.
    final label = memory?.label ?? '—';
    final space = label.indexOf(' ');
    final (value, unit) =
        space < 0 ? (label, '') : (label.substring(0, space), label.substring(space + 1));

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('memória acumulada'),
          const SizedBox(height: MnemosSpacing.xs),
          Numeral(
            value,
            unit: unit.isEmpty ? null : unit,
            // Lavanda: memória acumulada é a manchete do produto, e a regra de
            // cor por métrica está em `tokens.dart`.
            style: MnemosText.numeralLarge.copyWith(color: MnemosColors.primaryDeep),
            unitStyle: MnemosText.numeralUnit,
          ),
          const SizedBox(height: MnemosSpacing.sm),
          const Text(
            'A soma do quanto cada card ainda dura na sua cabeça.',
            style: MnemosText.bodySmall,
          ),
          const SizedBox(height: MnemosSpacing.md),
          const Divider(),
          const SizedBox(height: MnemosSpacing.md),
          IntrinsicHeight(
            child: Row(
              children: [
                _Sub(
                  color: MnemosColors.settledDeep,
                  value: retention == null ? '—' : '${(retention * 100).round()}',
                  unit: retention == null ? '' : '%',
                  detail: 'retenção em 90 dias',
                ),
                const VerticalDivider(width: MnemosSpacing.xl),
                _Sub(
                  value: '${streak ?? 0}',
                  unit: 'dias',
                  // §9 — dois perdões por mês, porque uma sequência que quebra
                  // num dia perdido ensina a ter medo do app.
                  detail: 'seguidos, 2 perdões/mês',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sub extends StatelessWidget {
  const _Sub({
    required this.value,
    required this.unit,
    required this.detail,
    this.color = MnemosColors.ink,
  });

  final String value;
  final String unit;
  final String detail;

  /// A cor pela métrica — ver a regra em `tokens.dart`.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Numeral(
            value,
            unit: unit.isEmpty ? null : unit,
            style: MnemosText.numeralSmall.copyWith(color: color),
          ),
          const SizedBox(height: MnemosSpacing.xs),
          Text(detail, style: MnemosText.caption),
        ],
      ),
    );
  }
}

/// "O que vem por aí" — quantos cards vencem nos próximos catorze dias.
class _Forecast extends ConsumerWidget {
  static const _horizon = 14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(forecastProvider).valueOrNull ?? const <String, int>{};
    final day = ref.watch(dayBucketProvider).valueOrNull;
    final now = ref.watch(clockProvider)();
    if (day == null) return const SizedBox.shrink();

    // Catorze dias corridos, e não só os dias que têm carga.
    //
    // A versão anterior jogava fora os dias vazios e espaçava o que sobrava
    // por igual: 31, 01, 02, 04, 05, 08 lado a lado, com a distância de 05
    // para 08 desenhada igual à de 01 para 02. O eixo dizia "os seus dias são
    // assim distribuídos" quando a distribuição era outra — e é exatamente a
    // distribuição que a pessoa veio ver. Um dia sem nada agora é uma coluna
    // de altura zero, que é a informação verdadeira.
    final days = [
      for (var i = 0; i < _horizon; i++)
        (
          date: now.add(Duration(days: i)),
          count: counts[day.today(now.add(Duration(days: i)))] ?? 0,
        ),
    ];
    final total = days.fold(0, (sum, d) => sum + d.count);
    final peak = days.fold(0, (best, d) => d.count > best ? d.count : best);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Text('O que vem por aí', style: MnemosText.sectionTitle),
            const Spacer(),
            const Eyebrow('14 dias', small: true),
          ],
        ),
        const SizedBox(height: MnemosSpacing.md),
        if (total == 0)
          const Text('Nada vencendo nas próximas duas semanas.', style: MnemosText.bodySmall)
        else
          Semantics(
            container: true,
            excludeSemantics: true,
            label: '$total cards vencem nos próximos 14 dias. '
                'O dia mais carregado tem $peak.',
            child: _Bars(days: days, peak: peak),
          ),
      ],
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.days, required this.peak});

  final List<({DateTime date, int count})> days;
  final int peak;

  static const _tall = 64.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final (i, day) in days.indexed) ...[
          if (i > 0) const SizedBox(width: 2),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  day.count == 0 ? '' : '${day.count}',
                  style: MnemosText.monoSmall.copyWith(fontSize: 9),
                ),
                const SizedBox(height: MnemosSpacing.xs),
                Container(
                  // Um dia vazio ainda desenha um traço de 2px: é o eixo, e
                  // sem ele a lacuna viraria de novo um dia que não existe.
                  height: day.count == 0 ? 2 : (_tall * (day.count / peak)).clamp(6, _tall),
                  decoration: BoxDecoration(
                    // A coluna mais alta em lavanda cheia; as demais mais
                    // claras. O pico é a informação — é o dia que dói.
                    color: switch (day.count) {
                      0 => MnemosColors.line,
                      _ when day.count == peak => MnemosColors.primary,
                      _ => MnemosColors.primary60,
                    },
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(MnemosRadii.bar),
                      bottom: Radius.circular(MnemosRadii.bar),
                    ),
                  ),
                ),
                const SizedBox(height: MnemosSpacing.xs),
                // Um rótulo a cada dois dias: catorze números de dois dígitos
                // lado a lado num telefone se encostam e viram uma tarja.
                Text(
                  i.isEven ? '${day.date.day}'.padLeft(2, '0') : '',
                  style: MnemosText.monoSmall.copyWith(fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// O mapa de calor dos últimos três meses.
class _Heatmap extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(heatmapProvider).valueOrNull ?? const <String, int>{};
    final day = ref.watch(dayBucketProvider).valueOrNull;
    final now = ref.watch(clockProvider)();
    if (day == null) return const SizedBox.shrink();

    final peak = days.values.isEmpty ? 1 : days.values.reduce((a, b) => a > b ? a : b);
    final start = now.subtract(const Duration(days: 83));
    final studied = days.values.where((n) => n > 0).length;
    final answered = days.values.fold(0, (sum, n) => sum + n);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Últimos três meses', style: MnemosText.sectionTitle),
        const SizedBox(height: MnemosSpacing.md),
        // Oitenta e quatro quadradinhos coloridos são, para um leitor de tela,
        // oitenta e quatro nadas. O resumo em texto é a mesma resposta que o
        // desenho dá ao olho: quanto e em quantos dias.
        Semantics(
          container: true,
          excludeSemantics: true,
          label: 'Mapa dos últimos três meses: $answered cards respondidos '
              'em $studied dias de 84.',
          child: Row(
            children: [
              for (var week = 0; week < 12; week++) ...[
                if (week > 0) const SizedBox(width: MnemosSpacing.xs),
                Expanded(
                  child: Column(
                    children: [
                      for (var weekday = 0; weekday < 7; weekday++) ...[
                        if (weekday > 0) const SizedBox(height: MnemosSpacing.xs),
                        _cell(days, day, start, week * 7 + weekday, peak),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: MnemosSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final month in _monthsSpanned(now))
              Text(month, style: MnemosText.monoSmall.copyWith(fontSize: 10)),
          ],
        ),
      ],
    );
  }

  /// Os três meses que a faixa cobre, do mais antigo ao atual.
  List<String> _monthsSpanned(DateTime now) {
    const names = [
      'JAN', 'FEV', 'MAR', 'ABR', 'MAI', 'JUN',
      'JUL', 'AGO', 'SET', 'OUT', 'NOV', 'DEZ',
    ];
    return [
      for (var back = 2; back >= 0; back--)
        names[DateTime(now.year, now.month - back).month - 1],
    ];
  }

  Widget _cell(
    Map<String, int> days,
    dynamic day,
    DateTime start,
    int offset,
    int peak,
  ) {
    final key = day.today(start.add(Duration(days: offset))) as String;
    final count = days[key] ?? 0;
    final intensity = count == 0 ? 0.0 : (count / peak).clamp(0.25, 1.0);

    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: switch (intensity) {
          0.0 => MnemosColors.hairline,
          < 0.4 => MnemosColors.primary40,
          < 0.7 => MnemosColors.primary60,
          _ => MnemosColors.primary,
        },
        borderRadius: BorderRadius.circular(MnemosRadii.bar),
      ),
    );
  }
}

/// "Maturidade por baralho" — quanto de cada baralho já passou de 21 dias.
class _Maturity extends ConsumerWidget {
  const _Maturity();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = ref.watch(decksProvider).valueOrNull ?? const [];
    final maturity = ref.watch(deckMaturityProvider).valueOrNull ?? const {};
    if (decks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Maturidade por baralho', style: MnemosText.sectionTitle),
        const SizedBox(height: 4),
        const Text(
          'Maduro é um card cujo intervalo já passou de 21 dias.',
          style: MnemosText.bodySmall,
        ),
        const SizedBox(height: MnemosSpacing.md),
        for (final (i, deck) in decks.indexed) ...[
          if (i > 0) const SizedBox(height: MnemosSpacing.md),
          _MaturityRow(
            name: deck.name,
            mature: maturity[deck.id]?.mature ?? 0,
            total: maturity[deck.id]?.total ?? 0,
          ),
        ],
      ],
    );
  }
}

class _MaturityRow extends StatelessWidget {
  const _MaturityRow({required this.name, required this.mature, required this.total});

  final String name;
  final int mature;
  final int total;

  @override
  Widget build(BuildContext context) {
    // Uma barra 100% vazia não comunica zero: comunica "aqui tem uma barra" e
    // parece um divisor. Com nenhum card maduro, a frase é a informação —
    // inclusive porque ela pode dizer *por que* ainda não há nenhum.
    if (mature == 0) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              name,
              style: MnemosText.body.copyWith(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: MnemosSpacing.md),
          Text(
            total == 0 ? 'sem cards' : 'nenhum maduro ainda',
            style: MnemosText.caption,
          ),
        ],
      );
    }

    final ratio = total == 0 ? 0.0 : mature / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: MnemosText.body.copyWith(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text('$mature/$total', style: MnemosText.mono),
          ],
        ),
        const SizedBox(height: MnemosSpacing.xs),
        MeterBar(
          fraction: ratio,
          semanticLabel: '$name: $mature de $total cards maduros.',
          color: ratio >= 0.5 ? MnemosColors.settled : MnemosColors.primary,
          track: MnemosColors.line,
          height: 7,
        ),
      ],
    );
  }
}
