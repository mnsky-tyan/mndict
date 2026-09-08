// Struct field names mirror the C declarations in
// artifacts/include/llama_native_api.h, which trips lowerCamelCase lints.
// ignore_for_file: non_constant_identifier_names
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

// C function signatures
typedef NativeInitModel = Int32 Function(Pointer<Utf8>, NativeInitOptions, Pointer<Pointer<Void>>);
typedef NativeGenerate = Int32 Function(Pointer<Void>, Pointer<Utf8>, NativeGenerateOptions);
typedef NativeStreamNextToken = Int32 Function(Pointer<Void>, Pointer<Pointer<Utf8>>);
typedef NativeFreeModel = Void Function(Pointer<Void>);
typedef NativeAttachDraft = Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32);

// Dart function signatures
typedef InitModel = int Function(Pointer<Utf8>, NativeInitOptions, Pointer<Pointer<Void>>);
typedef Generate = int Function(Pointer<Void>, Pointer<Utf8>, NativeGenerateOptions);
typedef StreamNextToken = int Function(Pointer<Void>, Pointer<Pointer<Utf8>>);
typedef FreeModel = void Function(Pointer<Void>);
typedef AttachDraft = int Function(Pointer<Void>, Pointer<Utf8>, int);

// Structs
final class NativeInitOptions extends Struct {
  @Int32()
  external int thread_count;
  @Int32()
  external int logging_verbosity;
  @Int32()
  external int seed;
  @Float()
  external double max_context_k;
}

final class NativeGenerateOptions extends Struct {
  @Int32()
  external int top_k;
  @Float()
  external double top_p;
  @Float()
  external double temperature;
  @Int32()
  external int max_tokens;
}

class LlamaNative {
  late DynamicLibrary _lib;
  late InitModel _initModel;
  late Generate _generate;
  late StreamNextToken _streamNextToken;
  late FreeModel _freeModel;
  late AttachDraft _attachDraft;

  Pointer<Void> _modelHandle = nullptr;

  LlamaNative() {
    if (Platform.isAndroid) {
      _lib = DynamicLibrary.open('libllama.so');
    } else {
      // Fallback or other platforms (not implemented for this task)
      throw UnsupportedError('Only Android is supported');
    }

    _initModel = _lib.lookupFunction<NativeInitModel, InitModel>('llama_native_init_model');
    _generate = _lib.lookupFunction<NativeGenerate, Generate>('llama_native_generate');
    _streamNextToken = _lib.lookupFunction<NativeStreamNextToken, StreamNextToken>('llama_native_stream_next_token');
    _freeModel = _lib.lookupFunction<NativeFreeModel, FreeModel>('llama_native_free_model');
    _attachDraft = _lib.lookupFunction<NativeAttachDraft, AttachDraft>('llama_native_attach_draft');
  }

  Future<int> loadModel(String modelPath, {
    int threads = 4,
    double contextSizeK = 2.0,
    int loggingVerbosity = 0,
    int seed = -1,
  }) async {
    if (_modelHandle != nullptr) {
      _freeModel(_modelHandle);
      _modelHandle = nullptr;
    }

    final pathPtr = modelPath.toNativeUtf8();
    final handlePtr = calloc<Pointer<Void>>();

    // Create options struct using calloc to ensure memory is allocated
    final optionsPtr = calloc<NativeInitOptions>();
    optionsPtr.ref.thread_count = threads;
    optionsPtr.ref.logging_verbosity = loggingVerbosity;
    optionsPtr.ref.seed = seed;
    optionsPtr.ref.max_context_k = contextSizeK;

    try {
      final result = _initModel(pathPtr, optionsPtr.ref, handlePtr);
      if (result == 0) {
        _modelHandle = handlePtr.value;
      }
      return result;
    } finally {
      calloc.free(pathPtr);
      calloc.free(handlePtr);
      calloc.free(optionsPtr);
    }
  }

  /// Attach a speculative-decoding draft model. Optional: on failure the
  /// handle keeps working in normal mode.
  Future<int> attachDraft(String draftPath, {int nDraftMax = 8}) async {
    if (_modelHandle == nullptr) return -1;
    final pathPtr = draftPath.toNativeUtf8();
    try {
      return _attachDraft(_modelHandle, pathPtr, nDraftMax);
    } finally {
      calloc.free(pathPtr);
    }
  }

  Future<int> generate(String prompt, {
    int topK = 40,
    double topP = 0.95,
    double temperature = 0.8,
    int maxTokens = 128,
  }) async {
    if (_modelHandle == nullptr) return -1;

    final promptPtr = prompt.toNativeUtf8();
    final optionsPtr = calloc<NativeGenerateOptions>();
    optionsPtr.ref.top_k = topK;
    optionsPtr.ref.top_p = topP;
    optionsPtr.ref.temperature = temperature;
    optionsPtr.ref.max_tokens = maxTokens;

    try {
      return _generate(_modelHandle, promptPtr, optionsPtr.ref);
    } finally {
      calloc.free(promptPtr);
      calloc.free(optionsPtr);
    }
  }

  Stream<String> streamTokens() async* {
    if (_modelHandle == nullptr) return;

    final tokenTextPtr = calloc<Pointer<Utf8>>();
    
    Stream<List<int>> byteStream() async* {
      while (true) {
        final result = _streamNextToken(_modelHandle, tokenTextPtr);
        if (result == 0) { // Success
          final ptr = tokenTextPtr.value.cast<Uint8>();
          int len = 0;
          while (ptr[len] != 0) {
            len++;
          }
          
          if (len > 0) {
            // Copy the bytes to a Dart Uint8List
            yield Uint8List.fromList(ptr.asTypedList(len));
          }
        } else if (result == -7) { // EOF (LLAMA_NATIVE_EOF)
          debugPrint("Native Llama: EOF reached");
          break;
        } else {
          debugPrint("Native Llama: Error $result");
          break;
        }
      }
    }

    try {
      yield* byteStream().transform(Utf8Decoder(allowMalformed: true));
    } finally {
      calloc.free(tokenTextPtr);
    }
  }

  void dispose() {
    if (_modelHandle != nullptr) {
      _freeModel(_modelHandle);
      _modelHandle = nullptr;
    }
  }

  bool get isLoaded => _modelHandle != nullptr;
}
