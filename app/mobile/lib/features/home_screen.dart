import 'package:flutter/material.dart';

import '../theme.dart';
import 'decks_screen.dart';
import 'device_screen.dart';
import 'progress_screen.dart';
import 'settings_screen.dart';
import 'today_screen.dart';

/// A casca do aplicativo.
///
/// Quatro destinos numa barra inferior, não uma lista de links. A diferença
/// não é estética: uma lista custa um toque de ida e um de volta para cada
/// troca de contexto, e quem estuda todo dia troca de contexto o tempo todo.
/// Com a barra, qualquer destino está a um toque de qualquer outro.
///
/// O princípio que o app já tinha continua valendo — a Home não acumula
/// métricas, lembretes nem promoção. Ele só deixou de ser implementado como
/// um índice: agora cada aba é a própria tela, e "Hoje" é onde os números
/// moram.
///
/// `IndexedStack` preserva o estado das quatro: voltar para a Biblioteca não
/// recarrega a lista nem perde a rolagem, o que é a razão de usá-lo no lugar
/// de reconstruir a aba a cada troca.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.school_outlined),
      selectedIcon: Icon(Icons.school),
      label: 'Hoje',
    ),
    NavigationDestination(
      icon: Icon(Icons.library_books_outlined),
      selectedIcon: Icon(Icons.library_books),
      label: 'Biblioteca',
    ),
    NavigationDestination(
      icon: Icon(Icons.devices_other_outlined),
      selectedIcon: Icon(Icons.devices_other),
      label: 'Dispositivo',
    ),
    NavigationDestination(
      icon: Icon(Icons.insights_outlined),
      selectedIcon: Icon(Icons.insights),
      label: 'Progresso',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          TodayScreen(embedded: true),
          DecksScreen(),
          DeviceScreen(),
          ProgressScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _destinations,
        backgroundColor: AppColors.ivory,
        indicatorColor: AppColors.mist,
        surfaceTintColor: AppColors.ivory,
        // Rótulos sempre visíveis: um ícone sozinho é um enigma para quem
        // abre o app duas vezes por semana, que é a maioria.
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 68,
      ),
    );
  }
}

/// Abre as configurações. Fica no `AppBar` de cada aba, não na barra inferior:
/// configuração não é um lugar onde se está, é algo que se faz e se fecha.
class SettingsAction extends StatelessWidget {
  const SettingsAction({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Configurações',
      icon: const Icon(Icons.settings_outlined, size: 22),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ),
    );
  }
}
