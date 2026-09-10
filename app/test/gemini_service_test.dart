import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/services/api_key_store.dart';
import 'package:app/services/app_settings.dart';
import 'package:app/services/gemini_service.dart';
import 'package:app/services/prompts.dart';

/// In-memory key/value backend standing in for flutter_secure_storage.
class _MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _PlannedResponse {
  final int statusCode;
  final List<int> bytes;
  final bool stalled;

  _PlannedResponse(this.statusCode, this.bytes, {this.stalled = false});
}

/// dio adapter that replays canned responses and records every request, so
/// tests can assert on the wire format without hitting the network.
class _FakeAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  _PlannedResponse? next;

  void enqueue(_PlannedResponse response) => next = response;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final planned = next!;
    if (planned.stalled) {
      // A response whose headers arrived but whose body never advances:
      // exercises the service's watchdog, not the transport's.
      final controller = StreamController<Uint8List>();
      return ResponseBody(controller.stream, planned.statusCode,
          headers: {
            Headers.contentTypeHeader: ['text/event-stream'],
          });
    }
    return ResponseBody.fromBytes(
      Uint8List.fromList(planned.bytes),
      planned.statusCode,
      headers: {
        Headers.contentTypeHeader: [
          planned.statusCode == 200 ? 'application/json' : 'application/json',
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  AppSettings settings() => AppSettings();

  Future<GeminiService> serviceWith({
    required AppSettings settings,
    required _FakeAdapter adapter,
    _MemoryKeyValueStore? store,
    Duration lookupTimeout = const Duration(seconds: 120),
    Duration similarityTimeout = const Duration(seconds: 60),
  }) async {
    await settings.init();
    final dio = Dio(BaseOptions(baseUrl: GeminiService.baseUrl));
    dio.httpClientAdapter = adapter;
    return GeminiService(
      settings,
      keys: ApiKeyStore(store: store ?? _MemoryKeyValueStore()),
      dio: dio,
      lookupTimeout: lookupTimeout,
      similarityTimeout: similarityTimeout,
    );
  }

  _FakeAdapter sseAdapter(String body, {int status = 200}) {
    final adapter = _FakeAdapter();
    adapter.enqueue(_PlannedResponse(status, utf8.encode(body)));
    return adapter;
  }

  String sseChunk(Map<String, dynamic> json) => 'data: ${jsonEncode(json)}\n\n';

  group('SSE line parser', () {
    test('extracts parts[].text from a data line', () {
      final line = sseChunk({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'Definition'},
                {'text': ': a lucky find'},
              ],
              'role': 'model',
            },
            'index': 0,
          }
        ],
      });
      expect(GeminiService.textsFromSseLine(line),
          ['Definition', ': a lucky find']);
    });

    test('emits text from every candidate', () {
      final line = sseChunk({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'a'},
              ],
            },
          },
          {
            'content': {
              'parts': [
                {'text': 'b'},
              ],
            },
          },
        ],
      });
      expect(GeminiService.textsFromSseLine(line), ['a', 'b']);
    });

    test('skips non-data lines, [DONE], empty payloads and malformed JSON', () {
      expect(GeminiService.textsFromSseLine(': keep-alive'), isEmpty);
      expect(GeminiService.textsFromSseLine('event: ping'), isEmpty);
      expect(GeminiService.textsFromSseLine('data: [DONE]'), isEmpty);
      expect(GeminiService.textsFromSseLine('data:'), isEmpty);
      expect(GeminiService.textsFromSseLine('data: not json'), isEmpty);
    });

    test('chunks without text parts yield nothing (finishReason-only)', () {
      final line = sseChunk({
        'candidates': [
          {'finishReason': 'STOP', 'index': 0},
        ],
      });
      expect(GeminiService.textsFromSseLine(line), isEmpty);
    });

    test('empty text parts are dropped', () {
      final line = sseChunk({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': ''},
              ],
            },
          },
        ],
      });
      expect(GeminiService.textsFromSseLine(line), isEmpty);
    });
  });

  group('lookup wire format', () {
    test('carries the verbatim dictionary system prompt and Define: user turn',
        () async {
      final adapter = _FakeAdapter();
      adapter.enqueue(_PlannedResponse(200, utf8.encode('')));
      final store = _MemoryKeyValueStore();
      await store.write('gemini_api_key', 'k-test');
      final service = await serviceWith(settings: settings(), adapter: adapter, store: store);

      // Consume the (empty) stream so the request completes.
      service.tokenStream.listen((_) {}, onError: (_) {});
      service.statusStream.listen((_) {});
      await service.searchWord('serendipity');

      expect(adapter.requests, hasLength(1));
      final request = adapter.requests.single;
      expect(request.uri.host, 'generativelanguage.googleapis.com');
      expect(request.uri.path, '/v1beta/models/${GeminiService.model}:streamGenerateContent');
      expect(request.uri.queryParameters['alt'], 'sse');
      expect(request.headers['x-goog-api-key'], 'k-test');

      final body = request.data as Map<String, dynamic>;
      expect(body['systemInstruction']['parts'][0]['text'],
          dictionarySystemPrompt,
          reason: 'the entry format + None abstention ride on this string');
      expect(body['contents'][0]['parts'][0]['text'], 'Define: serendipity');
      expect(body['generationConfig']['temperature'], 0);
      expect(body['generationConfig']['maxOutputTokens'], 1024);
    });
  });

  group('streaming lookup', () {
    test('emits each part text as a token and finishes with done', () async {
      final body = [
        sseChunk({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Hel'},
                ],
              },
            }
          ],
        }),
        sseChunk({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'lo'},
                  {'text': ' world'},
                ],
              },
            }
          ],
        }),
        'data: not json\n\n',
        sseChunk({
          'candidates': [
            {'finishReason': 'STOP'},
          ],
        }),
      ].join();
      final adapter = sseAdapter(body);
      final store = _MemoryKeyValueStore();
      await store.write('gemini_api_key', 'k-test');
      final service = await serviceWith(settings: settings(), adapter: adapter, store: store);

      final tokens = <String>[];
      final statuses = <String>[];
      service.tokenStream.listen(tokens.add);
      service.statusStream.listen(statuses.add);

      await service.searchWord('test');
      await Future<void>.delayed(Duration.zero);

      expect(tokens, ['Hel', 'lo', ' world']);
      expect(statuses.last, 'done');
      expect(service.isGenerating, isFalse);
    });

    test('401/403 flips the status to the actionable key-rejected message',
        () async {
      final adapter = sseAdapter('{"error": {"code": 401}}', status: 401);
      final store = _MemoryKeyValueStore();
      await store.write('gemini_api_key', 'k-dead');
      final service = await serviceWith(settings: settings(), adapter: adapter, store: store);

      final statuses = <String>[];
      Object? tokenError;
      service.statusStream.listen(statuses.add);
      service.tokenStream.listen((_) {}, onError: (Object e) => tokenError = e);

      await service.searchWord('test');
      await Future<void>.delayed(Duration.zero);

      expect(statuses.where((s) => s.startsWith('Error')), isNotEmpty);
      expect(statuses.last, contains('API key rejected'));
      expect(tokenError, isNotNull);
      expect(tokenError.toString(), contains('update it in Settings'));
    });

    test('watchdog fires the [Generation timed out] token on a stalled stream',
        () async {
      final adapter = _FakeAdapter();
      adapter.enqueue(_PlannedResponse(200, const [], stalled: true));
      final store = _MemoryKeyValueStore();
      await store.write('gemini_api_key', 'k-test');
      final service = await serviceWith(
        settings: settings(),
        adapter: adapter,
        store: store,
        lookupTimeout: const Duration(milliseconds: 80),
      );

      final tokens = <String>[];
      final statuses = <String>[];
      service.tokenStream.listen(tokens.add);
      service.statusStream.listen(statuses.add);

      await service.searchWord('test');
      await Future<void>.delayed(Duration.zero);

      expect(tokens.last, '\n[Generation timed out]');
      expect(statuses.last, 'done');
      expect(service.isGenerating, isFalse);
    });

    test('a second submit while generating is dropped (double-submit guard)',
        () async {
      final adapter = _FakeAdapter();
      adapter.enqueue(_PlannedResponse(200, const [], stalled: true));
      final store = _MemoryKeyValueStore();
      await store.write('gemini_api_key', 'k-test');
      final service = await serviceWith(
        settings: settings(),
        adapter: adapter,
        store: store,
        lookupTimeout: const Duration(milliseconds: 80),
      );

      service.tokenStream.listen((_) {}, onError: (_) {});
      service.statusStream.listen((_) {});

      final first = service.searchWord('one');
      // The second call must return without queueing a second request.
      await service.searchWord('two');
      await first;

      expect(adapter.requests, hasLength(1));
    });
  });

  group('no-key gate', () {
    test('a lookup without a stored key never reaches the network', () async {
      final adapter = _FakeAdapter();
      final service = await serviceWith(settings: settings(), adapter: adapter);

      final statuses = <String>[];
      Object? tokenError;
      service.statusStream.listen(statuses.add);
      service.tokenStream.listen((_) {}, onError: (Object e) => tokenError = e);

      await service.searchWord('test');
      await Future<void>.delayed(Duration.zero);

      expect(adapter.requests, isEmpty, reason: 'the gate is the product');
      expect(service.isGenerating, isFalse);
      expect(statuses.last, startsWith('Error:'));
      expect(statuses.last, contains('API key'));
      expect(tokenError, isNotNull);
      expect(tokenError.toString(), contains('API Key'));
    });

    test('an empty/whitespace key counts as no key', () async {
      final adapter = _FakeAdapter();
      final store = _MemoryKeyValueStore();
      await store.write('gemini_api_key', '   ');
      final service =
          await serviceWith(settings: settings(), adapter: adapter, store: store);

      service.tokenStream.listen((_) {}, onError: (_) {});
      await service.searchWord('test');

      expect(adapter.requests, isEmpty);
    });

    test('init() surfaces the actionable state when the key is missing',
        () async {
      final service =
          await serviceWith(settings: settings(), adapter: _FakeAdapter());
      final statuses = <String>[];
      service.statusStream.listen(statuses.add);
      await service.init();
      await Future<void>.delayed(Duration.zero);
      expect(statuses.single, startsWith('Error:'));
      expect(service.isReady, isFalse);
    });

    test('init() reports Ready when a key exists', () async {
      final store = _MemoryKeyValueStore();
      await store.write('gemini_api_key', 'k-test');
      final service = await serviceWith(
          settings: settings(), adapter: _FakeAdapter(), store: store);
      final statuses = <String>[];
      service.statusStream.listen(statuses.add);
      await service.init();
      await Future<void>.delayed(Duration.zero);
      expect(statuses.single, 'Ready');
      expect(service.isReady, isTrue);
    });
  });

  group('privacy notice', () {
    test('the first cloud lookup shows the notice exactly once', () async {
      final adapter = _FakeAdapter();
      adapter.enqueue(_PlannedResponse(200, utf8.encode('')));
      final store = _MemoryKeyValueStore();
      await store.write('gemini_api_key', 'k-test');
      final s = settings();
      final service = await serviceWith(settings: s, adapter: adapter, store: store);

      final statuses = <String>[];
      service.tokenStream.listen((_) {}, onError: (_) {});
      service.statusStream.listen(statuses.add);

      await service.searchWord('one');
      await Future<void>.delayed(Duration.zero);
      expect(statuses.first, contains("Google's Gemini API"));
      expect(s.cloudNoticeShown, isTrue);

      // Second lookup: straight to Generating, no repeat notice.
      adapter.enqueue(_PlannedResponse(200, utf8.encode('')));
      statuses.clear();
      await service.searchWord('two');
      await Future<void>.delayed(Duration.zero);
      expect(statuses, ['Generating', 'done']);
    });
  });

  group('similarity (Test tab)', () {
    Map<String, dynamic> scoreResponse(String text) => {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': text},
                ],
              },
            }
          ],
        };

    test('parses the score out of a generateContent answer', () async {
      final adapter = _FakeAdapter();
      adapter.enqueue(
          _PlannedResponse(200, utf8.encode(jsonEncode(scoreResponse('0.85')))));
      final store = _MemoryKeyValueStore();
      await store.write('gemini_api_key', 'k-test');
      final service = await serviceWith(settings: settings(), adapter: adapter, store: store);

      final score = await service.checkSimilarity(
          'serendipity', 'a lucky find', 'good things by accident');

      expect(score, 0.85);
      final request = adapter.requests.single;
      expect(request.uri.path,
          '/v1beta/models/${GeminiService.model}:generateContent');
      final body = request.data as Map<String, dynamic>;
      expect(body['generationConfig']['maxOutputTokens'], 16);
      expect(body['systemInstruction']['parts'][0]['text'],
          similarityInstruction(
              word: 'serendipity', definition: 'a lucky find'));
      expect(body['contents'][0]['parts'][0]['text'],
          'User Definition: good things by accident');
    });

    test('falls back to 0.0 on unparseable answers', () async {
      final adapter = _FakeAdapter();
      adapter.enqueue(_PlannedResponse(
          200, utf8.encode(jsonEncode(scoreResponse('not a number')))));
      final store = _MemoryKeyValueStore();
      await store.write('gemini_api_key', 'k-test');
      final service = await serviceWith(settings: settings(), adapter: adapter, store: store);

      expect(
          await service.checkSimilarity('w', 'd', 'u'), 0.0);
    });

    test('returns 0.0 without a stored key and sends nothing', () async {
      final adapter = _FakeAdapter();
      final service = await serviceWith(settings: settings(), adapter: adapter);

      final score =
          await service.checkSimilarity('w', 'd', 'u');

      expect(score, 0.0);
      expect(adapter.requests, isEmpty);
    });

    test('watchdog returns 0.0 instead of hanging the Test tab', () async {
      final adapter = _FakeAdapter();
      adapter.enqueue(_PlannedResponse(200, const [], stalled: true));
      final store = _MemoryKeyValueStore();
      await store.write('gemini_api_key', 'k-test');
      final service = await serviceWith(
        settings: settings(),
        adapter: adapter,
        store: store,
        similarityTimeout: const Duration(milliseconds: 60),
      );

      expect(await service.checkSimilarity('w', 'd', 'u'), 0.0);
      expect(service.isGenerating, isFalse);
    });
  });

  group('validateApiKey (settings badge)', () {
    test('200 means the key works', () async {
      final adapter = _FakeAdapter();
      adapter.enqueue(_PlannedResponse(
          200, utf8.encode(jsonEncode({'models': []}))));
      final dio = Dio(BaseOptions(baseUrl: GeminiService.baseUrl));
      dio.httpClientAdapter = adapter;

      final result = await GeminiService.validateApiKey('k-good', dio: dio);

      expect(result, KeyValidation.valid);
      expect(adapter.requests.single.uri.path, '/v1beta/models');
      expect(adapter.requests.single.headers['x-goog-api-key'], 'k-good');
    });

    test('401/403/400 mean the key is rejected', () async {
      for (final status in [400, 401, 403]) {
        final adapter = _FakeAdapter();
        adapter.enqueue(_PlannedResponse(status, utf8.encode('{}')));
        final dio = Dio(BaseOptions(baseUrl: GeminiService.baseUrl));
        dio.httpClientAdapter = adapter;

        expect(await GeminiService.validateApiKey('k-bad', dio: dio),
            KeyValidation.invalid,
            reason: 'HTTP $status must read as "Key rejected"');
      }
    });

    test('server errors are network problems, not rejections', () async {
      final adapter = _FakeAdapter();
      adapter.enqueue(_PlannedResponse(500, utf8.encode('{}')));
      final dio = Dio(BaseOptions(baseUrl: GeminiService.baseUrl));
      dio.httpClientAdapter = adapter;

      expect(await GeminiService.validateApiKey('k', dio: dio),
          KeyValidation.networkError);
    });
  });

  group('ApiKeyStore', () {
    test('save/read/delete round-trip, trimmed', () async {
      final store = ApiKeyStore(store: _MemoryKeyValueStore());
      await store.save('  k-test-1234  ');
      expect(await store.read(), 'k-test-1234');

      await store.delete();
      expect(await store.read(), isNull);
    });

    test('mask keeps only the last 4 characters readable', () {
      expect(ApiKeyStore.mask('AIzaSyD1234567890'), '••••••••••••7890');
      expect(ApiKeyStore.mask('  abc  '), '••••abc');
    });

    test('reading through a throwing backend reads as no key', () async {
      final service = ApiKeyStore(store: _ThrowingStore());
      expect(await service.read(), isNull);
    });
  });
}

class _ThrowingStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async =>
      throw StateError('plugin missing');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('plugin missing');

  @override
  Future<void> delete(String key) async => throw StateError('plugin missing');
}
