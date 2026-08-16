import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'token_store.dart';

/// The one place that turns a request into an authenticated request.
///
/// Refresh happens here rather than in each caller, and it happens **once**
/// for concurrent 401s: a device that wakes up and fires six sync requests at
/// a stale token must not rotate the refresh token six times. §8.2 revokes a
/// whole token family when a refresh token is replayed, so a self-inflicted
/// race would log the user out.
class Api {
  Api({
    required this.baseUrl,
    required this.tokens,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final Uri baseUrl;
  final TokenStore tokens;
  final Duration timeout;
  final http.Client _client;

  /// Held so that concurrent 401s await one rotation instead of racing.
  Future<bool>? _refreshing;

  /// Called when the refresh token is gone or rejected — the app has to send
  /// the user back to sign-in, and only the app knows how.
  void Function()? onAuthenticationLost;

  Future<Map<String, Object?>> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<Map<String, Object?>> post(String path, {Object? body}) =>
      _send('POST', path, body: body);

  /// Unauthenticated: used before an account exists (§8.1).
  Future<Map<String, Object?>> postAnonymous(String path, {Object? body}) =>
      _send('POST', path, body: body, authenticated: false);

  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool authenticated = true,
    bool isRetry = false,
  }) async {
    final uri = baseUrl.resolve(path).replace(queryParameters: query);
    final headers = <String, String>{'content-type': 'application/json'};

    if (authenticated) {
      final token = await tokens.readAccess();
      if (token != null) headers['authorization'] = 'Bearer $token';
    }

    late final http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      );
    } on SocketException catch (e) {
      // Offline is the normal case, not the exceptional one (§2.2). The caller
      // keeps working against local SQLite and tries again later.
      throw Offline(e);
    } on TimeoutException catch (e) {
      throw Offline(e);
    } on http.ClientException catch (e) {
      throw Offline(e);
    }

    if (response.statusCode == 401 && authenticated && !isRetry) {
      if (await _refreshOnce()) {
        return _send(method, path, query: query, body: body, isRetry: true);
      }
    }

    if (response.statusCode >= 400) throw _asException(response);

    if (response.body.isEmpty) return const {};
    return jsonDecode(response.body) as Map<String, Object?>;
  }

  ApiException _asException(http.Response response) {
    String? code;
    String? detail;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        detail = decoded['detail']?.toString();
        code = decoded['error_code']?.toString() ?? decoded['code']?.toString();
      }
    } on FormatException {
      // A proxy returning HTML is still a failure; it is just not ours.
      detail = null;
    }
    return ApiException(response.statusCode, code: code, detail: detail);
  }

  /// Rotates the token pair. Concurrent callers share one attempt.
  Future<bool> _refreshOnce() {
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _refresh() async {
    final refresh = await tokens.readRefresh();
    if (refresh == null) {
      onAuthenticationLost?.call();
      return false;
    }

    try {
      final body = await _send(
        'POST',
        '/v1/auth/refresh',
        body: {'refresh_token': refresh},
        authenticated: false,
      );
      await tokens.write(
        access: body['access_token']! as String,
        refresh: body['refresh_token']! as String,
      );
      return true;
    } on ApiException {
      // The refresh token was rejected. §8.2 treats a replayed refresh as a
      // compromise and revokes the family, so there is nothing to retry.
      await tokens.clear();
      onAuthenticationLost?.call();
      return false;
    }
  }

  void close() => _client.close();
}
