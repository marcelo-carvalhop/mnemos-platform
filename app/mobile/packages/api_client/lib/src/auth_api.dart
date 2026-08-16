import 'api.dart';
import 'token_store.dart';

/// §8.1 and §8.2 — identity, from first launch to signing in.
class AuthApi {
  const AuthApi(this.api, this.tokens);

  final Api api;
  final TokenStore tokens;

  /// A single-use nonce to attest over. Unauthenticated: it happens before
  /// any account exists.
  Future<String> challenge(String deviceId) async {
    final body = await api.postAnonymous(
      '/v1/auth/challenge',
      body: {'device_id': deviceId},
    );
    return body['nonce']! as String;
  }

  /// First launch: an anonymous account bound to this device.
  ///
  /// The attestation is what stops a reinstall from minting a second free
  /// generation (§8.1, §7.7). The platform plugin produces it; this only
  /// carries it.
  Future<String> registerDevice({
    required String deviceId,
    required String platform,
    String? attestation,
    String? nonce,
  }) async {
    final body = await api.postAnonymous('/v1/auth/device', body: {
      'device_id': deviceId,
      'platform': platform,
      if (attestation != null) 'attestation': attestation,
      if (nonce != null) 'nonce': nonce,
    });
    return _store(body);
  }

  /// Gives the existing anonymous account credentials. Nothing moves: the
  /// rows already belong to this user (§8.1).
  Future<String> signup({
    required String email,
    required String password,
    required String deviceId,
  }) async {
    final body = await api.post('/v1/auth/signup', body: {
      'email': email,
      'password': password,
      'device_id': deviceId,
    });
    return _store(body);
  }

  /// Signing in on a second device, or after a reinstall (§8.3).
  Future<String> login({
    required String email,
    required String password,
    required String deviceId,
  }) async {
    final body = await api.postAnonymous('/v1/auth/login', body: {
      'email': email,
      'password': password,
      'device_id': deviceId,
    });
    return _store(body);
  }

  Future<void> signOut() => tokens.clear();

  Future<String> _store(Map<String, Object?> body) async {
    await tokens.write(
      access: body['access_token']! as String,
      refresh: body['refresh_token']! as String,
    );
    return body['user_id']! as String;
  }
}
