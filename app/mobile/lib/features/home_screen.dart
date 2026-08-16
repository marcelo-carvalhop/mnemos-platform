import 'package:flutter/material.dart';

import '../theme.dart';
import 'decks_screen.dart';
import 'device_screen.dart';
import 'device_sync_screen.dart';
import 'progress_screen.dart';
import 'settings_screen.dart';

/// Home is navigation only. No statistics, reminders, streaks, study queue or
/// promotional content belongs here.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mnemos'),
        actions: [
          IconButton(
            tooltip: 'Configurações',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          _Destination(
            title: 'Biblioteca',
            icon: Icons.library_books_outlined,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DecksScreen()),
            ),
          ),
          _Destination(
            title: 'Dispositivo',
            icon: Icons.devices_other_outlined,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DeviceScreen()),
            ),
          ),
          _Destination(
            title: 'Sincronização',
            icon: Icons.sync_outlined,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DeviceSyncScreen()),
            ),
          ),
          _Destination(
            title: 'Estatísticas',
            icon: Icons.insights_outlined,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProgressScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _Destination extends StatelessWidget {
  const _Destination({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(
          children: [
            Icon(icon, color: AppColors.petrol, size: 23),
            const SizedBox(width: 16),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
            const Icon(Icons.chevron_right, color: AppColors.sage),
          ],
        ),
      ),
    );
  }
}
