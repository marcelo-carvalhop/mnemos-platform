import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api.dart';
import 'api_exception.dart';

/// One generation, as the app sees it (§5.5).
class GenerationJob {
  const GenerationJob({
    required this.id,
    required this.status,
    required this.stage,
    this.errorCode,
    this.errorDetail,
    this.cardCount = 0,
  });

  factory GenerationJob.fromJson(Map<String, Object?> json) => GenerationJob(
        id: json['id']! as String,
        status: json['status']! as String,
        // §5.5 — the server names the stage, so the app does not invent copy
        // from a status it might not recognise.
        stage: json['stage']! as String,
        errorCode: json['error_code'] as String?,
        errorDetail: json['error_detail'] as String?,
        cardCount: (json['card_count'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String status;
  final String stage;
  final String? errorCode;
  final String? errorDetail;
  final int cardCount;

  bool get isFinished => status == 'ready' || status == 'failed';
  bool get isReady => status == 'ready';
}

/// A card waiting for a human (§7.8).
class PendingCard {
  const PendingCard({
    required this.id,
    required this.front,
    required this.back,
    required this.tags,
    required this.position,
    this.decision,
  });

  factory PendingCard.fromJson(Map<String, Object?> json) => PendingCard(
        id: json['id']! as String,
        front: json['front']! as String,
        back: json['back']! as String,
        tags: [for (final t in json['tags'] as List<Object?>? ?? const []) t.toString()],
        position: (json['position'] as num?)?.toInt() ?? 0,
        decision: json['decision'] as String?,
      );

  final String id;
  final String front;
  final String back;
  final List<String> tags;
  final int position;

  /// null | approved | discarded. Null is undecided, and also the undo §5.7
  /// makes mandatory.
  final String? decision;
}

class ApprovalQueue {
  const ApprovalQueue({required this.cards, required this.decided, required this.total});

  factory ApprovalQueue.fromJson(Map<String, Object?> json) => ApprovalQueue(
        cards: [
          for (final c in json['cards']! as List<Object?>)
            PendingCard.fromJson(Map<String, Object?>.from(c! as Map<Object?, Object?>)),
        ],
        decided: (json['decided'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 0,
      );

  final List<PendingCard> cards;
  final int decided;
  final int total;
}

/// §7 over HTTP.
class GenerationApi {
  const GenerationApi(this.api);

  final Api api;

  /// A pre-signed PUT. The file goes straight to storage, never through the
  /// API (§7.2).
  Future<({String uploadKey, String url})> createUpload(String contentType) async {
    final body = await api.post('/v1/generation/uploads', body: {'content_type': contentType});
    return (uploadKey: body['upload_key']! as String, url: body['url']! as String);
  }

  /// Uploads bytes straight to storage.
  ///
  /// Not through our API (§7.2): a forty-megabyte PDF would otherwise be held
  /// in the request handler's memory on its way past. The URL is pre-signed
  /// and carries the content type, so the PUT must use the same one it was
  /// signed for or the signature does not match.
  Future<void> upload(
    String url,
    Uint8List bytes,
    String contentType, {
    http.Client? client,
  }) async {
    final owned = client == null;
    final http_ = client ?? http.Client();
    try {
      final response = await http_.put(
        Uri.parse(url),
        headers: {'content-type': contentType},
        body: bytes,
      );
      if (response.statusCode >= 400) {
        throw ApiException(response.statusCode, detail: 'upload failed');
      }
    } on http.ClientException catch (e) {
      throw Offline(e);
    } finally {
      if (owned) http_.close();
    }
  }

  /// Asks for a generation. Throws [ApiException] with `isQuotaExhausted`
  /// when the single free generation is spent — that is the paywall, not an
  /// error (§7.7).
  Future<GenerationJob> create({
    required String sourceType,
    required String targetDeckId,
    String? topic,
    String? uploadKey,
    int requestedCount = 10,
    String level = 'intermediario',
  }) async {
    final body = await api.post('/v1/generation/jobs', body: {
      'source_type': sourceType,
      'target_deck_id': targetDeckId,
      if (topic != null) 'topic': topic,
      if (uploadKey != null) 'upload_key': uploadKey,
      'requested_count': requestedCount,
      'level': level,
    });
    return GenerationJob.fromJson(body);
  }

  Future<GenerationJob> get(String jobId) async =>
      GenerationJob.fromJson(await api.get('/v1/generation/jobs/$jobId'));

  Future<ApprovalQueue> queue(String jobId) async =>
      ApprovalQueue.fromJson(await api.get('/v1/generation/jobs/$jobId/queue'));

  Future<PendingCard> decide(String pendingId, String? decision) async {
    final body = await api.post(
      '/v1/generation/pending/$pendingId',
      body: {'decision': decision},
    );
    return PendingCard.fromJson(body);
  }

  Future<int> approveRemaining(String jobId) async {
    final body = await api.post('/v1/generation/jobs/$jobId/approve-all');
    return (body['created']! as num).toInt();
  }

  /// Approved rows become real cards. Idempotent, so a retry after a dropped
  /// connection is safe (§7.8).
  Future<int> close(String jobId) async {
    final body = await api.post('/v1/generation/jobs/$jobId/close');
    return (body['created']! as num).toInt();
  }

  /// §5.13's indicator. A cache of the server's answer, never the authority.
  Future<({int remaining, int limit, String plan})> quota() async {
    final body = await api.get('/v1/quota/');
    return (
      remaining: (body['remaining']! as num).toInt(),
      limit: (body['limit']! as num).toInt(),
      plan: body['plan']! as String,
    );
  }
}
