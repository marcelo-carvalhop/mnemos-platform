import 'package:flutter/services.dart';

class WifiNetwork {
  const WifiNetwork({
    required this.ssid,
    required this.level,
    required this.secure,
    required this.securityType,
    required this.has24GHz,
    required this.has5GHz,
    required this.has6GHz,
  });

  final String ssid;
  final int level;
  final bool secure;
  final String securityType;
  final bool has24GHz;
  final bool has5GHz;
  final bool has6GHz;

  bool get supportedSecurity => const {'open', 'personal', 'enterprise'}.contains(securityType);

  bool get compatibleWithCurrentTerminal => has24GHz && supportedSecurity;

  bool get enterprise => securityType == 'enterprise';

  String get band {
    final values = <String>[];
    if (has24GHz) values.add('2,4 GHz');
    if (has5GHz) values.add('5 GHz');
    if (has6GHz) values.add('6 GHz');
    return values.isEmpty ? 'frequência desconhecida' : values.join(' + ');
  }

  String get securityLabel {
    switch (securityType) {
      case 'enterprise':
        return 'Enterprise';
      case 'open':
        return 'Aberta';
      case 'personal':
        return 'Protegida';
      default:
        return 'Segurança não suportada';
    }
  }

  factory WifiNetwork.fromMap(Map<Object?, Object?> map) {
    final ssid = map['ssid'];
    if (ssid is! String || ssid.trim().isEmpty) {
      throw const FormatException('Resultado de Wi-Fi sem SSID válido.');
    }
    final frequency = (map['frequency'] as num?)?.toInt() ?? 0;
    return WifiNetwork(
      ssid: ssid.trim(),
      level: (map['level'] as num?)?.toInt() ?? -100,
      secure: map['secure'] as bool? ?? true,
      securityType: map['securityType']?.toString() ?? 'unknown',
      has24GHz: map['has24GHz'] as bool? ?? (frequency >= 2400 && frequency <= 2500),
      has5GHz: map['has5GHz'] as bool? ?? (frequency >= 4900 && frequency < 5925),
      has6GHz: map['has6GHz'] as bool? ?? frequency >= 5925,
    );
  }
}

abstract final class DeviceWifi {
  static const _channel = MethodChannel('br.com.mnemos/device_wifi');

  static Future<bool> connect({required String ssid, required String password}) async {
    return await _channel.invokeMethod<bool>('connect', {'ssid': ssid, 'password': password}) ?? false;
  }

  static Future<String?> currentSsid() => _channel.invokeMethod<String>('currentSsid');

  static Future<List<WifiNetwork>> scanNetworks() async {
    final values = await _channel.invokeListMethod<Object?>('scanNetworks') ?? const <Object?>[];
    final result = <WifiNetwork>[];
    for (final value in values) {
      if (value is! Map) continue;
      try {
        result.add(WifiNetwork.fromMap(Map<Object?, Object?>.from(value)));
      } on FormatException {
        // Ignore one malformed platform result; manual SSID entry remains.
      }
    }
    result.sort((a, b) {
      if (a.compatibleWithCurrentTerminal != b.compatibleWithCurrentTerminal) {
        return a.compatibleWithCurrentTerminal ? -1 : 1;
      }
      return b.level.compareTo(a.level);
    });
    return result;
  }

  static Future<void> disconnect() => _channel.invokeMethod<void>('disconnect');
}
