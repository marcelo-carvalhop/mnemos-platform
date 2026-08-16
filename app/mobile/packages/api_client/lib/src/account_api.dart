import 'api.dart';

/// §8.4 — export and deletion, which are LGPD rights rather than features.
class AccountApi {
  const AccountApi(this.api);

  final Api api;

  /// Everything the account holds. The raw rows, not a rendered report: §3
  /// makes the review log the source of truth, so the rows are what makes
  /// this an export rather than a souvenir.
  Future<Map<String, Object?>> export() => api.get('/v1/account/export');

  /// Deletes the account and everything it holds. Not undoable.
  ///
  /// The confirmation is typed, not tapped, and it is sent verbatim — the
  /// server checks it too, because a client is not where an irreversible
  /// decision gets validated.
  Future<Map<String, Object?>> delete({required String confirmation}) async {
    final body = await api.post('/v1/account/delete', body: {'confirm': confirmation});
    return (body['deleted'] as Map<Object?, Object?>? ?? const {})
        .map((k, v) => MapEntry(k.toString(), v));
  }
}
