import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/model_downloader.dart';

/// The download gate: a file that exists but is short must read as "not
/// downloaded", or a truncated GGUF gets handed to native load and dies
/// with a confusing "generation failed: -1".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late ModelDownloader downloader;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mndict_models');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => tmp.path);
    downloader = ModelDownloader();
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  test('missing file is not downloaded', () async {
    expect(await downloader.isModelDownloaded('model.gguf'), isFalse);
  });

  test('a full-size file passes with and without the expected size',
      () async {
    final path = await downloader.getModelPath('model.gguf');
    File(path).writeAsBytesSync(List.filled(10 * 1024 * 1024, 7));
    expect(await downloader.isModelDownloaded('model.gguf'), isTrue);
    expect(
        await downloader.isModelDownloaded('model.gguf', expectedMB: 10),
        isTrue);
  });

  test('a truncated file fails only when the expected size is known',
      () async {
    final path = await downloader.getModelPath('model.gguf');
    File(path).writeAsBytesSync(List.filled(1024, 7)); // a stub, not 10 MB
    expect(await downloader.isModelDownloaded('model.gguf'), isTrue,
        reason: 'no expectation passed — legacy behaviour (exists check)');
    expect(
        await downloader.isModelDownloaded('model.gguf', expectedMB: 10),
        isFalse,
        reason: 'bytes are under 95% of the catalog size');
  });

  test('5% head-room tolerates sizes rounded in the catalog', () async {
    final path = await downloader.getModelPath('model.gguf');
    // 9.7 MB against a catalog entry of 10 MB: within the 5% head-room.
    File(path).writeAsBytesSync(List.filled((9.7 * 1024 * 1024).round(), 7));
    expect(
        await downloader.isModelDownloaded('model.gguf', expectedMB: 10),
        isTrue);
  });
}
