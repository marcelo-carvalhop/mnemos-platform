import 'dart:convert';

import 'package:http/http.dart' as http;

class TerminalPairing {
  const TerminalPairing({
    required this.protocol,
    required this.deviceId,
    required this.ssid,
    required this.password,
    required this.host,
    required this.token,
    required this.model,
    required this.firmware,
  });

  final int protocol;
  final String deviceId;
  final String ssid;
  final String password;
  final String host;
  final String token;
  final String model;
  final String firmware;

  static TerminalPairing parse(String raw) {
    final uri = Uri.parse(raw);
    if (uri.scheme != 'mnemos' || uri.host != 'pair') {
      throw const FormatException('Este QR Code não pertence a um terminal Mnemos.');
    }
    final q = uri.queryParameters;
    final protocol = int.tryParse(q['v'] ?? '');
    final deviceId = q['id'];
    final ssid = q['ssid'];
    final password = q['pwd'];
    final host = q['host'];
    final token = q['token'];
    final model = q['model'] ?? 'Mnemos Terminal';
    final firmware = q['fw'] ?? 'desconhecido';
    if (protocol == null || deviceId == null || ssid == null || password == null ||
        host == null || token == null) {
      throw const FormatException('QR Code de pareamento incompleto.');
    }
    if (protocol < 1 || protocol > 2) {
      throw FormatException('Protocolo de terminal incompatível: $protocol.');
    }
    return TerminalPairing(
      protocol: protocol,
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
  final String? infrastructureSsid;

  factory TerminalInfo.fromJson(Map<String, Object?> json) {
    final rawCapabilities = json['capabilities'];
    final capabilities = rawCapabilities is Map ? rawCapabilities : const <Object?, Object?>{};
    final rawCardTypes = capabilities['cardTypes'];
    final rawFormats = capabilities['contentFormats'];

    return TerminalInfo(
      deviceId: json['deviceId']! as String,
      firmware: json['firmware']! as String,
      model: json['model']! as String,
      cardCount: (json['cardCount']! as num).toInt(),
      maxCards: (json['maxCards']! as num).toInt(),
      clockTrusted: json['clockTrusted'] as bool? ?? false,
      wifiEnabled: json['wifiEnabled'] as bool? ?? false,
      wifiConnected: json['wifiConnected'] as bool? ?? false,
      supportedCardTypes: rawCardTypes is List
          ? [for (final value in rawCardTypes) value.toString()]
          : const [],
      supportedContentFormats: rawFormats is List
          ? [for (final value in rawFormats) value.toString()]
          : const [],
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

  factory TerminalNetworkStatus.fromJson(Map<String, Object?> json) => TerminalNetworkStatus(
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

  factory TerminalReview.fromJson(Map<String, Object?> json) => TerminalReview(
        id: json['id']! as String,
        cardId: json['cardId']! as String,
        reviewedAt: (json['reviewedAt']! as num).toInt(),
        rating: (json['rating']! as num).toInt(),
        responseTimeMs: (json['responseTimeMs'] as num?)?.toInt() ?? 0,
        confidence: (json['confidence'] as num?)?.toInt() ?? 0,
      );
}

class TerminalClient {
  TerminalClient(this.pairing, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final TerminalPairing pairing;
  final http.Client _http;

  Uri _uri(String path) => Uri.parse('http://${pairing.host}$path')
      .replace(queryParameters: {'token': pairing.token});

  Future<Map<String, Object?>> _getJson(String path, {Duration timeout = const Duration(seconds: 10)}) async {
    final response = await _http.get(_uri(path)).timeout(timeout);
    _ensureOk(response);
    return Map<String, Object?>.from(jsonDecode(response.body) as Map);
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
    return Map<String, Object?>.from(jsonDecode(response.body) as Map);
  }

  Future<TerminalInfo> info() async {
    final path = pairing.protocol >= 2 ? '/v2/info' : '/v1/info';
    return TerminalInfo.fromJson(await _getJson(path));
  }

  Future<void> setClock(DateTime instant) async {
    final epochSeconds = instant.toUtc().millisecondsSinceEpoch ~/ 1000;
    final path = pairing.protocol >= 2 ? '/v2/time' : '/v1/time';
    await _postJson(path, body: {'epochSeconds': epochSeconds});
  }

  Future<TerminalNetworkStatus> provision({
    required String ssid,
    required String wifiPassword,
    Uri? backendBaseUrl,
    String? deviceToken,
    int syncIntervalSeconds = 1800,
  }) async {
    if (pairing.protocol < 2) {
      throw StateError('O firmware deste terminal não suporta provisionamento Wi-Fi v2.');
    }
    final payload = <String, Object?>{
      'schema': 'mnemos.provision/v1',
      'wifi': {'ssid': ssid, 'password': wifiPassword},
      'syncIntervalSeconds': syncIntervalSeconds,
      'clockEpochSeconds': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      if (backendBaseUrl != null && deviceToken != null)
        'backend': {'baseUrl': backendBaseUrl.toString(), 'deviceToken': deviceToken},
    };
    return TerminalNetworkStatus.fromJson(await _postJson('/v2/provision', body: payload));
  }

  Future<TerminalNetworkStatus> networkStatus() async =>
      TerminalNetworkStatus.fromJson(await _getJson('/v2/network/status'));

  Future<void> completePairing() async {
    if (pairing.protocol >= 2) await _postJson('/v2/pairing/complete');
  }

  Future<void> acknowledgeReviews() async {
    final path = pairing.protocol >= 2 ? '/v2/reviews/ack' : '/v1/reviews/ack';
    await _postJson(path);
  }

  Future<List<TerminalReview>> reviews() async {
    if (pairing.protocol >= 2) {
      final payload = await _getJson('/v2/reviews', timeout: const Duration(seconds: 12));
      final list = payload['reviews'] as List<Object?>? ?? const [];
      return [
        for (final value in list)
          TerminalReview.fromJson(Map<String, Object?>.from(value! as Map)),
      ];
    }

    final response = await _http.get(_uri('/v1/reviews')).timeout(const Duration(seconds: 12));
    _ensureOk(response);
    final rows = <TerminalReview>[];
    for (final line in const LineSplitter().convert(response.body)) {
      if (line.trim().isEmpty) continue;
      rows.add(TerminalReview.fromJson(Map<String, Object?>.from(jsonDecode(line) as Map)));
    }
    return rows;
  }

  Future<int> sendLibrary(Map<String, Object?> bundle) async {
    final path = pairing.protocol >= 2 ? '/v2/library' : '/v1/library';
    final body = await _postJson(path, body: bundle, timeout: const Duration(seconds: 24));
    return (body['cardCount']! as num).toInt();
  }

  void _ensureOk(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String detail = 'Terminal respondeu HTTP ${response.statusCode}.';
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] != null) detail = body['error'].toString();
    } catch (_) {}
    throw StateError(detail);
  }

  void close() => _http.close();
}
