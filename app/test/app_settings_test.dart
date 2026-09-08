import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/services/app_settings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults after first launch', () async {
    final s = AppSettings();
    await s.init();
    expect(s.fontSize, 14.5);
    expect(s.isDarkMode, isFalse);
    expect(s.temperature, 0.0, reason: 'greedy by default for dictionaries');
    expect(s.topP, 0.95);
    expect(s.topK, 40);
    expect(s.threadCount, 4);
    expect(s.coins, 0);
    expect(s.selectedModelFilename, AppSettings.availableModels.first.filename);
  });

  test('selected model round-trips through prefs', () async {
    final first = AppSettings();
    await first.init();
    final target = AppSettings.availableModels[1];
    await first.setSelectedModel(target.filename);
    expect(first.currentModelConfig.filename, target.filename);

    final second = AppSettings();
    await second.init();
    expect(second.selectedModelFilename, target.filename);
    expect(second.currentModelConfig.name, target.name);
  });

  test('unknown persisted filename falls back to the first model', () async {
    SharedPreferences.setMockInitialValues({'selected_model': 'gone.gguf'});
    final s = AppSettings();
    await s.init();
    expect(s.currentModelConfig, same(AppSettings.availableModels.first));
  });

  test('model params round-trip', () async {
    final first = AppSettings();
    await first.init();
    await first.setModelParams(temp: 0.4, p: 0.8, k: 5);
    expect(first.temperature, 0.4);
    expect(first.topP, 0.8);
    expect(first.topK, 5);

    final second = AppSettings();
    await second.init();
    expect(second.temperature, 0.4);
    expect(second.topP, 0.8);
    expect(second.topK, 5);
  });

  test('coins accumulate', () async {
    final s = AppSettings();
    await s.init();
    await s.addCoins(1);
    await s.addCoins(2);
    expect(s.coins, 3);
  });

  test('thread count and appearance round-trip', () async {
    final first = AppSettings();
    await first.init();
    await first.setThreadCount(6);
    await first.setDarkMode(true);
    await first.setFontSize(18);

    final second = AppSettings();
    await second.init();
    expect(second.threadCount, 6);
    expect(second.isDarkMode, isTrue);
    expect(second.fontSize, 18);
  });
}
