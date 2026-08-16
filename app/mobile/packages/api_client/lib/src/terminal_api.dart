import 'api.dart';

class TerminalRegistration {
  const TerminalRegistration({
    required this.deviceId,
    required this.deviceToken,
    required this.protocol,
  });

  final String deviceId;
  final String deviceToken;
  final int protocol;

  factory TerminalRegistration.fromJson(Map<String, Object?> json) => TerminalRegistration(
        deviceId: json['device_id']! as String,
        deviceToken: json['device_token']! as String,
        protocol: (json['protocol']! as num).toInt(),
      );
}

/// Authenticated app-side API used to register or rotate a terminal credential.
class TerminalApi {
  const TerminalApi(this.api);

  final Api api;

  Future<TerminalRegistration> register({
    required String deviceId,
    required String model,
    required String firmware,
    required Set<String> deckIds,
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
}
