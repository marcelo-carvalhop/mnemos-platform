import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:sync_client/sync_client.dart';
import 'package:test/test.dart';

/// A client that answers from a script and records what it was asked.
class FakeHttp extends http.BaseClient {
  FakeHttp(this.handler);

  final FutureOr<http.Response> Function(http.Request request) handler;
  final List<http.Request> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final typed = request as http.Request;
    requests.add(typed);
    final response = await handler(typed);
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
    );
  }
}

http.Response ok(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

http.Response fail(int status, {String? detail}) => http.Response(
      jsonEncode({if (detail != null) 'detail': detail}),
      status,
      headers: {'content-type': 'application/json'},
    );

Api apiWith(FakeHttp http_, {TokenStore? tokens}) => Api(
      baseUrl: Uri.parse('https://example.test'),
      tokens: tokens ?? MemoryTokenStore(),
      client: http_,
    );

void main() {
  // -------------------------------------------------------------------------
  // Tokens
  // -------------------------------------------------------------------------

  group('authentication', () {
    test('a bearer token is attached when there is one', () async {
      final tokens = MemoryTokenStore();
      await tokens.write(access: 'the-token', refresh: 'r');
      final fake = FakeHttp((_) => ok({}));

      await apiWith(fake, tokens: tokens).get('/v1/quota/');

      expect(fake.requests.single.headers['authorization'], 'Bearer the-token');
    });

    test('a 401 refreshes once and replays the original request', () async {
      final tokens = MemoryTokenStore();
      await tokens.write(access: 'stale', refresh: 'good-refresh');

      var quotaCalls = 0;
      final fake = FakeHttp((request) {
        if (request.url.path == '/v1/auth/refresh') {
          return ok({'access_token': 'fresh', 'refresh_token': 'rotated', 'user_id': 'u'});
        }
        quotaCalls++;
        return request.headers['authorization'] == 'Bearer fresh'
            ? ok({'remaining': 1})
            : fail(401);
      });

      final body = await apiWith(fake, tokens: tokens).get('/v1/quota/');

      expect(body['remaining'], 1);
      expect(quotaCalls, 2, reason: 'once with the stale token, once with the fresh one');
      // §8.2 rotates on every refresh, so the stored pair must be the new one.
      expect(await tokens.readRefresh(), 'rotated');
    });

    test('concurrent 401s rotate the refresh token exactly once', () async {
      // §8.2 revokes an entire token family when a refresh token is replayed.
      // Six requests waking up against one stale access token would do exactly
      // that to themselves and log the user out.
      final tokens = MemoryTokenStore();
      await tokens.write(access: 'stale', refresh: 'good-refresh');

      var refreshes = 0;
      final fake = FakeHttp((request) async {
        if (request.url.path == '/v1/auth/refresh') {
          refreshes++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return ok({'access_token': 'fresh', 'refresh_token': 'rotated', 'user_id': 'u'});
        }
        return request.headers['authorization'] == 'Bearer fresh' ? ok({}) : fail(401);
      });

      final api = apiWith(fake, tokens: tokens);
      await Future.wait([for (var i = 0; i < 6; i++) api.get('/v1/quota/')]);

      expect(refreshes, 1);
    });

    test('a rejected refresh clears the tokens and says so once', () async {
      final tokens = MemoryTokenStore();
      await tokens.write(access: 'stale', refresh: 'revoked');
      var lost = 0;

      final fake = FakeHttp((request) =>
          request.url.path == '/v1/auth/refresh' ? fail(401) : fail(401));
      final api = apiWith(fake, tokens: tokens)..onAuthenticationLost = () => lost++;

      await expectLater(api.get('/v1/quota/'), throwsA(isA<ApiException>()));

      expect(await tokens.readAccess(), isNull);
      expect(await tokens.readRefresh(), isNull);
      expect(lost, 1);
    });

    test('the refresh call does not carry the token it is replacing', () async {
      final tokens = MemoryTokenStore();
      await tokens.write(access: 'stale', refresh: 'good');
      final fake = FakeHttp((request) => request.url.path == '/v1/auth/refresh'
          ? ok({'access_token': 'f', 'refresh_token': 'r', 'user_id': 'u'})
          : (request.headers['authorization'] == 'Bearer f' ? ok({}) : fail(401)));

      await apiWith(fake, tokens: tokens).get('/v1/quota/');

      final refresh = fake.requests.firstWhere((r) => r.url.path == '/v1/auth/refresh');
      expect(refresh.headers.containsKey('authorization'), isFalse);
    });

    test('registering a device needs no token at all', () async {
      final fake = FakeHttp((_) =>
          ok({'access_token': 'a', 'refresh_token': 'r', 'user_id': 'u', 'expires_in': 1}));
      final tokens = MemoryTokenStore();

      final userId = await AuthApi(apiWith(fake, tokens: tokens), tokens)
          .registerDevice(deviceId: 'd', platform: 'android');

      expect(userId, 'u');
      expect(fake.requests.single.headers.containsKey('authorization'), isFalse);
      expect(await tokens.readAccess(), 'a');
    });
  });

  // -------------------------------------------------------------------------
  // Failure shapes the app branches on
  // -------------------------------------------------------------------------

  group('failures', () {
    test('402 is the paywall, not an error', () async {
      final fake = FakeHttp((_) => fail(402, detail: 'quota exhausted'));

      await expectLater(
        GenerationApi(apiWith(fake)).create(sourceType: 'topic', targetDeckId: 'd', topic: 't'),
        throwsA(isA<ApiException>().having((e) => e.isQuotaExhausted, 'paywall', isTrue)),
      );
    });

    test('no network is Offline, which is ordinary rather than exceptional', () async {
      final fake = FakeHttp((_) => throw const SocketException('no route to host'));

      await expectLater(apiWith(fake).get('/v1/quota/'), throwsA(isA<Offline>()));
    });

    test('a timeout is offline too, not a server error', () async {
      final fake = FakeHttp((_) async {
        await Future<void>.delayed(const Duration(seconds: 5));
        return ok({});
      });
      final api = Api(
        baseUrl: Uri.parse('https://example.test'),
        tokens: MemoryTokenStore(),
        client: fake,
        timeout: const Duration(milliseconds: 20),
      );

      await expectLater(api.get('/v1/quota/'), throwsA(isA<Offline>()));
    });

    test('an HTML error page from a proxy is still a failure, just not ours', () async {
      final fake = FakeHttp((_) => http.Response('<html>502</html>', 502));

      await expectLater(
        apiWith(fake).get('/v1/quota/'),
        throwsA(isA<ApiException>().having((e) => e.isTransient, 'transient', isTrue)),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Sync (§6)
  // -------------------------------------------------------------------------

  group('sync transport', () {
    test('push carries the per-row sequences back', () async {
      // The gap that only appeared on wiring: without `assigned`, nothing can
      // clear the outbox and every row is pushed again forever.
      final fake = FakeHttp((_) => ok({
            'applied': 2,
            'skipped_stale': 0,
            'high_water': 7,
            'assigned': {'a': 6, 'b': 7},
          }));

      final result = await HttpSyncApi(apiWith(fake)).push(
        'decks',
        [
          {'id': 'a'},
          {'id': 'b'},
        ],
        'key',
      );

      expect(result.applied, 2);
      expect(result.assignedSeqs, {'a': 6, 'b': 7});
    });

    test('a server that sends no assignments does not crash the loop', () async {
      final fake = FakeHttp((_) => ok({'applied': 0, 'skipped_stale': 0, 'high_water': 0}));

      final result = await HttpSyncApi(apiWith(fake)).push('decks', [], 'key');

      expect(result.assignedSeqs, isEmpty);
    });

    test('pull passes the cursor and reads the page back', () async {
      final fake = FakeHttp((_) => ok({
            'table': 'cards',
            'rows': [
              {'id': 'x', 'server_seq': 4},
            ],
            'cursor': 4,
            'has_more': true,
          }));

      final page = await HttpSyncApi(apiWith(fake)).pull('cards', 2, 200);

      expect(fake.requests.single.url.queryParameters,
          {'table': 'cards', 'since': '2', 'limit': '200'});
      expect(page.rows.single['id'], 'x');
      expect(page.cursor, 4);
      expect(page.hasMore, isTrue);
    });

    test('409 becomes ResyncRequired, which the loop knows how to handle',
        () async {
      // §6.3 — the cursor predates the tombstone horizon, so an incremental
      // pull would silently miss deletions.
      final fake = FakeHttp((_) => fail(409, detail: 'cursor too old'));

      await expectLater(
        HttpSyncApi(apiWith(fake)).pull('cards', 1, 200),
        throwsA(isA<ResyncRequired>()),
      );
    });

    test('the idempotency key travels with the chunk', () async {
      final fake = FakeHttp((_) => ok({'applied': 0, 'high_water': 0, 'assigned': {}}));

      await HttpSyncApi(apiWith(fake)).push('decks', [], 'derived-key');

      final body = jsonDecode(fake.requests.single.body) as Map<String, Object?>;
      expect(body['idempotency_key'], 'derived-key');
    });
  });

  // -------------------------------------------------------------------------
  // Generation (§7)
  // -------------------------------------------------------------------------

  group('generation transport', () {
    test('a job carries the named stage the progress screen shows', () async {
      final fake = FakeHttp((_) => ok({
            'id': 'j',
            'status': 'generating',
            'stage': 'escrevendo os cards',
            'card_count': 0,
          }));

      final job = await GenerationApi(apiWith(fake)).get('j');

      // §5.5 — the server names the stage; the app does not invent copy.
      expect(job.stage, 'escrevendo os cards');
      expect(job.isFinished, isFalse);
    });

    test('a failed job carries a code the app can map to copy', () async {
      final fake = FakeHttp((_) => ok({
            'id': 'j',
            'status': 'failed',
            'stage': 'falhou',
            'error_code': 'topic_too_vague',
            'error_detail': 'Especifique o período.',
          }));

      final job = await GenerationApi(apiWith(fake)).get('j');

      expect(job.isFinished, isTrue);
      expect(job.isReady, isFalse);
      // §10 — a code, never the prose.
      expect(job.errorCode, 'topic_too_vague');
    });

    test('undo sends an explicit null rather than omitting the field', () async {
      // §5.7 makes undo mandatory; omitting `decision` would read as "no
      // change" instead of "un-decide".
      final fake = FakeHttp((_) => ok({
            'id': 'p',
            'front': 'f',
            'back': 'b',
            'tags': <String>[],
            'position': 0,
            'decision': null,
          }));

      await GenerationApi(apiWith(fake)).decide('p', null);

      final body = jsonDecode(fake.requests.single.body) as Map<String, Object?>;
      expect(body.containsKey('decision'), isTrue);
      expect(body['decision'], isNull);
    });

    test('the approval queue counts what is still undecided', () async {
      final fake = FakeHttp((_) => ok({
            'job_id': 'j',
            'total': 3,
            'decided': 1,
            'cards': [
              {'id': 'a', 'front': 'f', 'back': 'b', 'tags': ['t'], 'position': 0,
                'decision': 'approved'},
              {'id': 'b', 'front': 'f', 'back': 'b', 'tags': <String>[], 'position': 1,
                'decision': null},
              {'id': 'c', 'front': 'f', 'back': 'b', 'tags': <String>[], 'position': 2,
                'decision': null},
            ],
          }));

      final queue = await GenerationApi(apiWith(fake)).queue('j');

      expect(queue.total, 3);
      expect(queue.decided, 1);
      expect(queue.cards.where((c) => c.decision == null), hasLength(2));
      expect(queue.cards.first.tags, ['t']);
    });
  });

  // -------------------------------------------------------------------------
  // Uploads (§7.2)
  // -------------------------------------------------------------------------

  group('upload', () {
    test('goes to the pre-signed URL, not to our API', () async {
      // A forty-megabyte PDF must not pass through a request handler.
      final fake = FakeHttp((_) => http.Response('', 200));

      await GenerationApi(apiWith(fake))
          .upload('https://bucket.example/uploads/u/abc?sig=x',
              Uint8List.fromList([1, 2, 3]), 'application/pdf', client: fake);

      final request = fake.requests.single;
      expect(request.method, 'PUT');
      expect(request.url.host, 'bucket.example');
    });

    test('sends the content type the URL was signed for', () async {
      // The signature covers it; a different one is a 403 from storage.
      final fake = FakeHttp((_) => http.Response('', 200));

      await GenerationApi(apiWith(fake)).upload(
          'https://bucket.example/x', Uint8List.fromList([1]), 'image/jpeg',
          client: fake);

      expect(fake.requests.single.headers['content-type'], 'image/jpeg');
    });

    test('a rejected upload is an ApiException, not a silent success',
        () async {
      final fake = FakeHttp((_) => http.Response('AccessDenied', 403));

      await expectLater(
        GenerationApi(apiWith(fake)).upload(
            'https://bucket.example/x', Uint8List.fromList([1]), 'image/jpeg',
            client: fake),
        throwsA(isA<ApiException>()),
      );
    });

    test('no bearer token is sent to storage', () async {
      // The pre-signed URL is the credential. Attaching ours would leak it to
      // a host that is not us.
      final tokens = MemoryTokenStore();
      await tokens.write(access: 'secret', refresh: 'r');
      final fake = FakeHttp((_) => http.Response('', 200));

      await GenerationApi(apiWith(fake, tokens: tokens)).upload(
          'https://bucket.example/x', Uint8List.fromList([1]), 'image/jpeg',
          client: fake);

      expect(fake.requests.single.headers.containsKey('authorization'), isFalse);
    });
  });
}