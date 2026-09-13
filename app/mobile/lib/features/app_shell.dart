import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/ui.dart';
import 'create/create_screen.dart';
import 'decks_screen.dart';
import 'progress_screen.dart';
import 'today_screen.dart';

/// A casca do aplicativo: quatro abas, sempre visíveis.
///
/// §design — "barra de abas no lugar do menu". Antes, chegar às estatísticas
/// custava abrir a Home e tocar num item de lista; agora custa um toque, e a
/// Home deixou de ser um índice para virar a tela Hoje.
///
/// Usa [IndexedStack] e não um `switch`: trocar de aba não deve descartar a
/// rolagem nem refazer as consultas da aba que você acabou de deixar.
///
/// **Cada aba tem o seu próprio [Navigator].** Sem isso, abrir um baralho a
/// partir da Biblioteca empurrava a tela por cima da casca inteira e a barra
/// desaparecia — como se um baralho fosse outro lugar do app, e não um andar
/// abaixo da Biblioteca. O que deve mesmo cobrir a barra são as tarefas com
/// começo e fim (gerar, revisar o que a IA escreveu, assinar, escrever um
/// card): essas continuam sendo empurradas no navegador raiz.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index = widget.initialIndex;

  static const _tabs = <MnemosTab>[
    (icon: Icons.today_outlined, activeIcon: Icons.today, label: 'Hoje'),
    (
      icon: Icons.library_books_outlined,
      activeIcon: Icons.library_books,
      label: 'Biblioteca'
    ),
    (icon: Icons.add_circle_outline, activeIcon: Icons.add_circle, label: 'Criar'),
    (icon: Icons.insights_outlined, activeIcon: Icons.insights, label: 'Progresso'),
  ];

  final _navigators = [
    for (var i = 0; i < _tabs.length; i++) GlobalKey<NavigatorState>(),
  ];

  void _open(int index) {
    // Tocar na aba onde já se está volta ao topo dela. É o que uma barra de
    // abas promete em todo aplicativo, e sem isso a aba atual seria o único
    // botão da barra que não faz nada.
    if (index == _index) {
      _navigators[index].currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() => _index = index);
  }

  /// O botão voltar do Android, em ordem: primeiro sai da tela de dentro da
  /// aba, depois volta para a primeira aba, e só então sai do app.
  void _back(bool didPop) {
    if (didPop) return;

    final nested = _navigators[_index].currentState;
    if (nested != null && nested.canPop()) {
      nested.pop();
      return;
    }
    if (_index != 0) {
      setState(() => _index = 0);
      return;
    }
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final roots = [
      TodayScreen(onOpenLibrary: () => _open(1)),
      const DecksScreen(),
      const CreateScreen(),
      const ProgressScreen(),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _back(didPop),
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _index,
            children: [
              for (final (i, root) in roots.indexed)
                Navigator(
                  key: _navigators[i],
                  onGenerateRoute: (settings) => MaterialPageRoute<void>(
                    settings: settings,
                    builder: (_) => root,
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: MnemosTabBar(
          tabs: _tabs,
          currentIndex: _index,
          onSelected: _open,
        ),
      ),
    );
  }
}
