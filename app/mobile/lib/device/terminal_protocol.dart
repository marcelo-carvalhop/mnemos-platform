import 'dart:convert';

import 'package:http/http.dart' as http;

String _requiredString(Map<String, Object?> json, String key, String source) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) return value;
  throw FormatException(
    '$source inválido: campo obrigatório "$key" ausente ou inválido.',
  );
}

int _requiredInt(Map<String, Object?> json, String key, String source) {
  final value = json[key];
  if (value is num) return value.toInt();
  throw FormatException(
    '$source inválido: campo obrigatório "$key" ausente ou inválido.',
  );
}

Map<String, Object?> _decodeObject(String body, String source) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException catch (e) {
    throw FormatException('$source retornou JSON inválido: ${e.message}');
  }
  if (decoded is! Map) {
    throw FormatException('$source inválido: era esperado um objeto JSON.');
  }
  return Map<String, Object?>.from(decoded);
}

class TerminalPairing {
  const TerminalPairing({
    required this.protocol,
    required this.mode,
    required this.deviceId,
    required this.ssid,
    required this.password,
    required this.host,
    required this.token,
    required this.model,
    required this.firmware,
  });

  final int protocol;
  final String mode;
  final String deviceId;
  final String ssid;
  final String password;
  final String host;
  final String token;
  final String model;
  final String firmware;

  static TerminalPairing parse(String raw) {
    final uri = Uri.parse(raw);
    if (uri.scheme != 'mnemos' || (uri.host != 'pair' && uri.host != 'local')) {
      throw const FormatException(
        'Este QR Code não pertence a um terminal Mnemos.',
      );
    }
    final q = uri.queryParameters;
    final mode = q['mode'] ?? 'provision';
    final protocol = int.tryParse(q['v'] ?? '');
    final deviceId = q['id'];
    final ssid = q['ssid'];
    final password = q['pwd'];
    final host = q['host'];
    final token = q['token'];
    final model = q['model'] ?? 'Mnemos Terminal';
    final firmware = q['fw'] ?? 'desconhecido';
    if (protocol == null ||
        deviceId == null ||
        ssid == null ||
        password == null ||
        host == null ||
        token == null) {
      throw const FormatException('QR Code de pareamento incompleto.');
    }
    if (protocol < 1 || protocol > 4) {
      throw FormatException('Protocolo de terminal incompatível: $protocol.');
    }
    return TerminalPairing(
      protocol: protocol,
      mode: mode,
      deviceId: deviceId,
      ssid: ssid,
      password: password,
      host: host,
      token: token,
      model: model,
      firmware: firmware,
    );
  }
}

class TerminalInfo {
  const TerminalInfo({
    required this.deviceId,
    required this.firmware,
    required this.model,
    required this.cardCount,
    required this.maxCards,
    required this.clockTrusted,
    required this.wifiEnabled,
    required this.wifiConnected,
    required this.supportedCardTypes,
    required this.supportedContentFormats,
    required this.deckIds,
    required this.bleSync,
    required this.enterprisePassword,
    this.infrastructureSsid,
  });

  final String deviceId;
  final String firmware;
  final String model;
  final int cardCount;
  final int maxCards;
  final bool clockTrusted;
  final bool wifiEnabled;
  final bool wifiConnected;
  final List<String> supportedCardTypes;
  final List<String> supportedContentFormats;
  final List<String> deckIds;
  final bool bleSync;
  final bool enterprisePassword;
  final String? infrastructureSsid;

  factory TerminalInfo.fromJson(Map<String, Object?> json) {
    const source = 'Resposta /info do terminal';
    final rawCapabilities = json['capabilities'];
    final capabilities = rawCapabilities is Map
        ? rawCapabilities
        : const <Object?, Object?>{};
    final rawCardTypes = capabilities['cardTypes'];
    final rawFormats = capabilities['contentFormats'];

    return TerminalInfo(
      deviceId: _requiredString(json, 'deviceId', source),
      firmware: _requiredString(json, 'firmware', source),
      model: _requiredString(json, 'model', source),
      cardCount: _requiredInt(json, 'cardCount', source),
      maxCards: _requiredInt(json, 'maxCards', source),
      clockTrusted: json['clockTrusted'] as bool? ?? false,
      wifiEnabled: json['wifiEnabled'] as bool? ?? false,
      wifiConnected: json['wifiConnected'] as bool? ?? false,
      supportedCardTypes: rawCardTypes is List
          ? [for (final value in rawCardTypes) value.toString()]
          : const [],
      supportedContentFormats: rawFormats is List
          ? [for (final value in rawFormats) value.toString()]
          : const [],
      deckIds: json['deckIds'] is List
          ? [for (final value in json['deckIds'] as List) value.toString()]
          : const [],
      bleSync:
          (json['features'] is Map
                  ? (json['features'] as Map)['bleSync']
                  : null)
              as bool? ??
          false,
      enterprisePassword:
          (json['features'] is Map
                  ? (json['features'] as Map)['enterprisePassword']
                  : null)
              as bool? ??
          false,
      infrastructureSsid: json['infrastructureSsid'] as String?,
    );
  }
}

class TerminalNetworkStatus {
  const TerminalNetworkStatus({
    required this.enabled,
    required this.connected,
    this.ssid,
    this.ip,
    this.lastError,
  });

  final bool enabled;
  final bool connected;
  final String? ssid;
  final String? ip;
  final String? lastError;

  factory TerminalNetworkStatus.fromJson(Map<String, Object?> json) =>
      TerminalNetworkStatus(
        enabled: json['enabled'] as bool? ?? false,
        connected: json['connected'] as bool? ?? false,
        ssid: json['ssid'] as String?,
        ip: json['ip'] as String?,
        lastError: json['lastError'] as String?,
      );
}

class TerminalReview {
  const TerminalReview({
    required this.id,
    required this.cardId,
    required this.reviewedAt,
    required this.rating,
    required this.responseTimeMs,
    required this.confidence,
  });

  final String id;
  final String cardId;
  final int reviewedAt;
  final int rating;
  final int responseTimeMs;
  final int confidence;

  factory TerminalReview.fromJson(Map<String, Object?> json) {
    const source = 'Evento de revisão do terminal';
    return TerminalReview(
      id: _requiredString(json, 'id', source),
      cardId: _requiredString(json, 'cardId', source),
      reviewedAt: json['reviewedAtMs'] is num
          ? (json['reviewedAtMs'] as num).toInt() ~/ 1000
          : _requiredInt(json, 'reviewedAt', source),
      rating: json['schedulerRating'] is num
          ? (json['schedulerRating'] as num).toInt()
          : _requiredInt(json, 'rating', source),
      responseTimeMs: (json['responseTimeMs'] as num?)?.toInt() ?? 0,
      confidence: (json['confidence'] as num?)?.toInt() ?? 0,
    );
  }
}

class TerminalClient {
  TerminalClient(this.pairing, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final TerminalPairing pairing;
  final http.Client _http;

  Uri _uri(String path) => Uri.parse(
    'http://${pairing.host}$path',
  ).replace(queryParameters: {'token': pairing.token});

  Future<Map<String, Object?>> _getJson(
    String path, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final response = await _http.get(_uri(path)).timeout(timeout);
    _ensureOk(response);
    return _decodeObject(response.body, 'GET $path');
  }

  Future<Map<String, Object?>> _postJson(
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final response = await _http
        .post(
          _uri(path),
          headers: const {'content-type': 'application/json; charset=utf-8'},
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(timeout);
    _ensureOk(response);
    if (response.body.isEmpty) return const {};
    return _decodeObject(response.body, 'POST $path');
  }

  Future<TerminalInfo> info() async {
    final path = pairing.protocol >= 4
        ? '/v4/info'
        : pairing.protocol >= 3
        ? '/v3/info'
        : pairing.protocol >= 2
        ? '/v2/info'
        : '/v1/info';
    return TerminalInfo.fromJson(await _getJson(path));
  }

  Future<void> setClock(DateTime instant) async {
    final epochSeconds = instant.toUtc().millisecondsSinceEpoch ~/ 1000;
    final path = pairing.protocol >= 4
        ? '/v4/time'
        : pairing.protocol >= 3
        ? '/v3/time'
        : pairing.protocol >= 2
        ? '/v2/time'
        : '/v1/time';
    await _postJson(path, body: {'epochSeconds': epochSeconds});
  }

  Future<void> provisionNetworkProfile({
    required Map<String, Object?> profile,
    Uri? backendBaseUrl,
    String? deviceToken,
    int syncIntervalSeconds = 1800,
  }) async {
    if (pairing.protocol < 3) {
      final security = profile['security'];
      final securityMap = security is Map ? security : const {};
      await provision(
        ssid: profile['ssid']?.toString() ?? '',
        wifiPassword: securityMap['password']?.toString() ?? '',
        backendBaseUrl: backendBaseUrl,
        deviceToken: deviceToken,
        syncIntervalSeconds: syncIntervalSeconds,
      );
      return;
    }
    final payload = <String, Object?>{
      'schema': 'mnemos.provision/v2',
      'networkProfile': profile,
      'syncIntervalSeconds': syncIntervalSeconds,
      'clockEpochSeconds':
          DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      if (backendBaseUrl != null && deviceToken != null)
        'backend': {
          'baseUrl': backendBaseUrl.toString(),
          'deviceToken': deviceToken,
        },
    };
    await _postJson(
      pairing.protocol >= 4 ? '/v4/provision' : '/v3/provision',
      body: payload,
    );
  }

  Future<TerminalNetworkStatus> provision({
    required String ssid,
    required String wifiPassword,
    Uri? backendBaseUrl,
    String? deviceToken,
    int syncIntervalSeconds = 1800,
  }) async {
    if (pairing.protocol < 2) {
      throw StateError(
        'O firmware deste terminal não suporta provisionamento Wi-Fi v2.',
      );
    }
    final payload = <String, Object?>{
      'schema': 'mnemos.provision/v1',
      'wifi': {'ssid': ssid, 'password': wifiPassword},
      'syncIntervalSeconds': syncIntervalSeconds,
      'clockEpochSeconds':
          DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      if (backendBaseUrl != null && deviceToken != null)
        'backend': {
          'baseUrl': backendBaseUrl.toString(),
          'deviceToken': deviceToken,
        },
    };
    return TerminalNetworkStatus.fromJson(
      await _postJson('/v2/provision', body: payload),
    );
  }

  Future<TerminalNetworkStatus> networkStatus() async =>
      TerminalNetworkStatus.fromJson(
        await _getJson(
          pairing.protocol >= 4
              ? '/v4/network/status'
              : pairing.protocol >= 3
              ? '/v3/network/status'
              : '/v2/network/status',
        ),
      );

  Future<void> completePairing() async {
    if (pairing.protocol >= 4) {
      await _postJson('/v4/complete');
    } else if (pairing.protocol >= 3) {
      await _postJson('/v3/pairing/complete');
    } else if (pairing.protocol >= 2) {
      await _postJson('/v2/pairing/complete');
    }
  }

  Future<void> acknowledgeReviews() async {
    final path = pairing.protocol >= 4
        ? '/v4/sync/reviews/ack'
        : pairing.protocol >= 2
        ? '/v2/reviews/ack'
        : '/v1/reviews/ack';
    await _postJson(path);
  }

  Future<List<TerminalReview>> reviews() async {
    if (pairing.protocol >= 2) {
      final path = pairing.protocol >= 4 ? '/v4/sync/reviews' : '/v2/reviews';

      final payload = await _getJson(
        path,
        timeout: const Duration(seconds: 12),
      );
      final rawReviews = payload['reviews'];
      if (rawReviews == null) return const [];
      if (rawReviews is! List) {
        throw const FormatException(
          'Resposta /v2/reviews inválida: "reviews" não é uma lista.',
        );
      }
      final rows = <TerminalReview>[];
      for (var i = 0; i < rawReviews.length; i++) {
        final value = rawReviews[i];
        if (value is! Map) {
          throw FormatException(
            'Resposta /v2/reviews inválida: item $i não é um objeto.',
          );
        }
        rows.add(TerminalReview.fromJson(Map<String, Object?>.from(value)));
      }
      return rows;
    }

    final response = await _http
        .get(_uri('/v1/reviews'))
        .timeout(const Duration(seconds: 12));
    _ensureOk(response);
    final rows = <TerminalReview>[];
    for (final line in const LineSplitter().convert(response.body)) {
      if (line.trim().isEmpty) continue;
      rows.add(
        TerminalReview.fromJson(_decodeObject(line, 'Linha /v1/reviews')),
      );
    }
    return rows;
  }

  Future<int> sendLibrary(Map<String, Object?> bundle) async {
    final path = pairing.protocol >= 4
        ? '/v4/sync/library'
        : pairing.protocol >= 2
        ? '/v2/library'
        : '/v1/library';
    final body = await _postJson(
      path,
      body: bundle,
      timeout: const Duration(seconds: 24),
    );
    return _requiredInt(body, 'cardCount', 'Resposta $path');
  }

  void _ensureOk(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String detail = 'Terminal respondeu HTTP ${response.statusCode}.';
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] != null) {
        detail = body['error'].toString();
      }
    } catch (_) {}
    throw StateError(detail);
  }

  void close() => _http.close();
}
