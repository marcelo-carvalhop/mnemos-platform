import 'api.dart';
import 'token_store.dart';

/// How creating an account ended.
enum RegisterOutcome {
  /// The server needs no confirmation: the session is already stored.
  signedIn,

  /// A link went to the address; nothing is signed in until it is opened.
  verificationSent,
}

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

  /// What signing up asks for on this server.
  Future<({bool inviteRequired, bool emailVerificationRequired})> options() async {
    final body = await api.get('/v1/auth/options');
    return (
      inviteRequired: body['invite_required'] == true,
      emailVerificationRequired: body['email_verification_required'] == true,
    );
  }

  /// A new account with credentials from the start — the only way in on an
  /// invite-only server, which refuses anonymous devices.
  Future<({RegisterOutcome outcome, String? userId})> register({
    required String email,
    required String password,
    required String deviceId,
    String? inviteCode,
  }) async {
    final code = inviteCode?.trim();
    final body = await api.postAnonymous('/v1/auth/register', body: {
      'email': email,
      'password': password,
      'device_id': deviceId,
      'invite_code': (code == null || code.isEmpty) ? null : code,
    });
    final tokens = body['tokens'];
    if (body['status'] == 'signed_in' && tokens is Map<String, Object?>) {
      return (outcome: RegisterOutcome.signedIn, userId: await _store(tokens));
    }
    return (outcome: RegisterOutcome.verificationSent, userId: null);
  }

  /// The same answer for any address, so it reveals nothing.
  Future<void> resendVerification(String email) async {
    await api.postAnonymous('/v1/auth/resend-verification', body: {'email': email});
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
