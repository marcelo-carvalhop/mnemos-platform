import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../device/device_wifi.dart';
import '../device/terminal_local_store.dart';
import '../device/terminal_protocol.dart';
import '../providers.dart';
import '../providers_sync.dart';
import '../theme.dart';

/// Connection-only screen.
///
/// Content selection deliberately does not live here. This screen identifies
/// the device, gives it one network profile and a restricted backend token,
/// then leaves content reconciliation to DeviceSyncScreen.
class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  TerminalPairing? _pairing;
  List<WifiNetwork> _wifiNetworks = const [];
  WifiNetwork? _selectedNetwork;
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  final _identity = TextEditingController();
  final _username = TextEditingController();
  bool _hidePassword = true;
  String _manualSecurityType = 'personal';
  bool _busy = false;
  bool _scanningWifi = false;
  String? _message;
  bool _error = false;

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    _identity.dispose();
    _username.dispose();
    if (_pairing != null) unawaited(DeviceWifi.disconnect());
    super.dispose();
  }

  String _friendly(Object error) {
    if (error is PlatformException) return error.message ?? 'Falha da plataforma (${error.code}).';
    var text = error.toString();
    for (final prefix in const ['Bad state: ', 'FormatException: ']) {
      if (text.startsWith(prefix)) text = text.substring(prefix.length);
    }
    return text;
  }

  Future<void> _scanQr() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScannerScreen()),
    );
    if (raw == null || !mounted) return;
    try {
      final pairing = TerminalPairing.parse(raw);
      setState(() {
        _pairing = pairing;
        _message = 'Terminal identificado. Escolha a rede que ele deverá conhecer.';
        _error = false;
      });
      await _scanWifi();
    } catch (e) {
      setState(() {
        _message = _friendly(e);
        _error = true;
      });
    }
  }

  Future<void> _scanWifi() async {
    if (_scanningWifi) return;
    setState(() => _scanningWifi = true);
    try {
      final networks = await DeviceWifi.scanNetworks();
      final current = await DeviceWifi.currentSsid();
      if (!mounted) return;
      final preferred = current == null ? null : networks.where((n) => n.ssid == current).firstOrNull;
      setState(() {
        _wifiNetworks = networks;
        _selectedNetwork = preferred;
        if (preferred != null) _ssid.text = preferred.ssid;
        _scanningWifi = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanningWifi = false;
        _message = '${_friendly(e)} O SSID ainda pode ser informado manualmente.';
        _error = false;
      });
    }
  }

  Map<String, Object?> _networkProfile() {
    final ssid = _ssid.text.trim();
    if (ssid.isEmpty) throw StateError('Informe o SSID da rede.');
    final selected = _selectedNetwork;
    if (selected != null && selected.ssid == ssid && !selected.compatibleWithCurrentTerminal) {
      if (!selected.has24GHz) {
        throw StateError('A rede $ssid foi encontrada apenas em 5/6 GHz. Este terminal precisa de uma variante 2,4 GHz.');
      }
      throw StateError('O tipo de segurança anunciado por $ssid ainda não é suportado por este terminal.');
    }

    final id = 'wifi-${base64Url.encode(utf8.encode(ssid)).replaceAll('=', '')}';
    final securityType = selected?.securityType ?? _manualSecurityType;
    final security = <String, Object?>{'type': securityType == 'enterprise' ? 'enterprise-password' : securityType};
    if (securityType == 'personal') {
      if (_password.text.length < 8 || _password.text.length > 63) {
        throw StateError('A senha Wi-Fi deve ter entre 8 e 63 caracteres.');
      }
      security['password'] = _password.text;
    } else if (securityType == 'enterprise') {
      if (_username.text.trim().isEmpty || _password.text.isEmpty) {
        throw StateError('A rede Enterprise exige usuário e senha.');
      }
      security['eap'] = {
        'method': 'peap',
        'identity': _identity.text.trim(),
        'username': _username.text.trim(),
        'password': _password.text,
      };
    }

    return {
      'schema': 'mnemos.network-profile/v1',
      'id': id,
      'ssid': ssid,
      'security': security,
      'settings': {
        'enabled': true,
        'autoConnect': true,
        'priority': 100,
      },
    };
  }

  bool _backendCanBeProvisioned(Uri uri) {
    final host = uri.host.toLowerCase();
    return host.isNotEmpty && host != '10.0.2.2' && host != 'localhost' && host != '127.0.0.1';
  }

  Future<void> _provision() async {
    final pairing = _pairing;
    if (pairing == null) return;
    late final Map<String, Object?> profile;
    try {
      profile = _networkProfile();
    } catch (e) {
      setState(() {
        _message = _friendly(e);
        _error = true;
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = 'Preparando o terminal…';
      _error = false;
    });

    String? token;
    Uri? backend;
    final backendUrl = ref.read(apiBaseUrlProvider);
    if (_backendCanBeProvisioned(backendUrl)) {
      try {
        final registration = await ref.read(terminalApiProvider).register(
              deviceId: pairing.deviceId,
              model: pairing.model,
              firmware: pairing.firmware,
            );
        token = registration.deviceToken;
        backend = backendUrl;
      } catch (_) {
        // The terminal remains valid offline. Backend registration can be
        // repeated later without blocking local provisioning.
      }
    }

    TerminalClient? client;
    var stage = 'conexão temporária';
    try {
      setState(() => _message = 'Conectando ao Mnemos…');
      final connected = await DeviceWifi.connect(ssid: pairing.ssid, password: pairing.password);
      if (!connected) throw StateError('O Android não conseguiu entrar na rede temporária do Mnemos.');
      await Future<void>.delayed(const Duration(milliseconds: 600));

      client = TerminalClient(pairing);
      stage = 'leitura do terminal';
      await client.setClock(DateTime.now());
      final info = await client.info();
      final security = profile['security'];
      final securityType = security is Map ? security['type']?.toString() : null;
      if (securityType == 'enterprise-password' && !info.enterprisePassword) {
        throw StateError('Este firmware não oferece autenticação Enterprise por usuário e senha.');
      }

      stage = 'gravação da rede';
      setState(() => _message = 'Gravando a rede ${_ssid.text.trim()}…');
      await client.provisionNetworkProfile(
        profile: profile,
        backendBaseUrl: backend,
        deviceToken: token,
      );

      stage = 'encerramento do provisionamento';
      await client.completePairing();
      await DeviceWifi.disconnect();
      client.close();
      client = null;

      final local = TerminalLocalStore(ref.read(databaseProvider));
      await local.saveTerminal(
        StoredTerminal(
          deviceId: info.deviceId,
          model: info.model,
          firmware: info.firmware,
          protocol: pairing.protocol,
          maxCards: info.maxCards,
          bleSync: info.bleSync,
          lastSeenAt: DateTime.now(),
        ),
      );
      await local.setActualDeckIds(info.deviceId, info.deckIds.toSet());

      if (!mounted) return;
      setState(() {
        _busy = false;
        _pairing = null;
        _message = 'Conexão configurada. O conteúdo do Mnemos é definido separadamente em Sincronização.';
        _error = false;
      });
    } catch (e) {
      client?.close();
      await DeviceWifi.disconnect();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Falha durante $stage: ${_friendly(e)}';
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pairing = _pairing;
    final selected = _selectedNetwork;
    return Scaffold(
      appBar: AppBar(title: const Text('Conexão')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
        children: [
          if (pairing == null) ...[
            const Text('Conectar um Mnemos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              'Esta tela configura somente a conexão do dispositivo. Cards e decks são escolhidos depois, em Sincronização.',
              style: TextStyle(height: 1.5, color: AppColors.sage),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _busy ? null : _scanQr, child: const Text('Ler QR Code do Mnemos')),
          ] else ...[
            Text(pairing.deviceId, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('${pairing.model} · firmware ${pairing.firmware}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(child: Text('Rede Wi-Fi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                IconButton(
                  tooltip: 'Atualizar redes',
                  onPressed: _busy || _scanningWifi ? null : _scanWifi,
                  icon: _scanningWifi
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_wifiNetworks.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final network in _wifiNetworks.take(10))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  enabled: !_busy,
                  title: Text(network.ssid),
                  subtitle: Text(
                    '${network.securityLabel} · ${network.band}${network.compatibleWithCurrentTerminal ? '' : ' · incompatível'}',
                    style: TextStyle(color: network.compatibleWithCurrentTerminal ? AppColors.sage : AppColors.terracotta),
                  ),
                  trailing: _ssid.text == network.ssid ? const Icon(Icons.check, color: AppColors.petrol) : null,
                  onTap: network.compatibleWithCurrentTerminal
                      ? () => setState(() {
                            _selectedNetwork = network;
                            _ssid.text = network.ssid;
                            _password.clear();
                          })
                      : null,
                ),
              const Divider(),
            ],
            TextField(
              controller: _ssid,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'SSID'),
              onChanged: (_) => setState(() => _selectedNetwork = null),
            ),
            const SizedBox(height: 10),
            if (selected == null) ...[
              DropdownButtonFormField<String>(
                initialValue: _manualSecurityType,
                decoration: const InputDecoration(labelText: 'Segurança'),
                items: const [
                  DropdownMenuItem(value: 'personal', child: Text('Rede protegida')),
                  DropdownMenuItem(value: 'enterprise', child: Text('Rede institucional / Enterprise')),
                  DropdownMenuItem(value: 'open', child: Text('Rede aberta')),
                ],
                onChanged: _busy ? null : (value) => setState(() => _manualSecurityType = value ?? 'personal'),
              ),
              const SizedBox(height: 10),
            ],
            if (selected?.enterprise == true || (selected == null && _manualSecurityType == 'enterprise')) ...[
              TextField(
                controller: _identity,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Identidade anônima (opcional)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _username,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Usuário'),
              ),
              const SizedBox(height: 10),
            ],
            if ((selected?.securityType ?? _manualSecurityType) != 'open')
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: _hidePassword,
                decoration: InputDecoration(
                  labelText: (selected?.enterprise == true || (selected == null && _manualSecurityType == 'enterprise')) ? 'Senha institucional' : 'Senha Wi-Fi',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _hidePassword = !_hidePassword),
                    icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _provision,
              child: Text(_busy ? 'Configurando…' : 'Salvar conexão'),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 18),
            Text(_message!, style: TextStyle(color: _error ? AppColors.terracotta : AppColors.sage, height: 1.45)),
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
  bool _returned = false;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Ler QR Code')),
        body: MobileScanner(
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
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
