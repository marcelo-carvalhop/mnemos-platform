import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../device/device_wifi.dart';
import '../device/terminal_protocol.dart';
import '../device/terminal_sync_service.dart';
import '../providers.dart';
import '../providers_sync.dart';
import '../theme.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  TerminalPairing? _pairing;
  TerminalInfo? _info;
  TerminalNetworkStatus? _network;
  final Set<String> _selectedDecks = {};
  final _ssid = TextEditingController();
  final _wifiPassword = TextEditingController();
  bool _hidePassword = true;
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _ssid.dispose();
    _wifiPassword.dispose();
    if (_pairing != null) unawaited(DeviceWifi.disconnect());
    super.dispose();
  }

  Future<void> _scan() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScannerScreen()),
    );
    if (raw == null || !mounted) return;

    try {
      final pairing = TerminalPairing.parse(raw);
      if (pairing.protocol < 2) {
        throw StateError(
          'Este terminal usa o protocolo v${pairing.protocol}. Atualize o firmware para a linha v0.3 antes do provisionamento Wi-Fi.',
        );
      }
      final currentSsid = await DeviceWifi.currentSsid();
      setState(() {
        _pairing = pairing;
        _info = null;
        _network = null;
        _ssid.text = currentSsid ?? '';
        _message = currentSsid == null
            ? 'QR Code reconhecido. Informe a rede Wi-Fi que o terminal deverá usar.'
            : 'QR Code reconhecido. Confirme a rede Wi-Fi e informe a senha.';
        _messageIsError = false;
      });
    } catch (e) {
      setState(() {
        _message = e.toString().replaceFirst('Bad state: ', '');
        _messageIsError = true;
      });
    }
  }

  bool _backendCanBeProvisioned(Uri uri) {
    final host = uri.host.toLowerCase();
    return host != '10.0.2.2' && host != 'localhost' && host != '127.0.0.1' && host.isNotEmpty;
  }

  Future<void> _configureAndSync() async {
    final pairing = _pairing;
    if (pairing == null) return;
    if (_ssid.text.trim().isEmpty) {
      setState(() {
        _message = 'Informe o SSID da rede Wi-Fi.';
        _messageIsError = true;
      });
      return;
    }
    final wifiPassword = _wifiPassword.text;
    if (wifiPassword.isNotEmpty && (wifiPassword.length < 8 || wifiPassword.length > 63)) {
      setState(() {
        _message = 'A senha Wi-Fi deve ter entre 8 e 63 caracteres, ou ficar vazia para uma rede aberta.';
        _messageIsError = true;
      });
      return;
    }
    if (_selectedDecks.isEmpty) {
      setState(() {
        _message = 'Selecione ao menos um baralho para a biblioteca inicial.';
        _messageIsError = true;
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = 'Preparando a credencial do terminal e iniciando o provisionamento…';
      _messageIsError = false;
    });

    final backendUrl = ref.read(apiBaseUrlProvider);
    String? terminalToken;
    Uri? provisionedBackend;

    // Register while the phone still has normal Internet access. A localhost
    // or 10.0.2.2 URL is intentionally not provisioned because it is an
    // emulator-only alias and cannot be reached by a physical terminal.
    if (_backendCanBeProvisioned(backendUrl)) {
      try {
        final registration = await ref.read(terminalApiProvider).register(
              deviceId: pairing.deviceId,
              model: pairing.model,
              firmware: pairing.firmware,
              deckIds: _selectedDecks,
            );
        terminalToken = registration.deviceToken;
        provisionedBackend = backendUrl;
      } catch (_) {
        // Offline/local study remains valid. The terminal can be reprovisioned
        // later when a backend is available.
      }
    }

    TerminalClient? client;
    try {
      final connected = await DeviceWifi.connect(ssid: pairing.ssid, password: pairing.password);
      if (!connected) {
        throw StateError('O Android não confirmou a conexão temporária com o Mnemos.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
      client = TerminalClient(pairing);
      await client.setClock(DateTime.now());
      final info = await client.info();
      if (info.supportedCardTypes.isNotEmpty && !info.supportedCardTypes.contains('basic')) {
        throw StateError('Este terminal não declara suporte ao tipo de card basic.');
      }
      if (info.supportedContentFormats.isNotEmpty && !info.supportedContentFormats.contains('plain')) {
        throw StateError('Este terminal não declara suporte ao formato de conteúdo plain.');
      }

      await client.provision(
        ssid: _ssid.text.trim(),
        wifiPassword: wifiPassword,
        backendBaseUrl: provisionedBackend,
        deviceToken: terminalToken,
        syncIntervalSeconds: 1800,
      );

      final study = await ref.read(studyServiceProvider.future);
      final service = TerminalSyncService(ref.read(databaseProvider), study);
      final result = await service.synchronize(
        client: client,
        deckIds: _selectedDecks,
        maxCards: info.maxCards,
      );

      TerminalNetworkStatus status = await client.networkStatus();
      for (var i = 0; i < 12 && !status.connected; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        status = await client.networkStatus();
      }

      await client.completePairing();
      await DeviceWifi.disconnect();
      client.close();
      client = null;

      ref.invalidate(queueProvider);
      ref.invalidate(studiedTodayProvider);
      ref.invalidate(accumulatedMemoryProvider);
      ref.invalidate(deckMaturityProvider);

      if (!mounted) return;
      setState(() {
        _busy = false;
        _info = info;
        _network = status;
        _pairing = null;
        final backendText = provisionedBackend == null
            ? ' O backend não foi gravado nesta configuração.'
            : ' O terminal recebeu uma credencial própria para sincronização com o backend.';
        final wifiText = status.connected
            ? ' Terminal conectado à rede ${status.ssid ?? _ssid.text.trim()}.'
            : ' As credenciais Wi-Fi foram gravadas, mas a conexão ainda não foi confirmada.';
        _message = '${result.sentCards} cartões enviados e ${result.importedReviews} revisões importadas.$wifiText$backendText';
        _messageIsError = !status.connected;
      });
    } catch (e) {
      client?.close();
      await DeviceWifi.disconnect();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = e.toString().replaceFirst('Bad state: ', '');
        _messageIsError = true;
      });
    }
  }

  void _reset() {
    setState(() {
      _pairing = null;
      _info = null;
      _network = null;
      _selectedDecks.clear();
      _wifiPassword.clear();
      _message = null;
      _messageIsError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider);
    final pairing = _pairing;

    return Scaffold(
      appBar: AppBar(title: const Text('Terminal Mnemos')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.fill,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Configuração do terminal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text(
                  'O QR Code abre uma conexão temporária. O celular transfere a rede Wi-Fi, a biblioteca inicial e, quando disponível, uma credencial restrita de backend. Depois o terminal encerra o ponto de acesso e permanece na rede configurada.',
                  style: TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                if (pairing == null)
                  FilledButton.icon(
                    onPressed: _busy ? null : _scan,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Escanear QR Code do terminal'),
                  )
                else ...[
                  Text(pairing.deviceId, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${pairing.model} · firmware ${pairing.firmware} · protocolo ${pairing.protocol}',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _ssid,
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: 'Rede Wi-Fi (SSID)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _wifiPassword,
                    enabled: !_busy,
                    obscureText: _hidePassword,
                    decoration: InputDecoration(
                      labelText: 'Senha da rede Wi-Fi',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _hidePassword = !_hidePassword),
                        icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'A senha é enviada apenas durante o provisionamento e não é recuperada automaticamente do Android.',
                    style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.muted),
                  ),
                ],
              ],
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _messageIsError ? AppColors.againBg : AppColors.mist,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(_message!, style: TextStyle(height: 1.4, color: _messageIsError ? AppColors.terracotta : AppColors.graphite)),
            ),
          ],
          if (pairing != null) ...[
            const SizedBox(height: 26),
            const Text('Biblioteca inicial', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text(
              'Selecione os baralhos que serão gravados no terminal durante esta configuração. Depois, um backend compatível pode manter o dispositivo atualizado diretamente pela rede Wi-Fi.',
              style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            decks.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('$e'),
              data: (rows) => Column(
                children: [
                  for (final deck in rows)
                    CheckboxListTile(
                      value: _selectedDecks.contains(deck.id),
                      activeColor: AppColors.petrol,
                      checkColor: AppColors.ivory,
                      contentPadding: EdgeInsets.zero,
                      title: Text(deck.name),
                      subtitle: deck.description == null ? null : Text(deck.description!),
                      onChanged: _busy
                          ? null
                          : (checked) => setState(() {
                                if (checked == true) {
                                  _selectedDecks.add(deck.id);
                                } else {
                                  _selectedDecks.remove(deck.id);
                                }
                              }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _configureAndSync,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.settings_input_antenna),
              label: Text(_busy ? 'Configurando…' : 'Configurar e sincronizar'),
            ),
            TextButton(onPressed: _busy ? null : _reset, child: const Text('Cancelar configuração')),
          ],
          if (_info != null) ...[
            const SizedBox(height: 24),
            Text(
              _network?.connected == true
                  ? 'Configuração concluída. O terminal está online e já não depende do celular.'
                  : 'Configuração concluída parcialmente. O terminal pode continuar estudando offline e tentar a rede novamente.',
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _reset, child: const Text('Configurar outro terminal')),
          ],
        ],
      ),
    );
  }
}

class _QrScannerScreen extends StatefulWidget {
  const _QrScannerScreen();

  @override
  State<_QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<_QrScannerScreen> {
  var _returned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ler QR Code do Mnemos')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_returned) return;
              for (final code in capture.barcodes) {
                final raw = code.rawValue;
                if (raw == null || !raw.startsWith('mnemos://pair?')) continue;
                _returned = true;
                Navigator.of(context).pop(raw);
                return;
              }
            },
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.brass, width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 36,
            child: Text(
              'Mantenha o QR Code do terminal dentro da moldura.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.ivory, fontSize: 14, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 8, color: AppColors.graphite)]),
            ),
          ),
        ],
      ),
    );
  }
}
