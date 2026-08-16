import 'package:sync_client/sync_client.dart';

import 'api.dart';
import 'api_exception.dart';

/// `SyncApi` over HTTP (§6).
///
/// Thin on purpose: the ordering, chunking and cursor rules live in
/// `sync_client`, which is tested without a network. What is here is the
/// translation, and the one thing the translation must not get wrong is
/// `assigned` — without it the outbox never empties.
class HttpSyncApi implements SyncApi {
  const HttpSyncApi(this.api);

  final Api api;

  @override
  Future<PushResult> push(
    String table,
    List<Map<String, Object?>> rows,
    String idempotencyKey,
  ) async {
    final body = await api.post(
      '/v1/sync/push',
      body: {'table': table, 'rows': rows, 'idempotency_key': idempotencyKey},
    );

    final assigned = (body['assigned'] as Map<Object?, Object?>? ?? const {})
        .map((key, value) => MapEntry(key.toString(), (value! as num).toInt()));

    return PushResult(
      applied: (body['applied']! as num).toInt(),
      assignedSeqs: assigned,
    );
  }

  @override
  Future<({List<Map<String, Object?>> rows, int cursor, bool hasMore})> pull(
    String table,
    int since,
    int limit,
  ) async {
    try {
      final body = await api.get('/v1/sync/pull', query: {
        'table': table,
        'since': '$since',
        'limit': '$limit',
      });

      return (
        rows: [
          for (final row in body['rows']! as List<Object?>)
            Map<String, Object?>.from(row! as Map<Object?, Object?>),
        ],
        cursor: (body['cursor']! as num).toInt(),
        hasMore: body['has_more']! as bool,
      );
    } on ApiException catch (e) {
      // §6.3 — the cursor predates the tombstone horizon, so an incremental
      // pull would silently miss deletions. The client must start over.
      if (e.statusCode == 409) throw ResyncRequired(e.detail ?? 'cursor too old');
      rethrow;
    }
  }
}
