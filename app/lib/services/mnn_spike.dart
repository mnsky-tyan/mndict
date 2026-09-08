// MNN in-app spike. Only active in MNN_SPIKE=1 flutter builds (CMake
// MNDICT_MNN_SPIKE / jni/mnn_spike.cpp): drives the MNN engine inside the app
// process over FFI and alternates real llama.cpp lookups through
// [DictionaryService], so both engines log "Decode summary" in the same
// process, same scheduling environment, same thermal window.
//
// print is deliberate: release-mode logcat surfacing for a spike.
// ignore_for_file: avoid_print
//
// Sideload the model dir first:
//   adb push mnn/models-mnn/lfm25-1.2b \
//     /sdcard/Android/data/com.example.app/files/mnn/lfm25-1.2b
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

import 'dictionary_service.dart';

const bool kMnnSpikeEnabled = bool.fromEnvironment('MNN_SPIKE');

// Same persona the production llama.cpp prompt uses (prompts.dart
// lfm25tuned); the headword itself rides as the user turn. MNN applies the
// model's own jinja template (llm_config.json), so no literal im_start here.
const String _systemPrompt =
    "You are a dictionary assistant. Explain the given word, phrase, "
    "idiom, or short sentence as a dictionary entry. If the headword is "
    "not a real English word or phrase, reply only: None.";

class MnnSpike {
  MnnSpike._();

  static DynamicLibrary? _lib;

  static DynamicLibrary get _dlib => _lib ??= DynamicLibrary.open('libmnnspike.so');

  // Bound first: all progress logging rides the native side because Dart
  // print() never reaches logcat in release builds.
  static final void Function(Pointer<Utf8>) _nativeLog = _dlib.lookupFunction<
      Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>('mnn_spike_log');

  static final int Function(Pointer<Utf8>) _create = _dlib
      .lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>(
          'mnn_spike_create');

  static final int Function(Pointer<Utf8>) _setConfig = _dlib
      .lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>(
          'mnn_spike_set_config');

  static final int Function() _load = _dlib
      .lookupFunction<Int32 Function(), int Function()>('mnn_spike_load');

  static final int Function(Pointer<Utf8>, int) _lookup = _dlib
      .lookupFunction<Int32 Function(Pointer<Utf8>, Int32),
          int Function(Pointer<Utf8>, int)>('mnn_spike_lookup');

  static final void Function() _destroy = _dlib
      .lookupFunction<Void Function(), void Function()>('mnn_spike_destroy');

  static int _withNativeStr(String s, int Function(Pointer<Utf8>) fn) {
    final p = s.toNativeUtf8();
    try {
      return fn(p);
    } finally {
      calloc.free(p);
    }
  }

  static const List<String> _words = ['serendipity', 'ephemeral', 'garrulous'];

  // power:high + greedy are the audited best config; memory:high measured as
  // a 3.5x regression (13 vs 46 t/s) so it stays off. The noeos dir decodes
  // exactly max_new_tokens (stop tokens patched out of its tokenizer) so its
  // output length matches llama.cpp's ~128-token entries — same event count
  // on both sides of the wall-clock comparison.
  static const Map<String, Object?> _best = {
    'power': 'high',
    'thread_num': 4,
    'memory': 'low',
    'sampler_type': 'greedy',
  };

  /// Legs interleave llama and the MNN configs so thermal drift hits all
  /// of them equally (audit rule: paired windows, never absolute numbers).
  static const List<(String, String, Map<String, Object?>?)> _legs = [
    ('llama', '', null),
    ('mnn-A', 'lfm25-1.2b', _best),
    ('mnn-noeos', 'lfm25-noeos', _best),
    ('llama', '', null),
    ('mnn-noeos', 'lfm25-noeos', _best),
    ('mnn-A', 'lfm25-1.2b', _best),
    ('llama', '', null),
  ];

  static Future<void> runSweep(DictionaryService llama) async {
    _log('sweep gated on: $kMnnSpikeEnabled');
    final ext = await getExternalStorageDirectory();
    if (ext == null) {
      _log('no external storage dir — cannot locate sideloaded model');
      return;
    }
    _log('model root: ${ext.path}/mnn exists=${Directory('${ext.path}/mnn').existsSync()}');
    await Future<void>.delayed(const Duration(seconds: 10));
    _log('=== MNN in-app sweep start (llama baseline interleaved) ===');
    int lookupIndex = 0;
    for (final (name, dir, cfg) in _legs) {
      if (cfg == null) {
        final word = _words[lookupIndex % _words.length];
        _log('--- leg $name: lookup "$word"');
        await llama.searchWord(word);
        lookupIndex++;
      } else {
        final configPath = '${ext.path}/mnn/$dir/llm_config.json';
        if (!File(configPath).existsSync()) {
          _log('leg $name: missing $configPath — skipped');
          continue;
        }
        _log('--- leg $name');
        _destroy();
        _check('create', _withNativeStr(configPath, _create));
        _check('set_config',
            _withNativeStr(jsonEncode({...cfg, 'system_prompt': _systemPrompt}), _setConfig));
        _check('load', _load());
        for (int rep = 0; rep < 3; rep++) {
          final w = _words[lookupIndex % _words.length];
          _withNativeStr(w, (p) => _lookup(p, 128));
          lookupIndex++;
          await Future<void>.delayed(const Duration(milliseconds: 1200));
        }
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    _destroy();
    _log('=== MNN in-app sweep done ===');
  }

  static void _check(String what, int code) {
    if (code != 0) _log('$what failed: $code');
  }

  static void _log(String msg) {
    try {
      final p = msg.toNativeUtf8();
      try {
        _nativeLog(p);
      } finally {
        calloc.free(p);
      }
    } catch (_) {
      print('[MnnSpike] $msg');
    }
  }
}
