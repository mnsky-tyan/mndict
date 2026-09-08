import 'dart:async';
import 'dart:io';
import 'app_settings.dart';
import 'llama_isolate.dart';
import 'model_downloader.dart';
import 'prompts.dart';

class DictionaryService {
  final LlamaIsolate _llama = LlamaIsolate();
  final ModelDownloader _downloader = ModelDownloader();
  final AppSettings settings;

  bool isModelLoaded = false;
  bool isGenerating = false;
  String? _currentModelPath;
  
  final StreamController<String> _tokenStreamController = StreamController.broadcast();
  Stream<String> get tokenStream => _tokenStreamController.stream;

  final StreamController<String> _statusStreamController = StreamController.broadcast();
  Stream<String> get statusStream => _statusStreamController.stream;

  DictionaryService(this.settings);

  Future<void> init() async {
    await _llama.spawn();
    
    _llama.statusStream.listen((status) {
      _statusStreamController.add(status.name); // Forward status name
      if (status == LlamaStatus.done) {
        isGenerating = false;
      }
    });
    
    // Auto-load model if available
    await checkAndLoadModel();
  }

  Future<void> checkAndLoadModel() async {
    final filename = settings.selectedModelFilename;
    _statusStreamController.add("Checking model: $filename");

    final isDownloaded = await _downloader.isModelDownloaded(filename);
    if (isDownloaded) {
      final path = await _downloader.getModelPath(filename);
      if (!isModelLoaded || _currentModelPath != path) {
        await loadModel(path);
      }
      // Speculative-decoding draft: fetch once in the background if missing.
      _ensureDraftDownloaded();
    } else {
      _statusStreamController.add("Model not found. Please download in settings.");
      isModelLoaded = false;
    }
  }

  Future<void> _ensureDraftDownloaded() async {
    final config = settings.currentModelConfig;
    final draftName = config.draftFilename;
    if (!config.specDecoding || draftName == null || config.draftUrl == null) return;
    if (await _downloader.isModelDownloaded(draftName)) return;
    _statusStreamController.add("Downloading draft model (${config.draftSizeMB} MB)...");
    try {
      await _downloader.downloadModel(config.draftUrl!, draftName, (_) {});
      _statusStreamController.add("Draft model ready");
    } catch (e) {
      _statusStreamController.add("Draft download failed (decoding unaffected)");
    }
  }

  Future<String?> _draftPathOrNull() async {
    final config = settings.currentModelConfig;
    final draftName = config.draftFilename;
    if (!config.specDecoding || draftName == null) return null;
    if (!await _downloader.isModelDownloaded(draftName)) return null;
    return _downloader.getModelPath(draftName);
  }

  Future<void> loadModel(String path) async {
    _statusStreamController.add("Loading Model...");
    final draftPath = await _draftPathOrNull();
    try {
      await _llama.loadModel(
        path,
        maxContextK: 1.0, // Increased to 1024 tokens (1.0K) to avoid overflow
        threadCount: settings.threadCount,
        maxTokens: 2048,
        loggingVerbosity: 1,
        draftPath: draftPath,
      );
      isModelLoaded = true;
      _currentModelPath = path;
      _statusStreamController.add("Model Loaded");
      
      // Warmup to ensure first token is fast
      _statusStreamController.add("Warming up...");
      await _llama.warmup();
      _statusStreamController.add("Ready");
    } catch (e) {
      _statusStreamController.add("Failed to load model: $e");
      isModelLoaded = false;
      // Self-heal: a corrupt/partial file fails native load every time it is
      // selected. Delete it so the next attempt re-downloads — but only when
      // the failure blames the file itself. An OOM failure (-1) would delete
      // a multi-GB model and still fail after the re-download.
      if (_isFatalModelFileError(e)) {
        try {
          final f = File(path);
          if (await f.exists()) {
            await f.delete();
            _statusStreamController.add("Corrupt model file deleted. Download it again.");
          }
        } catch (_) {}
      }
    }
  }

  /// Native load failure codes that mean the file itself is unusable, so a
  /// re-download can help. Codes mirror artifacts/include/llama_native_api.h:
  /// -2 FILE_NOT_FOUND (also returned for unreadable/corrupt GGUFs),
  /// -3 UNSUPPORTED_FORMAT, -4 CORRUPT_FILE.
  static bool _isFatalModelFileError(Object e) {
    final match = RegExp(r'code (-?\d+)').firstMatch(e.toString());
    final code = match == null ? null : int.tryParse(match.group(1)!);
    return code == -2 || code == -3 || code == -4;
  }

  Future<void> searchWord(String word) async {
    if (!isModelLoaded) {
      _tokenStreamController.addError("Model not loaded");
      return;
    }
    if (isGenerating) return;

    isGenerating = true;
    final config = settings.currentModelConfig;

    // Force reload for Gemma to clear context and prevent degradation
    if (config.promptStyle == PromptStyle.gemma && _currentModelPath != null) {
       await loadModel(_currentModelPath!);
    }

    final prompt = buildLookupPrompt(config.promptStyle, word);

    StreamSubscription? sub;
    StreamSubscription? statusSub;
    final completer = Completer<void>();
    
    bool isThinking = false;

    // Listen to the isolate's stream directly for this request
    sub = _llama.tokenStream.listen((token) {
      // Styles whose models may emit <think>...</think> spontaneously
      // (LFM2.5-8B-A1B reasons by default; the others are safety nets).
      const thinkingStyles = {
        PromptStyle.qwen3,
        PromptStyle.lfm25,
        PromptStyle.minicpm5,
        PromptStyle.nemotron3,
      };
      if (thinkingStyles.contains(config.promptStyle)) {
        if (token.contains("<think>")) {
          isThinking = true;
          // User requested to disable thinking process display by default
          // We just swallow the tokens until </think>
        }
        
        if (isThinking) {
          if (token.contains("</think>")) {
            isThinking = false;
            // If there is content after </think>, we should stream it.
            final parts = token.split("</think>");
            if (parts.length > 1) {
              _tokenStreamController.add(parts[1]);
            }
            return;
          }
          // Swallow thinking tokens
          return; 
        }
      }
      
      // Stream directly to UI
      _tokenStreamController.add(token);
    }, onError: (e) {
      _tokenStreamController.addError(e);
      if (!completer.isCompleted) completer.complete(); // Stop waiting on error
    });

    // Listen for completion or error
    statusSub = _llama.statusStream.listen((status) {
      if (status == LlamaStatus.done || status == LlamaStatus.error) {
        if (!completer.isCompleted) completer.complete();
      }
    });

    try {
      // Check if reload succeeded
      if (!isModelLoaded) {
         throw Exception("Model failed to reload");
      }

      await _llama.generate(
        prompt, 
        maxTokens: 1024,
        temperature: settings.temperature,
        topP: settings.topP,
        topK: settings.topK,
      );
      
      // Wait for completion signal with timeout
      await completer.future.timeout(const Duration(seconds: 120));
      
    } catch (e) {
      if (e is TimeoutException) {
        _tokenStreamController.add("\n[Generation timed out]");
      } else {
        _tokenStreamController.addError(e);
      }
    } finally {
      isGenerating = false;
      sub.cancel();
      statusSub.cancel();
    }
  }

  Future<double> checkSimilarity(String word, String definition, String userInput) async {
    if (!isModelLoaded) return 0.0;
    // A lookup (or a previous check) still owns the model — a second
    // generate would interleave on the isolate.
    if (isGenerating) return 0.0;

    final config = settings.currentModelConfig;
    final prompt = buildSimilarityPrompt(
      config.promptStyle,
      word: word,
      definition: definition,
      userInput: userInput,
    );

    final completer = Completer<double>();
    String buffer = "";

    StreamSubscription? sub;
    // Listen to _llama.tokenStream directly
    sub = _llama.tokenStream.listen((token) {
      buffer += token;
    });

    StreamSubscription? statusSub;
    // Listen to _llama.statusStream directly
    statusSub = _llama.statusStream.listen((status) {
      if (status == LlamaStatus.done || status == LlamaStatus.error) {
        sub?.cancel();
        statusSub?.cancel();

        if (completer.isCompleted) return;
        final match = RegExp(r"0\.\d+|1\.0|0|1").firstMatch(buffer);
        completer.complete(match != null
            ? (double.tryParse(match.group(0)!) ?? 0.0)
            : 0.0);
      }
    });

    try {
      isGenerating = true;
      await _llama.generate(
        prompt,
        maxTokens: 10,
        temperature: settings.temperature,
        topP: settings.topP,
        topK: settings.topK,
      );
    } catch (e) {
      sub.cancel();
      statusSub.cancel();
      if (!completer.isCompleted) completer.complete(0.0);
    }

    // If the isolate never reports back, fail the check instead of hanging
    // the Test tab's spinner.
    return completer.future.timeout(const Duration(seconds: 60), onTimeout: () {
      sub?.cancel();
      statusSub?.cancel();
      return 0.0;
    });
  }

  void dispose() {
    _llama.dispose();
    _tokenStreamController.close();
    _statusStreamController.close();
  }
}
