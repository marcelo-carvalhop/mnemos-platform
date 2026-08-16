import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../providers_progress.dart';
import '../theme.dart';

/// Screen `08 Progresso` — §5.11, §9.
///
/// Everything here is measured over the review log. The order is an argument:
/// accumulated memory first, because §2.3 says the headline is what the user
/// keeps, never how many cards they own; then retention, which is the only
/// honest measure of whether the schedule is working; then what is coming,
/// because being ambushed by four hundred cards on a Monday is how people
/// quit. The streak is last on purpose — it is the most motivating number and
/// the least meaningful one.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memory = ref.watch(accumulatedMemoryProvider);
    final retention = ref.watch(retentionProvider);
    final streak = ref.watch(streakProvider);
    final forecast = ref.watch(forecastProvider);
    final heatmap = ref.watch(heatmapProvider);
    final maturity = ref.watch(deckMaturityProvider);
    final graduations = ref.watch(graduationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Estatísticas')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(accumulatedMemoryProvider)
            ..invalidate(retentionProvider)
            ..invalidate(streakProvider)
            ..invalidate(forecastProvider)
            ..invalidate(heatmapProvider)
            ..invalidate(deckMaturityProvider)
            ..invalidate(graduationsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            const Text('Sua memória acumulada',
                style: TextStyle(fontSize: 13, color: AppColors.faint)),
            const SizedBox(height: 6),
            Text(
              memory.valueOrNull?.label ?? '—',
              style: const TextStyle(
                  fontSize: 32, fontWeight: FontWeight.w500, color: AppColors.ink),
            ),
            const SizedBox(height: 4),
            const Text(
              'A soma do quanto cada card ainda dura na sua cabeça.',
              style: TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.faint),
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: 'Retenção (90 dias)',
                    // Null is "nothing answered yet", and showing that as 0%
                    // would tell a new account it gets everything wrong.
                    value: retention.valueOrNull == null
                        ? '—'
                        : '${(retention.value! * 100).round()}%',
                    detail: retention.valueOrNull == null
                        ? 'aparece depois das primeiras respostas'
                        : 'do que você revisou, acertou',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Stat(
                    label: 'Dias seguidos',
                    value: '${streak.valueOrNull ?? 0}',
                    // §9 — two forgiven days a month, because a streak that
                    // breaks on one missed day teaches people to fear the app.
                    detail: 'com dois perdões por mês',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            const _SectionTitle('O que vem por aí'),
            const SizedBox(height: 4),
            const Text(
              'Quantos cards vencem nos próximos 14 dias.',
              style: TextStyle(fontSize: 12, color: AppColors.faint),
            ),
            const SizedBox(height: 14),
            forecast.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('$e'),
              data: (days) => _Forecast(days: days),
            ),
            const SizedBox(height: 30),
            const _SectionTitle('Os últimos três meses'),
            const SizedBox(height: 14),
            heatmap.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('$e'),
              data: (days) => _Heatmap(days: days, now: ref.watch(clockProvider)()),
            ),
            const SizedBox(height: 30),
            const _SectionTitle('Maturidade por baralho'),
            const SizedBox(height: 4),
            // §5.2's correction, carried through: mature, never "concluído".
            const Text(
              'Maduro é um card cujo intervalo já passou de 21 dias.',
              style: TextStyle(fontSize: 12, color: AppColors.faint),
            ),
            const SizedBox(height: 14),
            maturity.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('$e'),
              data: (byDeck) => _Maturity(
                byDeck: byDeck,
                names: {
                  for (final d in ref.watch(decksProvider).valueOrNull ?? []) d.id: d.name,
                },
              ),
            ),
            const SizedBox(height: 30),
            graduations.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (rows) => rows.isEmpty
                  ? const SizedBox.shrink()
                  : _Graduations(count: rows.length),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.detail});

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.faint)),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w500, color: AppColors.navy)),
          const SizedBox(height: 4),
          Text(detail,
              style: const TextStyle(fontSize: 11, height: 1.35, color: AppColors.faint)),
        ],
      ),
    );
  }
}

/// Fourteen bars. Deliberately not a line chart: the question is "is Thursday
/// going to hurt", and a bar answers it at a glance.
class _Forecast extends StatelessWidget {
  const _Forecast({required this.days});

  final Map<String, int> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty || days.values.every((v) => v == 0)) {
      return const Text('Nada vencendo nas próximas duas semanas.',
          style: TextStyle(fontSize: 13, color: AppColors.muted));
    }

    final keys = days.keys.toList()..sort();
    final peak = days.values.reduce((a, b) => a > b ? a : b);

    return SizedBox(
      height: 96,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final key in keys)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      days[key] == 0 ? '' : '${days[key]}',
                      style: const TextStyle(fontSize: 8, color: AppColors.faint),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      height: (60 * (days[key]! / peak)).clamp(2, 60).toDouble(),
                      decoration: BoxDecoration(
                        color: AppColors.navy.withValues(alpha: .85),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(key.substring(8), style: const TextStyle(fontSize: 8, color: AppColors.faint)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Twelve weeks, one square a day.
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.days, required this.now});

  final Map<String, int> days;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final peak = days.values.isEmpty ? 1 : days.values.reduce((a, b) => a > b ? a : b);
    final start = now.subtract(const Duration(days: 83));

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < 84; i++)
          Builder(builder: (context) {
            final day = start.add(Duration(days: i));
            final key = '${day.year.toString().padLeft(4, '0')}-'
                '${day.month.toString().padLeft(2, '0')}-'
                '${day.day.toString().padLeft(2, '0')}';
            final count = days[key] ?? 0;
            return Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: count == 0
                    ? AppColors.hairline
                    : AppColors.navy.withValues(alpha: (.25 + .75 * (count / peak)).clamp(.25, 1)),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
      ],
    );
  }
}

class _Maturity extends StatelessWidget {
  const _Maturity({required this.byDeck, required this.names});

  final Map<String, dynamic> byDeck;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    if (byDeck.isEmpty) {
      // A deck with no cards is not "no decks", and neither is worth a
      // progress bar at 0%.
      return const Text('Ainda não há cards para medir.',
          style: TextStyle(fontSize: 13, color: AppColors.muted));
    }

    return Column(
      children: [
        for (final entry in byDeck.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(names[entry.key] ?? 'Baralho',
                          style: const TextStyle(fontSize: 13.5)),
                    ),
                    Text('${entry.value.mature} de ${entry.value.total} maduros',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.faint)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: entry.value.ratio as double,
                    minHeight: 5,
                    backgroundColor: AppColors.hairline,
                    valueColor: const AlwaysStoppedAnimation(AppColors.navy),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Graduations extends StatelessWidget {
  const _Graduations({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.goodBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.workspace_premium_outlined, color: AppColors.good, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              count == 1
                  ? '1 card passou de seis meses de intervalo'
                  : '$count cards passaram de seis meses de intervalo',
              style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.good),
            ),
          ),
        ],
      ),
    );
  }
}
