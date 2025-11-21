import 'dart:async';
import 'dart:isolate';
import 'native_llama.dart';

enum LlamaStatus {
  ready,
  generating,
  done,
  error
}

class LlamaIsolate {
  Isolate? _isolate;
  SendPort? _sendPort;
  final StreamController<String> _tokenStreamController = StreamController.broadcast();
  final StreamController<LlamaStatus> _statusStreamController = StreamController.broadcast();

  Stream<String> get tokenStream => _tokenStreamController.stream;
  Stream<LlamaStatus> get statusStream => _statusStreamController.stream;

  Future<void> spawn() async {
    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateEntry, receivePort.sendPort);
    
    final completer = Completer<SendPort>();
    receivePort.listen((message) {
      if (message is SendPort) {
        completer.complete(message);
      } else if (message is String) {
        // Token received
        _tokenStreamController.add(message);
      } else if (message is Map && message['type'] == 'error') {
        _tokenStreamController.addError(message['message']);
      } else if (message is Map && message['type'] == 'done') {
        // Generation finished
        // We don't close the stream here because we might generate again
        // But we need to signal the UI. 
        // Since we are using a StreamController, we can't easily send a "done" event without closing it.
        // Instead, let's send a special token or just rely on the UI handling a custom event if we exposed it.
        // BUT, the UI listens to `tokenStream`.
        // Let's just close the controller? No, we reuse the isolate.
        // We should probably expose a separate status stream or just send a special marker.
        // Actually, the UI `listen` has `onDone`. If we close the controller, we can't reuse it.
        // Let's change the protocol: The UI should listen to a broadcast stream that stays open.
        // But `_isGenerating` needs to be set to false.
        // Let's send a special "[DONE]" token? No, that's hacky.
        // Let's add a `onDone` callback to `generate`? No, it's async.
        
        // BETTER APPROACH:
        // The `generate` method in `LlamaIsolate` returns a `Future`.
        // We can make that Future complete when generation is done?
        // No, `generate` just sends the command.
        
        // Let's add a `statusStream` to `LlamaIsolate`.
        _statusStreamController.add(LlamaStatus.done);
      }
    });

    _sendPort = await completer.future;
  }

  Future<void> loadModel(String modelPath, {
    int maxContextK = 2,
    int threadCount = 4,
    int maxTokens = 128,
    int loggingVerbosity = 1,
    int seed = -1,
  }) async {
    if (_sendPort == null) throw Exception("Isolate not spawned");
    _sendPort!.send({
      'command': 'load',
      'path': modelPath,
      'options': {
        'maxContextK': maxContextK,
        'threadCount': threadCount,
        'maxTokens': maxTokens,
        'loggingVerbosity': loggingVerbosity,
        'seed': seed,
      }
    });
  }

  Future<void> generate(String prompt, {int maxTokens = 2048}) async {
    if (_sendPort == null) throw Exception("Isolate not spawned");
    _sendPort!.send({
      'command': 'generate',
      'prompt': prompt,
      'maxTokens': maxTokens,
    });
  }

  void dispose() {
    _sendPort?.send({'command': 'dispose'});
    _isolate?.kill();
    _tokenStreamController.close();
  }

  static void _isolateEntry(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    final llama = LlamaNative();

    receivePort.listen((message) async {
      if (message is Map) {
        final command = message['command'];
        
        try {
          if (command == 'load') {
            final path = message['path'];
            final options = message['options'];
            
            final result = await llama.loadModel(
              path,
              threads: options['threadCount'],
              contextSizeK: options['maxContextK'],
              loggingVerbosity: options['loggingVerbosity'],
              seed: options['seed'],
            );
            if (result != 0) {
              mainSendPort.send({'type': 'error', 'message': 'Failed to load model: $result'});
            }
            
          } else if (command == 'generate') {
            final prompt = message['prompt'];
            final maxTokens = message['maxTokens'] ?? 2048;
            final result = await llama.generate(prompt, maxTokens: maxTokens);
            
            if (result != 0) {
              mainSendPort.send({'type': 'error', 'message': 'Generation failed: $result'});
              return;
            }

            await for (final token in llama.streamTokens()) {
              mainSendPort.send(token);
            }
            mainSendPort.send({'type': 'done'});
            
          } else if (command == 'dispose') {
            llama.dispose();
            Isolate.current.kill();
          }
        } catch (e) {
          mainSendPort.send({'type': 'error', 'message': e.toString()});
        }
      }
    });
  }
}
