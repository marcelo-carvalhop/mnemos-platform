import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Um destino da barra de abas.
///
/// Dois ícones e não um: o vazado para o inativo, o preenchido para o ativo.
/// Toda barra de abas da Apple — Fitness, Saúde, App Store, Podcasts — troca a
/// **forma** além da cor. É redundância deliberada: quem não distingue os dois
/// tons ainda distingue as duas silhuetas, e uma barra em que só a cor muda
/// deixa de dizer onde a pessoa está para quem enxerga cor de outro jeito.
typedef MnemosTab = ({IconData icon, IconData activeIcon, String label});

/// A barra de abas do design.
///
/// §design — "barra de abas no lugar do menu". A Home era uma lista de quatro
/// links, o que custava um toque e uma tela inteira para chegar a qualquer
/// lugar; agora os quatro lugares estão sempre visíveis e o toque leva direto.
///
/// Afunda em vez de flutuar: fundo mais escuro que a tela e uma linha em cima,
/// sem sombra. É moldura, não conteúdo.
class MnemosTabBar extends StatelessWidget {
  const MnemosTabBar({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onSelected,
  });

  final List<MnemosTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: MnemosColors.sunken,
        // `hairline` sobre a barra afundada dava 1,11:1 — a linha existia no
        // código e não na tela. `outline` é o tom mais fechado da família e
        // basta para a barra ter uma borda superior de verdade.
        border: Border(top: BorderSide(color: MnemosColors.outline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: MnemosSpacing.sm, bottom: MnemosSpacing.sm),
          child: Row(
            children: [
              for (final (i, tab) in tabs.indexed)
                Expanded(
                  child: _Tab(
                    tab: tab,
                    selected: i == currentIndex,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.tab, required this.selected, required this.onTap});

  final MnemosTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // O inativo estava em `fainter` no valor antigo: 2,74:1 sobre a barra, o
    // que deixava três dos quatro destinos ilegíveis ao mesmo tempo. Agora os
    // dois estados se leem igualmente bem (5,99:1 e 5,88:1) e o que separa um
    // do outro é o que deve separar — o peso da letra e a lavanda do ativo,
    // não o apagamento do resto.
    final color = selected ? MnemosColors.primaryDeep : MnemosColors.faint;

    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: squircle(MnemosRadii.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: MnemosSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 26 contra um rótulo de 11: o glifo domina e a palavra
              // confirma, como na barra do iOS. Em 22/12 os dois tinham quase
              // o mesmo corpo e a barra lia como uma fileira de palavras com
              // desenhinhos.
              Icon(selected ? tab.activeIcon : tab.icon, size: 26, color: color),
              const SizedBox(height: 3),
              Text(
                tab.label,
                style: MnemosText.tab.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
