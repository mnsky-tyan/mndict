import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'model_downloader.dart';
import 'llama_isolate.dart';
import 'dart:io';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  final LlamaIsolate _llama = LlamaIsolate();
  final ModelDownloader _downloader = ModelDownloader();
  
  static const String _modelUrl = "https://huggingface.co/tensorblock/Reasoning-Llama-1b-v0.1-GGUF/resolve/main/Reasoning-Llama-1b-v0.1-Q4_K_S.gguf";
  static const String _modelFilename = "Reasoning-Llama-1b-v0.1-Q4_K_S.gguf";

  bool _isModelLoaded = false;
  bool _isGenerating = false;
  String? _modelPath;
  String _statusMessage = "Checking for model...";
  double _downloadProgress = 0.0;

  Future<void> _checkExistingModel() async {
    final isDownloaded = await _downloader.isModelDownloaded(_modelFilename);
    if (isDownloaded) {
      final path = await _downloader.getModelPath(_modelFilename);
      await _loadModel(path);
    } else {
      setState(() {
        _statusMessage = "Model not found. Please download.";
      });
    }
  }

  final StringBuffer _responseBuffer = StringBuffer();
  final RegExp _garbageRegex = RegExp(r'<[^>]*?(?:idl|header|eot|user|assistant|system|end)[^>]*?>', caseSensitive: false);

  @override
  void initState() {
    super.initState();
    _initIsolate();
    _checkExistingModel();
  }

  Future<void> _initIsolate() async {
    await _llama.spawn();
    
    // Listen for tokens
    _llama.tokenStream.listen((token) {
      if (!_isGenerating) return;

      _responseBuffer.write(token);
      final text = _responseBuffer.toString();
      
      // Check for full match (Stop condition)
      final match = _garbageRegex.firstMatch(text);
      if (match != null) {
        // Found a stop tag!
        final cleanText = text.substring(0, match.start);
        setState(() {
          if (_messages.isNotEmpty && _messages.last['role'] == 'ai') {
            _messages.last['content'] = _messages.last['content']! + cleanText;
          }
          _isGenerating = false;
        });
        _responseBuffer.clear();
        _scrollToBottom();
        return;
      }

      // Check for partial match at the end (Buffering condition)
      // Heuristic: if the last index of '<' is within the last 20 chars
      final lastOpen = text.lastIndexOf('<');
      if (lastOpen != -1 && text.length - lastOpen < 20) {
        // Potential start of a tag, emit everything before it
        if (lastOpen > 0) {
          final safeChunk = text.substring(0, lastOpen);
          setState(() {
            if (_messages.isNotEmpty && _messages.last['role'] == 'ai') {
              _messages.last['content'] = _messages.last['content']! + safeChunk;
            }
          });
          
          // Keep the potential tag in buffer
          final remaining = text.substring(lastOpen);
          _responseBuffer.clear();
          _responseBuffer.write(remaining);
        }
        // If lastOpen == 0, we keep everything in buffer
      } else {
        // No potential tag, emit everything
        setState(() {
          if (_messages.isNotEmpty && _messages.last['role'] == 'ai') {
            _messages.last['content'] = _messages.last['content']! + text;
          }
        });
        _responseBuffer.clear();
      }
      _scrollToBottom();
    });

    // Listen for status
    _llama.statusStream.listen((status) {
      if (status == LlamaStatus.done) {
        // Flush remaining buffer if any
        if (_responseBuffer.isNotEmpty && _isGenerating) {
           setState(() {
            if (_messages.isNotEmpty && _messages.last['role'] == 'ai') {
              _messages.last['content'] = _messages.last['content']! + _responseBuffer.toString();
            }
          });
          _responseBuffer.clear();
        }
        
        setState(() {
          _isGenerating = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _llama.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickModel() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      String path = result.files.single.path!;
      await _loadModel(path);
    }
  }

  Future<void> _downloadModel() async {
    setState(() {
      _statusMessage = "Downloading Model...";
      _downloadProgress = 0.0;
    });

    try {
      await _downloader.downloadModel(_modelUrl, _modelFilename, (progress) {
        setState(() {
          _downloadProgress = progress;
        });
      });

      final path = await _downloader.getModelPath(_modelFilename);
      await _loadModel(path);
    } catch (e) {
      setState(() {
        _statusMessage = "Error: $e";
      });
    }
  }

  Future<void> _loadModel(String path) async {
    setState(() {
      _statusMessage = "Loading Model...";
    });

    try {
      await _llama.loadModel(
        path,
        maxContextK: 4, // 4096 tokens
        threadCount: 4,
        maxTokens: 2048, // Increased max tokens
        loggingVerbosity: 1,
      );
      
      setState(() {
        _isModelLoaded = true;
        _modelPath = path;
        _statusMessage = "Model Loaded: ${path.split('/').last}";
      });
    } catch (e) {
      setState(() {
        _statusMessage = "Failed to load model: $e";
      });
    }
  }

  void _sendMessage() async {
    if (_controller.text.isEmpty || !_isModelLoaded || _isGenerating) return;

    final text = _controller.text;
    _controller.clear();
    
    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _messages.add({'role': 'ai', 'content': ''});
      _isGenerating = true;
    });
    _responseBuffer.clear();
    _scrollToBottom();

    try {
      // Llama 3 Prompt Format (User Specified)
      final prompt = 
        "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n"
        "You are a helpful AI assistant.<|eot_id|>\n"
        "<|start_header_id|>user<|end_header_id|>\n\n"
        "$text<|eot_id|>\n"
        "<|start_header_id|>assistant<|end_header_id|>\n\n";
      
      await _llama.generate(prompt, maxTokens: 2048);
      
      // Tokens will be handled by the stream listener in initState
      
    } catch (e) {
      setState(() {
        _messages.last['content'] = 'Error: $e';
        _isGenerating = false;
      });
    }
  }

  final ScrollController _scrollController = ScrollController();

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Llama.cpp Chat'),
      ),
      body: Column(
        children: [
          // Status Bar
          Container(
            padding: const EdgeInsets.all(8.0),
            color: Colors.grey[200],
            child: Row(
              children: [
                Expanded(child: Text(_statusMessage)),
                if (!_isModelLoaded) ...[
                  if (_downloadProgress > 0 && _downloadProgress < 1.0)
                    SizedBox(
                      width: 100,
                      child: LinearProgressIndicator(value: _downloadProgress),
                    )
                  else ...[
                    TextButton(
                      onPressed: _pickModel,
                      child: const Text("Load Local"),
                    ),
                    TextButton(
                      onPressed: _downloadModel,
                      child: const Text("Download"),
                    ),
                  ]
                ]
              ],
            ),
          ),
          
          // Chat Area
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['role'] == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.blue[100] : Colors.green[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(msg['content']!),
                  ),
                );
              },
            ),
          ),

          // Input Area
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                if (_isGenerating)
                  const CircularProgressIndicator()
                else
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _sendMessage,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
