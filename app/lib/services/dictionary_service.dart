import 'dart:async';
import 'dart:convert';
import 'app_settings.dart';
import 'llama_isolate.dart';
import 'model_downloader.dart';

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

  static const String _systemPrompt = """
You are a dictionary assistant. Output the definition in the following format:
Definition: [Definition]
Examples:
- [Example 1]
- [Example 2]
Synonyms: [Synonym 1], [Synonym 2]
Antonyms: [Antonym 1], [Antonym 2]
Do not use markdown formatting. Just plain text.
""";

  // Instruction carried in the system turn for the 2026 bake-off models:
  // strict format + explicit permission to abstain (the honesty play).
  static const String _dictionarySystemPrompt = "You are a dictionary assistant. Explain the given word, "
      "phrase, idiom, or short sentence. Reply in exactly this format:\n"
      "Definition: <definition>\n"
      "Examples:\n- <example sentence>\n- <example sentence>\n"
      "Synonyms: <comma-separated synonyms, or none>\n"
      "Antonyms: <comma-separated antonyms, or none>\n"
      "Plain text only, no markdown. "
      "If you are not certain the entry exists, or you don't know it, reply only: None.";

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
    } else {
      _statusStreamController.add("Model not found. Please download in settings.");
      isModelLoaded = false;
    }
  }

  Future<void> loadModel(String path) async {
    _statusStreamController.add("Loading Model...");
    try {
      await _llama.loadModel(
        path,
        maxContextK: 1.0, // Increased to 1024 tokens (1.0K) to avoid overflow
        threadCount: settings.threadCount,
        maxTokens: 2048,
        loggingVerbosity: 1,
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
    }
  }

  Future<void> searchWord(String word) async {
    if (!isModelLoaded) {
      _tokenStreamController.addError("Model not loaded");
      return;
    }
    if (isGenerating) return;

    isGenerating = true;
    final config = settings.currentModelConfig;
    String prompt;

    // Force reload for Gemma to clear context and prevent degradation
    if (config.promptStyle == PromptStyle.gemma && _currentModelPath != null) {
       await loadModel(_currentModelPath!);
    }

    if (config.promptStyle == PromptStyle.chatml) {
      prompt = 
        "<|im_start|>system\n"
        "$_systemPrompt<|im_end|>\n"
        "<|im_start|>user\n"
        "Define: $word<|im_end|>\n"
        "<|im_start|>assistant\n";
    } else if (config.promptStyle == PromptStyle.gemma) {
      prompt =
        // Gemma is BOS-sensitive: the <bos> token must start the prompt or
        // the model can end generation immediately.
        "<bos><start_of_turn>user\n"
        "Give a dictionary definition for the word: $word\n"
        "Include Definition, Examples, Synonyms, and Antonyms.<end_of_turn>\n"
        "<start_of_turn>model\n";
    } else if (config.promptStyle == PromptStyle.qwen3) {
      prompt = 
        "<|im_start|>system\n"
        "$_systemPrompt\n"
        "Use **bold** for headings (Definition, Examples, Synonyms, Antonyms).\n"
        "Do not output thinking process. Do not use <think> tags.<|im_end|>\n"
        "<|im_start|>user\n"
        "Define: $word /no_think<|im_end|>\n"
        "<|im_start|>assistant\n";
    } else if (config.promptStyle == PromptStyle.lfm25) {
      // LFM2.5: the GGUF's add_bos_token=true makes the tokenizer prepend
      // <|startoftext|> — a literal BOS here would double it.
      // Format reminder rides in the user turn: small models obey the user
      // turn far better than the system turn (locally verified 2026-09-05).
      prompt =
        "<|im_start|>system\n"
        "$_dictionarySystemPrompt<|im_end|>\n"
        "<|im_start|>user\n"
        "$word\n\n"
        "Use the exact entry format: numbered Meanings with a short sense "
        "label in parentheses, an Example block with bullet sentence(s) under "
        "each meaning, and Synonyms/Antonyms lines each formatted as: "
        "word - short gloss.<|im_end|>\n"
        "<|im_start|>assistant\n";
    } else if (config.promptStyle == PromptStyle.minicpm5) {
      // MiniCPM5: GGUF add_bos_token=false, so the template's <s> is included
      // literally. The empty <think> block is the model's own non-thinking
      // form (its template injects exactly this when thinking is disabled).
      prompt =
        "<s><|im_start|>system\n"
        "$_dictionarySystemPrompt<|im_end|>\n"
        "<|im_start|>user\n"
        "$word<|im_end|>\n"
        "<|im_start|>assistant\n<think>\n\n</think>\n\n";
    } else if (config.promptStyle == PromptStyle.nemotron3) {
      // Nemotron 3: Qwen-style template, no BOS; empty think block disables
      // its reasoning-by-default mode.
      prompt =
        "<|im_start|>system\n"
        "$_dictionarySystemPrompt<|im_end|>\n"
        "<|im_start|>user\n"
        "$word<|im_end|>\n"
        "<|im_start|>assistant\n<think></think>";
    } else if (config.promptStyle == PromptStyle.gemma4) {
      // Gemma-4 replaced <start_of_turn>/<end_of_turn> with <|turn>/<turn|>;
      // it has no system role, so the instruction rides in the user turn.
      // BOS <bos> is emitted unconditionally by the template.
      prompt =
        "<bos><|turn>user\n"
        "$_dictionarySystemPrompt\n\n"
        "$word<turn|>\n"
        "<|turn>model\n";
    } else if (config.promptStyle == PromptStyle.phi) {
      prompt = 
        "<|user|>\n"
        "$_systemPrompt\n"
        "Define: $word<|end|>\n"
        "<|assistant|>\n";
    } else {
      // Llama 3
      prompt = 
        "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n"
        "$_systemPrompt<|eot_id|>\n"
        "<|start_header_id|>user<|end_header_id|>\n\n"
        "Define: $word<|eot_id|>\n"
        "Define: $word<|eot_id|>\n"
        "<|start_header_id|>assistant<|end_header_id|>\n\n";
    }

    print("DEBUG: Prompt length: ${prompt.length}");
    print("DEBUG: Prompt content: $prompt");

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
      print("DEBUG: Token received: '$token'");
      _tokenStreamController.add(token);
    }, onError: (e) {
      print("DEBUG: Token stream error: $e");
      _tokenStreamController.addError(e);
      if (!completer.isCompleted) completer.complete(); // Stop waiting on error
    });

    // Listen for completion or error
    statusSub = _llama.statusStream.listen((status) {
      print("DEBUG: Status received: '$status'");
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
      sub?.cancel();
      statusSub?.cancel();
    }
  }

  Future<double> checkSimilarity(String word, String definition, String userInput) async {
    if (!isModelLoaded) return 0.0;
    
    final systemMsg = 
      "You are a semantic similarity checker. Compare the user's definition to the actual definition. "
      "Output ONLY a single number between 0.0 and 1.0 representing the similarity score. "
      "0.0 means completely wrong, 1.0 means perfect match. No other text.\n"
      "Word: $word\n"
      "Actual Definition: $definition";
      
    final userMsg = "User Definition: $userInput";

    final config = settings.currentModelConfig;
    String prompt;

    // The im_start/im_end turn structure is shared by chatml, LFM2.5,
    // MiniCPM5 and Nemotron 3.
    if (config.promptStyle == PromptStyle.chatml ||
        config.promptStyle == PromptStyle.lfm25 ||
        config.promptStyle == PromptStyle.minicpm5 ||
        config.promptStyle == PromptStyle.nemotron3) {
      prompt =
        "<|im_start|>system\n"
        "$systemMsg<|im_end|>\n"
        "<|im_start|>user\n"
        "$userMsg<|im_end|>\n"
        "<|im_start|>assistant\n";
    } else if (config.promptStyle == PromptStyle.gemma ||
        config.promptStyle == PromptStyle.gemma4) {
      final isGemma4 = config.promptStyle == PromptStyle.gemma4;
      prompt =
        "<bos>${isGemma4 ? '<|turn>user\n' : '<start_of_turn>user\n'}"
        "$systemMsg\n"
        "$userMsg${isGemma4 ? '<turn|>\n<|turn>model\n' : '<end_of_turn>\n<start_of_turn>model\n'}";
    } else if (config.promptStyle == PromptStyle.phi) {
      prompt = 
        "<|user|>\n"
        "$systemMsg\n"
        "$userMsg<|end|>\n"
        "<|assistant|>\n";
    } else {
      // Llama 3
      prompt = 
        "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n"
        "$systemMsg<|eot_id|>\n"
        "<|start_header_id|>user<|end_header_id|>\n\n"
        "$userMsg<|eot_id|>\n"
        "<|start_header_id|>assistant<|end_header_id|>\n\n";
    }

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
      if (status == LlamaStatus.done || !isGenerating) {
        sub?.cancel();
        statusSub?.cancel();
        
        final match = RegExp(r"0\.\d+|1\.0|0|1").firstMatch(buffer);
        if (match != null) {
          completer.complete(double.tryParse(match.group(0)!) ?? 0.0);
        } else {
          completer.complete(0.0);
        }
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
      completer.complete(0.0);
    }
    
    return completer.future;
  }

  void dispose() {
    _llama.dispose();
    _tokenStreamController.close();
    _statusStreamController.close();
  }
}
