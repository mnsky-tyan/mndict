import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'api_key_store.dart';
import 'app_settings.dart';
import 'prompts.dart';

/// Result of checking a candidate API key against the Gemini API.
enum KeyValidation { valid, invalid, networkError }

/// The cloud engine behind dictionary lookups: streams Gemini answers into
/// the same UI surface the local llama engine used (token deltas on
/// [tokenStream], status strings on [statusStream], plus the double-submit
/// guard and clear-mid-stream retirement the app relies on).
///
/// Bring-your-own-key: without a stored key nothing is sent anywhere — a
/// lookup surfaces the actionable settings state instead. There is no
/// compiled-in key and no fallback.
class GeminiService {
  /// Not a secret (fine in code); the API key is the secret.
  static const String model = 'gemini-3.6-flash';
  static const String baseUrl = 'https://generativelanguage.googleapis.com/v1beta';

  final ApiKeyStore _keys;
  final AppSettings settings;
  final Dio _dio;

  /// Parity with the local engine's lookup watchdog (120 s) and the Test
  /// tab's similarity watchdog (60 s). Injectable so tests don't wait.
  final Duration lookupTimeout;
  final Duration similarityTimeout;

  bool isGenerating = false;

  /// Surface parity with DictionaryService.isModelLoaded: true once init()
  /// found a stored key. Lookups re-read the store, so a key added in
  /// settings is picked up without restarting the app.
  bool isReady = false;

  final StreamController<String> _tokenController = StreamController.broadcast();
  Stream<String> get tokenStream => _tokenController.stream;

  final StreamController<String> _statusController = StreamController.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  GeminiService(
    this.settings, {
    ApiKeyStore? keys,
    Dio? dio,
    this.lookupTimeout = const Duration(seconds: 120),
    this.similarityTimeout = const Duration(seconds: 60),
  })  : _keys = keys ?? ApiKeyStore(),
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 30),
            ));

  /// Stream sinks that survive dispose: a lookup's watchdog can fire after
  /// teardown, and pushing into a closed controller throws.
  void _emitToken(String token) {
    if (!_tokenController.isClosed) _tokenController.add(token);
  }

  void _emitTokenError(Object e) {
    if (!_tokenController.isClosed) _tokenController.addError(e);
  }

  void _emitStatus(String status) {
    if (!_statusController.isClosed) _statusController.add(status);
  }

  Future<void> init() async {
    final key = await _keys.read();
    isReady = key != null;
    if (key != null) {
      _emitStatus('Ready');
    } else {
      _emitStatus('Error: No API key - add your Gemini key in Settings');
    }
  }

  Future<void> searchWord(String word) async {
    if (isGenerating) return;
    isGenerating = true;

    final key = await _keys.read();
    if (key == null) {
      isGenerating = false;
      // The gate IS the product: no call, just the way out.
      _emitStatus('Error: No API key - add your Gemini key in Settings');
      _emitTokenError(Exception(
          'No Gemini API key - open the side menu > API Key to add one.'));
      return;
    }

    // One-line privacy notice on the first cloud lookup, in the same slot
    // the Generating status uses so it stays visible for the whole lookup.
    if (!settings.cloudNoticeShown) {
      _emitStatus("Lookups are sent to Google's Gemini API.");
      await settings.markCloudNoticeShown();
    } else {
      _emitStatus('Generating');
    }

    StreamSubscription<void>? sub;
    try {
      sub = await _streamLookup(word, key);
      _emitStatus('done');
    } on TimeoutException {
      _emitToken('\n[Generation timed out]');
      _emitStatus('done');
    } on DioException catch (e) {
      final friendly = _friendlyNetworkError(e);
      _emitStatus('Error: $friendly');
      _emitTokenError(Exception(friendly));
    } catch (e) {
      _emitStatus('Error: $e');
      _emitTokenError(e);
    } finally {
      isGenerating = false;
      await sub?.cancel();
    }
  }

  /// POSTs the lookup and consumes the SSE response, emitting every
  /// candidate's parts[].text as a token. Returns the subscription so the
  /// caller can retire it when the watchdog fires.
  Future<StreamSubscription<void>> _streamLookup(String word, String key) async {
    final response = await _dio.post<ResponseBody>(
      '/models/$model:streamGenerateContent?alt=sse',
      options: Options(
        responseType: ResponseType.stream,
        headers: {'x-goog-api-key': key},
      ),
      data: lookupBody(word),
    );
    final body = response.data!;

    final completer = Completer<void>();
    final sub = body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        for (final text in textsFromSseLine(line)) {
          _emitToken(text);
        }
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    try {
      await completer.future.timeout(lookupTimeout);
    } on TimeoutException {
      await sub.cancel();
      rethrow;
    }
    return sub;
  }

  /// Request body for a streaming lookup. The system instruction is the
  /// shared [dictionarySystemPrompt] VERBATIM — that is what preserves the
  /// Definition/Examples/Synonyms/Antonyms format and the None abstention.
  static Map<String, dynamic> lookupBody(String word) => {
        'systemInstruction': {
          'parts': [
            {'text': dictionarySystemPrompt},
          ],
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': 'Define: $word'},
            ],
          },
        ],
        'generationConfig': {'temperature': 0, 'maxOutputTokens': 1024},
      };

  /// Non-streaming similarity score for the Test tab, mirroring the local
  /// engine's contract: 0.0 when busy, unkeyed, failing, or unparseable.
  Future<double> checkSimilarity(
      String word, String definition, String userInput) async {
    if (isGenerating) return 0.0;
    isGenerating = true;
    try {
      final key = await _keys.read();
      if (key == null) return 0.0;

      final response = await _dio
          .post<Map<String, dynamic>>(
            '/models/$model:generateContent',
            options: Options(headers: {'x-goog-api-key': key}),
            data: {
              'systemInstruction': {
                'parts': [
                  {
                    'text': similarityInstruction(word: word, definition: definition),
                  },
                ],
              },
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': 'User Definition: $userInput'},
                  ],
                },
              ],
              'generationConfig': {'temperature': 0, 'maxOutputTokens': 16},
            },
          )
          .timeout(similarityTimeout);

      return parseSimilarityScore(response.data);
    } catch (_) {
      return 0.0;
    } finally {
      isGenerating = false;
    }
  }

  /// Same parse the local engine used, applied to the joined part texts.
  static double parseSimilarityScore(Map<String, dynamic>? data) {
    if (data == null) return 0.0;
    final text = textsFromResponseJson(data).join();
    final match = RegExp(r'0\.\d+|1\.0|0|1').firstMatch(text);
    if (match == null) return 0.0;
    return double.tryParse(match.group(0)!) ?? 0.0;
  }

  /// Cheap credential check for the settings UI: listing models costs no
  /// generation tokens.
  static Future<KeyValidation> validateApiKey(String key, {Dio? dio}) async {
    final client = dio ??
        Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
        ));
    final owned = dio == null;
    try {
      await client.get<void>(
        '/models',
        options: Options(headers: {'x-goog-api-key': key.trim()}),
      );
      return KeyValidation.valid;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // Google answers a bad key with 400 ("API key not valid"), a
      // permission-less one with 401/403 — all mean "key rejected".
      if (status == 400 || status == 401 || status == 403) {
        return KeyValidation.invalid;
      }
      return KeyValidation.networkError;
    } catch (_) {
      return KeyValidation.networkError;
    } finally {
      if (owned) client.close();
    }
  }

  /// Reads one `data: {...}` SSE line into the text tokens it carries.
  /// Unknown or malformed lines are skipped, never fatal.
  static List<String> textsFromSseLine(String line) {
    if (!line.startsWith('data:')) return const [];
    final payload = line.substring(5).trim();
    if (payload.isEmpty || payload == '[DONE]') return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      return const [];
    }
    if (decoded is! Map<String, dynamic>) return const [];
    return textsFromResponseJson(decoded);
  }

  /// Extracts every candidate's parts[].text from one response chunk.
  static List<String> textsFromResponseJson(Map<String, dynamic> json) {
    final texts = <String>[];
    final candidates = json['candidates'];
    if (candidates is! List) return texts;
    for (final candidate in candidates) {
      if (candidate is! Map<String, dynamic>) continue;
      final content = candidate['content'];
      if (content is! Map<String, dynamic>) continue;
      final parts = content['parts'];
      if (parts is! List) continue;
      for (final part in parts) {
        if (part is! Map<String, dynamic>) continue;
        final text = part['text'];
        if (text is String && text.isNotEmpty) texts.add(text);
      }
    }
    return texts;
  }

  static String _friendlyNetworkError(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401 || status == 403) {
      return 'API key rejected - update it in Settings (side menu > API Key).';
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Network timeout - could not reach Gemini.';
      case DioExceptionType.connectionError:
        return 'Network error - check your connection.';
      default:
        return 'Request failed (HTTP $status).';
    }
  }

  void dispose() {
    _tokenController.close();
    _statusController.close();
    _dio.close();
  }
}
