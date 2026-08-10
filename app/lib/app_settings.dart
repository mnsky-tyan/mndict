import 'package:shared_preferences/shared_preferences.dart';

enum PromptStyle { llama3, chatml, gemma, qwen3, phi }

class ModelConfig {
  final String name;
  final String url;
  final String filename;
  final PromptStyle promptStyle;
  final double sizeMB;

  const ModelConfig({
    required this.name,
    required this.url,
    required this.filename,
    required this.promptStyle,
    required this.sizeMB,
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
  
  double _fontSize = 16.0;
  bool _isDarkMode = false;
  String _selectedModelFilename = availableModels.first.filename;
  
  // New Settings
  int _coins = 0;
  double _temperature = 0.8;
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
    _fontSize = _prefs.getDouble(_keyFontSize) ?? 16.0;
    _isDarkMode = _prefs.getBool(_keyIsDarkMode) ?? false;
    _selectedModelFilename = _prefs.getString(_keySelectedModel) ?? availableModels.first.filename;
    
    _coins = _prefs.getInt(_keyCoins) ?? 0;
    _temperature = _prefs.getDouble(_keyTemperature) ?? 0.8;
    _topP = _prefs.getDouble(_keyTopP) ?? 0.95;
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
