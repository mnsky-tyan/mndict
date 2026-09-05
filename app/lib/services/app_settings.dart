import 'package:shared_preferences/shared_preferences.dart';

enum PromptStyle { llama3, chatml, gemma, qwen3, phi, lfm25, lfm25tuned, gemma4, minicpm5, nemotron3 }

class ModelConfig {
  final String name;
  final String url;
  final String filename;
  final PromptStyle promptStyle;
  final double sizeMB;

  // Optional speculative-decoding draft model (downloaded alongside the main
  // model when present). Opt-in via specDecoding: the base-distilled DSpark
  // draft accepts only ~30% on structured dictionary entries, which measured
  // SLOWER than plain decode on desktop (32.1 vs 45.6 t/s) and on device
  // (10.4 vs 36.8 t/s). Re-enable per model once a draft is distilled on the
  // tuned model.
  final bool specDecoding;
  final String? draftUrl;
  final String? draftFilename;
  final double draftSizeMB;

  const ModelConfig({
    required this.name,
    required this.url,
    required this.filename,
    required this.promptStyle,
    required this.sizeMB,
    this.specDecoding = false,
    this.draftUrl,
    this.draftFilename,
    this.draftSizeMB = 0,
  });
}

class AppSettings {
  static const String _keyFontSize = 'fontSize';
  static const String _keyIsDarkMode = 'isDarkMode';
  static const String _keySelectedModel = 'selected_model';
  static const String _keyCoins = 'coins';
  static const String _keyTemperature = 'temperature';
  static const String _keyTopP = 'top_p';
  static const String _keyTopK = 'top_k';

  static const List<ModelConfig> availableModels = [
    // --- 2026-09 model bake-off candidates (docs/on-device-llm-research-2026-09.md) ---
    ModelConfig(
      name: 'LFM2.5 1.2B PILOT (LoRA Q4_0)',
      // Local-LAN build served from the dev PC (training/out/); not a public URL.
      // Q4_0: 4.6x faster prefill + ~1.5x faster decode than Q4_K_M on-device
      // (KleidiAI i8mm path); promptStyle lfm25tuned = byte-exact training prompt.
      // DSpark 296M draft: speculative decoding, measured +40% on desktop.
      url: 'http://192.168.0.116:8090/pilot-q40.gguf',
      filename: 'LFM2.5-Pilot-Q4_0.gguf',
      promptStyle: PromptStyle.lfm25tuned,
      sizeMB: 696,
      draftUrl: 'http://192.168.0.116:8090/DSpark-Q8_0.gguf',
      draftFilename: 'LFM2.5-DSpark-Q8_0.gguf',
      draftSizeMB: 302,
    ),
    ModelConfig(
      name: 'LFM2.5 1.2B',
      url: 'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
      filename: 'LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
      promptStyle: PromptStyle.lfm25,
      sizeMB: 731,
    ),
    ModelConfig(
      name: 'MiniCPM5 1B',
      url: 'https://huggingface.co/openbmb/MiniCPM5-1B-GGUF/resolve/main/MiniCPM5-1B-Q4_K_M.gguf',
      filename: 'MiniCPM5-1B-Q4_K_M.gguf',
      promptStyle: PromptStyle.minicpm5,
      sizeMB: 688,
    ),
    ModelConfig(
      name: 'Nemotron 3 Nano 4B',
      url: 'https://huggingface.co/nvidia/NVIDIA-Nemotron-3-Nano-4B-GGUF/resolve/main/NVIDIA-Nemotron3-Nano-4B-Q4_K_M.gguf',
      filename: 'NVIDIA-Nemotron3-Nano-4B-Q4_K_M.gguf',
      promptStyle: PromptStyle.nemotron3,
      sizeMB: 2837,
    ),
    ModelConfig(
      name: 'Gemma 4 E2B (QAT)',
      url: 'https://huggingface.co/google/gemma-4-E2B-it-qat-q4_0-gguf/resolve/main/gemma-4-E2B_q4_0-it.gguf',
      filename: 'gemma-4-E2B_q4_0-it.gguf',
      promptStyle: PromptStyle.gemma4,
      sizeMB: 3350,
    ),
    ModelConfig(
      name: 'LFM2.5 8B-A1B',
      url: 'https://huggingface.co/LiquidAI/LFM2.5-8B-A1B-GGUF/resolve/main/LFM2.5-8B-A1B-Q4_K_M.gguf',
      filename: 'LFM2.5-8B-A1B-Q4_K_M.gguf',
      promptStyle: PromptStyle.lfm25,
      sizeMB: 5156,
    ),
    // --- Legacy candidates (superseded by the bake-off set) ---
    ModelConfig(
      name: 'Reasoning Llama 1B',
      url: 'https://huggingface.co/tensorblock/Reasoning-Llama-1b-v0.1-GGUF/resolve/main/Reasoning-Llama-1b-v0.1-Q4_K_S.gguf',
      filename: 'Reasoning-Llama-1b-v0.1-Q4_K_S.gguf',
      promptStyle: PromptStyle.llama3,
      sizeMB: 1300,
    ),
    ModelConfig(
      name: 'LFM2 2.6B',
      url: 'https://huggingface.co/LiquidAI/LFM2-2.6B-GGUF/resolve/main/LFM2-2.6B-Q4_K_M.gguf',
      filename: 'LFM2-2.6B-Q4_K_M.gguf',
      promptStyle: PromptStyle.chatml,
      sizeMB: 2110,
    ),
    ModelConfig(
      name: 'LFM2 2.6B (Q2)',
      url: 'https://huggingface.co/DevQuasar/LiquidAI.LFM2-2.6B-GGUF/resolve/main/LiquidAI.LFM2-2.6B.Q2_K.gguf',
      filename: 'LiquidAI.LFM2-2.6B.Q2_K.gguf',
      promptStyle: PromptStyle.chatml,
      sizeMB: 938,
    ),
    ModelConfig(
      name: 'Gemma 3 270M',
      url: 'https://huggingface.co/unsloth/gemma-3-270m-it-GGUF/resolve/main/gemma-3-270m-it-Q4_K_M.gguf',
      filename: 'gemma-3-270m-it-Q4_K_M.gguf',
      promptStyle: PromptStyle.gemma,
      sizeMB: 253,
    ),
    ModelConfig(
      name: 'Qwen 3 0.6B',
      url: 'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q5_K_M.gguf',
      filename: 'Qwen3-0.6B-Q5_K_M.gguf',
      promptStyle: PromptStyle.qwen3,
      sizeMB: 600, // Approx
    ),
    ModelConfig(
      name: 'Nano Phi 115M',
      url: 'https://huggingface.co/tensorblock/nano-phi-115M-v0.1-GGUF/resolve/main/nano-phi-115M-v0.1-Q5_K_M.gguf',
      filename: 'nano-phi-115M-v0.1-Q5_K_M.gguf',
      promptStyle: PromptStyle.phi,
      sizeMB: 87,
    ),
  ];

  late SharedPreferences _prefs;
  
  double _fontSize = 14.5;
  bool _isDarkMode = false;
  String _selectedModelFilename = availableModels.first.filename;
  
  // New Settings
  int _coins = 0;
  // Greedy by default: dictionary entries should be deterministic, and
  // speculative decoding accepts drafts against the sampled token - sampling
  // at temperature > 0 collapses the draft acceptance rate (measured on
  // device 2026-09-05: ~11 t/s at temp 0.8 vs 36.8 t/s plain decode).
  double _temperature = 0.0;
  double _topP = 0.95;
  int _topK = 40;

  double get fontSize => _fontSize;
  bool get isDarkMode => _isDarkMode;
  String get selectedModelFilename => _selectedModelFilename;
  
  int get coins => _coins;
  double get temperature => _temperature;
  double get topP => _topP;
  int get topK => _topK;

  ModelConfig get currentModelConfig {
    return availableModels.firstWhere(
      (m) => m.filename == _selectedModelFilename,
      orElse: () => availableModels.first,
    );
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _fontSize = _prefs.getDouble(_keyFontSize) ?? 14.5;
    _isDarkMode = _prefs.getBool(_keyIsDarkMode) ?? false;
    _selectedModelFilename = _prefs.getString(_keySelectedModel) ?? availableModels.first.filename;
    
    _coins = _prefs.getInt(_keyCoins) ?? 0;
    _temperature = _prefs.getDouble(_keyTemperature) ?? 0.0;
    _topP = _prefs.getDouble(_keyTopP) ?? 0.95;
    _topK = _prefs.getInt(_keyTopK) ?? 40;
    _threadCount = _prefs.getInt(_keyThreadCount) ?? 4;
  }

  Future<void> setFontSize(double size) async {
    _fontSize = size;
    await _prefs.setDouble(_keyFontSize, size);
  }

  Future<void> setDarkMode(bool isDark) async {
    _isDarkMode = isDark;
    await _prefs.setBool(_keyIsDarkMode, isDark);
  }
  
  Future<void> setSelectedModel(String filename) async {
    _selectedModelFilename = filename;
    await _prefs.setString(_keySelectedModel, filename);
  }

  Future<void> addCoins(int amount) async {
    _coins += amount;
    await _prefs.setInt(_keyCoins, _coins);
  }

  Future<void> setModelParams({double? temp, double? p, int? k}) async {
    if (temp != null) {
      _temperature = temp;
      await _prefs.setDouble(_keyTemperature, temp);
    }
    if (p != null) {
      _topP = p;
      await _prefs.setDouble(_keyTopP, p);
    }
    if (k != null) {
      _topK = k;
      await _prefs.setInt(_keyTopK, k);
    }
  }

  // Thread Count
  int _threadCount = 4;
  static const String _keyThreadCount = 'thread_count';
  int get threadCount => _threadCount;

  Future<void> setThreadCount(int count) async {
    _threadCount = count;
    await _prefs.setInt(_keyThreadCount, count);
  }
}
