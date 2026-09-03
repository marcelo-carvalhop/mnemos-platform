import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../providers.dart';
import '../providers_progress.dart';
import '../providers_today.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../ui/ui.dart';
import 'deck_detail_screen.dart';
import 'device_screen.dart';
import 'settings_screen.dart';

/// O painel do dia — artboard 01.
///
/// §design — "a Início vira o painel do dia". A Home antiga era um índice de
/// quatro links que não dizia nada; esta tela responde à única pergunta que
/// alguém abre o app para fazer: **o que preciso fazer hoje, e o meu terminal
/// está com isso?**
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key, required this.onOpenLibrary});

  /// "Ver todos" troca de aba em vez de empilhar uma tela: a Biblioteca já é
  /// um destino da barra, e empurrá-la por cima criaria duas rotas para o
  /// mesmo lugar.
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();

    return ScreenBody(
      children: [
        ScreenHeader(
          eyebrow: longDate(now),
          title: 'Hoje',
          trailing: RoundAction(
            icon: Icons.settings_outlined,
            tooltip: 'Configurações',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ),
        const SizedBox(height: MnemosSpacing.xl),
        const _DueHero(),
        const SizedBox(height: MnemosSpacing.md),
        const _StatRow(),
        const SizedBox(height: MnemosSpacing.xxl),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Text('Seus baralhos', style: MnemosText.sectionTitle),
            const Spacer(),
            TextButton(
              onPressed: onOpenLibrary,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Ver todos'),
            ),
          ],
        ),
        const SizedBox(height: MnemosSpacing.md),
        const _DeckList(),
      ],
    );
  }
}

/// O bloco-âncora lavanda: quanto vence agora e o estado do terminal.
class _DueHero extends ConsumerWidget {
  const _DueHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = ref.watch(dueTodayProvider);
    final hasCards = ref.watch(hasAnyCardsProvider).valueOrNull ?? false;
    final lastSync = ref.watch(terminalLastSyncProvider).valueOrNull;
    final terminal = ref.watch(activeTerminalProvider).valueOrNull;
    final now = ref.watch(clockProvider)();

    final cards = due.valueOrNull?.cards ?? 0;
    final decks = due.valueOrNull?.decks ?? 0;

    // §5.1, §5.2 — "nada vencendo" e "nada existe" são frases diferentes, e
    // dizer a primeira a quem nunca criou um card é mentir sobre o motivo do
    // silêncio.
    final (eyebrow, headline, detail) = switch ((hasCards, cards)) {
      (false, _) => ('comece por aqui', '0', 'nenhum card ainda'),
      (true, 0) => ('nada vencendo', '0', 'sua memória segue trabalhando'),
      _ => ('vencendo agora', '$cards', 'cards em ${plural(decks, 'baralho', 'baralhos')}'),
    };

    return HeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(eyebrow, color: MnemosColors.onPrimaryMuted),
          const SizedBox(height: MnemosSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(headline, style: MnemosText.heroNumeral),
              const SizedBox(width: MnemosSpacing.sm),
              Expanded(
                child: Text(
                  detail,
                  style: MnemosText.body.copyWith(
                    fontSize: 16,
                    color: MnemosColors.onPrimarySoft,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MnemosSpacing.lg),
          Container(height: 1, color: MnemosColors.onDark.withValues(alpha: 0.18)),
          const SizedBox(height: MnemosSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Text(
                  // §M1 — o aparelho tem um nome só. "Nenhum Mnemos conectado"
                  // era literalmente o nome do produto negando a si mesmo:
                  // dava para ler como "este app não está conectado".
                  terminal == null
                      ? 'Nenhum Mnemos T5 conectado'
                      : 'T5 ${relativeSince(lastSync, now) == null ? 'ainda não sincronizou' : 'sincronizado ${relativeSince(lastSync, now)}'}',
                  style: MnemosText.bodySmall.copyWith(color: MnemosColors.onPrimarySoft),
                ),
              ),
              const SizedBox(width: MnemosSpacing.md),
              _HeroButton(
                label: terminal == null ? 'Conectar' : 'Enviar ao T5',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DeviceScreen()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// O botão claro sobre o bloco lavanda. Inverte as cores do primário porque
/// sobre lavanda o primário desapareceria.
class _HeroButton extends StatelessWidget {
  const _HeroButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: squircle(MnemosRadii.control),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: MnemosSpacing.lg,
          vertical: MnemosSpacing.md,
        ),
        decoration: ShapeDecoration(
        color: MnemosColors.onDark,
        shape: squircle(MnemosRadii.control),
      ),
        child: Text(
          label,
          style: MnemosText.labelSmall.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: MnemosColors.primaryDeep,
          ),
        ),
      ),
    );
  }
}

/// Os dois ladrilhos: sequência e retenção.
class _StatRow extends ConsumerWidget {
  const _StatRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(streakProvider).valueOrNull;
    final retention = ref.watch(retentionProvider).valueOrNull;

    // `IntrinsicHeight` + `stretch`: os dois ladrilhos tinham 40 px de degrau
    // na base porque cada um crescia com o próprio conteúdo. Numa fileira de
    // dois, o degrau é a primeira coisa que o olho pega — os ladrilhos do
    // resumo do Fitness têm sempre a mesma altura, e é o conteúdo mais curto
    // que ganha espaço, não a fileira que ganha um dente.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        Expanded(
          child: StatTile(
            label: 'sequência',
            value: '${streak ?? 0}',
            unit: 'dias',
            meter: const _WeekStrip(),
          ),
        ),
        const SizedBox(width: MnemosSpacing.md),
        Expanded(
          child: StatTile(
            label: 'retenção 90 d',
            // Menta: a cor é da métrica, não da tela — ver a regra em
            // `tokens.dart`.
            color: MnemosColors.settledDeep,
            value: retention == null ? '—' : '${(retention * 100).round()}',
            unit: retention == null ? null : '%',
            meter: MeterBar(
              fraction: retention ?? 0,
              color: MnemosColors.settled,
              semanticLabel: retention == null
                  ? 'Retenção em 90 dias ainda desconhecida'
                  : 'Retenção em 90 dias: ${(retention * 100).round()}%',
            ),
          ),
        ),
        ],
      ),
    );
  }
}

/// Os sete tracinhos da última semana, com o dia embaixo de cada um.
///
/// Não é enfeite do número da sequência: mostra **quais** dias contaram, que é
/// o que deixa "19 dias" verificável em vez de assertivo.
///
/// Os rótulos S T Q Q S S D não são cosméticos. Sem eles, sete traços dos
/// quais um está vazio se leem como "a sequência quebrou" — que é o oposto do
/// número ao lado. Com eles, o traço vazio é uma terça-feira, e hoje ganha
/// contorno em vez de ficar vazio: um dia que ainda não terminou não é um dia
/// perdido.
class _WeekStrip extends ConsumerWidget {
  const _WeekStrip();

  /// Iniciais em português, indexadas por `DateTime.weekday` (1 = segunda).
  static const _initials = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heatmap = ref.watch(heatmapProvider).valueOrNull ?? const <String, int>{};
    final goal = ref.watch(dailyGoalProvider).valueOrNull ?? 20;
    final day = ref.watch(dayBucketProvider).valueOrNull;
    final now = ref.watch(clockProvider)();

    var studied = 0;
    for (var back = 6; back >= 0; back--) {
      if (_answered(heatmap, day, now, back) > 0) studied++;
    }

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'Últimos sete dias: estudou em $studied deles.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sem `stretch`: cada traço já tem altura própria, e esticar numa
          // Row sem altura definida pede altura infinita ao filho.
          Row(
            children: [
              for (var back = 6; back >= 0; back--) ...[
                if (back < 6) const SizedBox(width: MnemosSpacing.xs),
                Expanded(child: SizedBox(height: 6, child: _mark(heatmap, day, now, back, goal))),
              ],
            ],
          ),
          const SizedBox(height: MnemosSpacing.xs),
          Row(
            children: [
              for (var back = 6; back >= 0; back--) ...[
                if (back < 6) const SizedBox(width: MnemosSpacing.xs),
                Expanded(
                  child: Text(
                    _initials[now.subtract(Duration(days: back)).weekday - 1],
                    textAlign: TextAlign.center,
                    style: MnemosText.monoSmall.copyWith(
                      fontSize: 9,
                      color: back == 0 ? MnemosColors.muted : MnemosColors.faint,
                      fontWeight: back == 0 ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  int _answered(Map<String, int> heatmap, dynamic day, DateTime now, int daysBack) {
    if (day == null) return 0;
    final key = day.today(now.subtract(Duration(days: daysBack))) as String;
    return heatmap[key] ?? 0;
  }

  Widget _mark(
    Map<String, int> heatmap,
    dynamic day,
    DateTime now,
    int daysBack,
    int goal,
  ) {
    final answered = _answered(heatmap, day, now, daysBack);

    // Hoje sem a meta batida é um contorno, não um vazio: o dia ainda está
    // acontecendo, e desenhá-lo igual a uma terça perdida é dar por encerrado
    // algo que a pessoa ainda pode fazer nos próximos minutos.
    if (daysBack == 0 && answered < goal) {
      return DecoratedBox(
        decoration: ShapeDecoration(
        color: answered > 0 ? MnemosColors.primary40 : null,
        shape: squircle(MnemosRadii.bar, side: BorderSide(color: MnemosColors.primary, width: 1.5)),
      ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: switch (answered) {
          // Hoje em menta: a meta batida hoje é a única que ainda pode mudar.
          _ when answered >= goal => daysBack == 0 ? MnemosColors.settled : MnemosColors.primary,
          > 0 => MnemosColors.primary40,
          _ => MnemosColors.line,
        },
        borderRadius: BorderRadius.circular(MnemosRadii.bar),
      ),
    );
  }
}

/// A lista de baralhos com o que vence em cada um.
class _DeckList extends ConsumerWidget {
  const _DeckList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = ref.watch(decksProvider).valueOrNull ?? const [];
    final counts = ref.watch(deckCardCountsProvider).valueOrNull ?? const {};
    final maturity = ref.watch(deckMaturityProvider).valueOrNull ?? const {};
    final due = ref.watch(dueByDeckProvider).valueOrNull ?? const {};

    if (decks.isEmpty) {
      return const SurfaceCard(
        child: Text(
          'Nenhum baralho ainda. Crie o primeiro na aba Criar.',
          style: MnemosText.bodySmall,
        ),
      );
    }

    // Três é o teto desta lista: Hoje é um painel, não a Biblioteca. "Ver
    // todos" existe justamente para não transformar uma numa cópia da outra.
    //
    // E os três são os de maior fila, não os três primeiros da Biblioteca:
    // cortar por ordem alfabética faz o painel dizer "15 cards em 4 baralhos"
    // e listar logo abaixo três baralhos sem nada vencendo — a tela
    // contradizendo o próprio número. Empate mantém a ordem da Biblioteca.
    final ordered = [...decks]..sort((a, b) {
      final byDue = (due[b.id] ?? 0).compareTo(due[a.id] ?? 0);
      return byDue != 0 ? byDue : decks.indexOf(a).compareTo(decks.indexOf(b));
    });
    final shown = ordered.take(3).toList();

    return Column(
      children: [
        for (final (i, deck) in shown.indexed) ...[
          if (i > 0) const SizedBox(height: MnemosSpacing.sm),
          DeckRow(
            name: deck.name,
            detail: '${plural(counts[deck.id] ?? 0, 'card', 'cards')}'
                ' · ${maturity[deck.id]?.mature ?? 0} maduros',
            accent: (due[deck.id] ?? 0) > 0 ? MnemosColors.primary : MnemosColors.settled,
            dueCount: due[deck.id] ?? 0,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DeckDetailScreen(deckId: deck.id, deckName: deck.name),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
