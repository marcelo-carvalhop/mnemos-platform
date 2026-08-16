/// What went wrong, in terms the app can branch on.
///
/// §10 requires the client to map a machine-readable code to copy rather than
/// matching on server prose, so the code is carried separately from the
/// message and the message is never shown raw.
class ApiException implements Exception {
  const ApiException(this.statusCode, {this.code, this.detail});

  final int statusCode;

  /// The `ErrorCode` the server sent, when it sent one.
  final String? code;
  final String? detail;

  /// §7.7 — the paywall, not an error dialog.
  bool get isQuotaExhausted => statusCode == 402;

  /// Sign in again. Distinguished from 403, which means the account is fine
  /// and this particular thing is not allowed.
  bool get isUnauthenticated => statusCode == 401;

  /// Worth retrying: the server is having a moment, the request was not
  /// wrong.
  bool get isTransient => statusCode >= 500 || statusCode == 429;

  @override
  String toString() => 'ApiException($statusCode${code == null ? "" : ", $code"})';
}

/// The network did not answer at all — distinct from an answer we did not
/// like. Offline-first means this is ordinary, not exceptional (§2.2).
class Offline implements Exception {
  const Offline(this.cause);
  final Object cause;

  @override
  String toString() => 'Offline: $cause';
}
