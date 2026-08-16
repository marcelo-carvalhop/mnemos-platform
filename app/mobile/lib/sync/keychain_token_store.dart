import 'package:api_client/api_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// §8.2 — the tokens go in the platform keychain.
///
/// Not in `local_settings`: a refresh token is a credential, and the database
/// is the thing that gets exported (§8.4), backed up by the OS, and copied
/// around during a restore. Keeping it out of there means an export can never
/// carry someone's session with it.
class KeychainTokenStore implements TokenStore {
  const KeychainTokenStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static const _access = 'access_token';
  static const _refresh = 'refresh_token';

  @override
  Future<String?> readAccess() => _storage.read(key: _access);

  @override
  Future<String?> readRefresh() => _storage.read(key: _refresh);

  @override
  Future<void> write({required String access, required String refresh}) async {
    await _storage.write(key: _access, value: access);
    await _storage.write(key: _refresh, value: refresh);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _access);
    await _storage.delete(key: _refresh);
  }
}
