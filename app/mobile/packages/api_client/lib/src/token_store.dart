/// Where the tokens live.
///
/// An interface, because the app puts them in the platform keychain and the
/// tests put them in a map. §8.2: the refresh token is a credential — it is
/// never written to the database next to the study data, and never logged.
abstract interface class TokenStore {
  Future<String?> readAccess();
  Future<String?> readRefresh();
  Future<void> write({required String access, required String refresh});
  Future<void> clear();
}

/// In-memory, for tests and for a first launch that has not persisted yet.
class MemoryTokenStore implements TokenStore {
  String? _access;
  String? _refresh;

  @override
  Future<String?> readAccess() async => _access;

  @override
  Future<String?> readRefresh() async => _refresh;

  @override
  Future<void> write({required String access, required String refresh}) async {
    _access = access;
    _refresh = refresh;
  }

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
  }
}
