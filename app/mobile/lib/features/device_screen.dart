import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/terminal_local_store.dart';
import '../providers.dart';
import '../theme.dart';
import 'device_sync_screen.dart';
import 'home_screen.dart' show SettingsAction;
import 'terminal_screen.dart';

/// Identity and connection entry point for the dedicated terminal.
/// Content selection belongs to DeviceSyncScreen, not here.
class DeviceScreen extends ConsumerStatefulWidget {
  const DeviceScreen({super.key});

  @override
  ConsumerState<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends ConsumerState<DeviceScreen> {
  StoredTerminal? _terminal;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final terminal = await TerminalLocalStore(ref.read(databaseProvider)).activeTerminal();
    if (!mounted) return;
    setState(() {
      _terminal = terminal;
      _loading = false;
    });
  }

  Future<void> _openConnection() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TerminalScreen()),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispositivo'),
        actions: [
          // A sincronização deixou de ser um destino da Home: ela é sobre este
          // aparelho, e é aqui que quem pensa nele já está.
          IconButton(
            tooltip: 'Sincronização',
            icon: const Icon(Icons.sync_outlined, size: 22),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DeviceSyncScreen()),
            ),
          ),
          const SettingsAction(),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
              children: [
                if (_terminal == null) ...[
                  const Text('Nenhum Mnemos configurado.'),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _openConnection,
                    child: const Text('Conectar um Mnemos'),
                  ),
                ] else ...[
                  Text(
                    _terminal!.model,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(_terminal!.deviceId, style: const TextStyle(color: AppColors.sage)),
                  const SizedBox(height: 28),
                  _Row(label: 'Firmware', value: _terminal!.firmware),
                  _Row(label: 'Protocolo', value: 'v${_terminal!.protocol}'),
                  _Row(label: 'Capacidade', value: '${_terminal!.maxCards} cards'),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _openConnection,
                    child: const Text('Configurar conexão'),
                  ),
                ],
              ],
            ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: AppColors.sage))),
            Flexible(child: Text(value, textAlign: TextAlign.right)),
          ],
        ),
      );
}
