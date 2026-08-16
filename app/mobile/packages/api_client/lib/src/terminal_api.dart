import 'api.dart';

String _requiredString(Map<String, Object?> json, String key, String source) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) return value;
  throw FormatException('$source inválido: campo obrigatório "$key" ausente ou inválido.');
}

int _requiredInt(Map<String, Object?> json, String key, String source) {
  final value = json[key];
  if (value is num) return value.toInt();
  throw FormatException('$source inválido: campo obrigatório "$key" ausente ou inválido.');
}

class TerminalRegistration {
  const TerminalRegistration({required this.deviceId, required this.deviceToken, required this.protocol});
  final String deviceId;
  final String deviceToken;
  final int protocol;

  factory TerminalRegistration.fromJson(Map<String, Object?> json) {
    const source = 'Resposta de registro do terminal';
    return TerminalRegistration(
      deviceId: _requiredString(json, 'device_id', source),
      deviceToken: _requiredString(json, 'device_token', source),
      protocol: _requiredInt(json, 'protocol', source),
    );
  }
}

class TerminalSummary {
  const TerminalSummary({
    required this.deviceId,
    required this.model,
    required this.firmware,
    required this.desiredDeckIds,
    required this.reportedDeckIds,
    required this.cardCount,
    required this.maxCards,
    required this.revoked,
    this.lastSeenAt,
    this.lastSyncAt,
    this.connectivity,
    this.wifiSsid,
  });

  final String deviceId;
  final String model;
  final String firmware;
  final List<String> desiredDeckIds;
  final List<String> reportedDeckIds;
  final int cardCount;
  final int maxCards;
  final bool revoked;
  final String? lastSeenAt;
  final String? lastSyncAt;
  final String? connectivity;
  final String? wifiSsid;

  factory TerminalSummary.fromJson(Map<String, Object?> json) {
    List<String> strings(Object? value) => value is List ? value.map((e) => e.toString()).toList() : const [];
    return TerminalSummary(
      deviceId: _requiredString(json, 'device_id', 'Resumo do terminal'),
      model: (json['model'] as String?) ?? 'Mnemos Terminal',
      firmware: (json['firmware'] as String?) ?? 'desconhecido',
      desiredDeckIds: strings(json['desired_deck_ids'] ?? json['deck_ids']),
      reportedDeckIds: strings(json['reported_deck_ids']),
      cardCount: (json['card_count'] as num?)?.toInt() ?? 0,
      maxCards: (json['max_cards'] as num?)?.toInt() ?? 0,
      revoked: json['revoked'] as bool? ?? false,
      lastSeenAt: json['last_seen_at'] as String?,
      lastSyncAt: json['last_sync_at'] as String?,
      connectivity: json['connectivity'] as String?,
      wifiSsid: json['wifi_ssid'] as String?,
    );
  }
}

/// App-side management of dedicated Mnemos terminals.
class TerminalApi {
  const TerminalApi(this.api);
  final Api api;

  Future<TerminalRegistration> register({
    required String deviceId,
    required String model,
    required String firmware,
    Set<String> deckIds = const {},
  }) async {
    return TerminalRegistration.fromJson(
      await api.post(
        '/v1/terminals/register',
        body: {
          'device_id': deviceId,
          'model': model,
          'firmware': firmware,
          'deck_ids': deckIds.toList(growable: false),
        },
      ),
    );
  }

  Future<TerminalSummary> summary(String deviceId) async => TerminalSummary.fromJson(
        await api.get('/v1/terminals/$deviceId/summary'),
      );

  Future<TerminalSummary> updateDecks(String deviceId, Set<String> deckIds) async => TerminalSummary.fromJson(
        await api.post(
          '/v1/terminals/$deviceId/decks',
          body: {'deck_ids': deckIds.toList(growable: false)},
        ),
      );
  Future<TerminalSummary> reportObserved(
    String deviceId, {
    required Set<String> deckIds,
    required int cardCount,
    required int maxCards,
  }) async => TerminalSummary.fromJson(
        await api.post(
          '/v1/terminals/$deviceId/observed',
          body: {
            'reported_deck_ids': deckIds.toList(growable: false),
            'card_count': cardCount,
            'max_cards': maxCards,
          },
        ),
      );

}
