import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Um destino da barra de abas.
typedef MnemosTab = ({IconData icon, String label});

/// A barra de abas — o mesmo desenho do menu da web no celular
/// (`app/web/src/app/shell/shell.css`, `.tabbar`).
///
/// Cinco lugares: as quatro abas e "Mais", que guarda o que se usa pouco
/// (Dispositivo, Configurações, Sair) numa folha que sobe de baixo. A aba
/// ativa ganha uma pílula atrás do ícone; Criar é a ação e não um lugar, então
/// o ícone dela é sempre um botão marinho no meio da barra.
class MnemosTabBar extends StatelessWidget {
  const MnemosTabBar({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onSelected,
    required this.onMore,
    this.moreSelected = false,
    this.actionIndex,
    this.badges = const {},
  });

  final List<MnemosTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  /// "Mais" não é uma aba: abre a folha.
  final VoidCallback onMore;

  /// Marca "Mais" quando a tela aberta mora dentro dele.
  final bool moreSelected;

  /// A aba desenhada como ação (Criar).
  final int? actionIndex;

  /// Número sobre o ícone, por aba — os cards que vencem, em Hoje.
  final Map<int, int> badges;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: MnemosColors.raised,
        border: Border(top: BorderSide(color: MnemosColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              for (final (i, tab) in tabs.indexed)
                Expanded(
                  child: _Tab(
                    icon: tab.icon,
                    label: tab.label,
                    selected: i == currentIndex && !moreSelected,
                    action: i == actionIndex,
                    badge: badges[i] ?? 0,
                    onTap: () => onSelected(i),
                  ),
                ),
              Expanded(
                child: _Tab(
                  icon: Icons.more_horiz,
                  label: 'Mais',
                  selected: moreSelected,
                  onTap: onMore,
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
  const _Tab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.action = false,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool action;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = action || selected ? MnemosColors.ink : MnemosColors.faint;
    final pill = action
        ? (selected ? MnemosColors.primaryDarkLine : MnemosColors.primary)
        : (selected ? MnemosColors.soft : Colors.transparent);

    return Semantics(
      selected: selected,
      button: true,
      label: badge > 0 ? '$label, $badge vencendo' : label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: SizedBox(
          height: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    width: 44,
                    height: 28,
                    decoration: ShapeDecoration(color: pill, shape: const StadiumBorder()),
                    child: Icon(
                      icon,
                      size: 21,
                      color: action ? MnemosColors.onDark : color,
                    ),
                  ),
                  if (badge > 0)
                    Positioned(
                      top: -5,
                      right: -2,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: const ShapeDecoration(
                          color: MnemosColors.due,
                          shape: StadiumBorder(
                            side: BorderSide(color: MnemosColors.raised, width: 2),
                          ),
                        ),
                        child: Text(
                          badge > 99 ? '99+' : '$badge',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: MnemosFonts.sans,
                            fontSize: 10.5,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            color: MnemosColors.onDue,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: MnemosText.tab.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
