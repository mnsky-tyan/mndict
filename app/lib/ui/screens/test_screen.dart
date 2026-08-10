import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_settings.dart';
import '../../services/vocabulary_service.dart';
import '../../services/dictionary_service.dart';
import '../widgets/vocabulary_detail_popup.dart';

class TestScreen extends StatefulWidget {
  final VocabularyService vocabularyService;
  final DictionaryService? dictionaryService;
  final AppSettings settings;

  const TestScreen({
    super.key,
    required this.vocabularyService,
    required this.dictionaryService,
    required this.settings,
  });

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  VocabularyItem? _currentWord;
  final TextEditingController _inputController = TextEditingController();
  bool _isChecking = false;
  String? _feedbackMessage;
  bool _showPopup = false;

  @override
  void initState() {
    super.initState();
    _nextWord();
  }

  void _nextWord() {
    final words = widget.vocabularyService.getSortedWords(SortType.latest, true);
    if (words.isEmpty) {
      setState(() => _currentWord = null);
      return;
    }
    final random = Random();
    setState(() {
      _currentWord = words[random.nextInt(words.length)];
      _inputController.clear();
      _feedbackMessage = null;
      _showPopup = false;
    });
  }

  Future<void> _checkAnswer() async {
    if (_currentWord == null || _inputController.text.isEmpty || widget.dictionaryService == null) return;

    setState(() {
      _isChecking = true;
      _feedbackMessage = "Checking similarity...";
    });

    final word = _currentWord!.word;
    final definition = _currentWord!.definition;
    final userInput = _inputController.text;

    try {
      final score = await widget.dictionaryService!.checkSimilarity(word, definition, userInput);
      
      if (!mounted) return;

      setState(() {
        _isChecking = false;
        if (score >= 0.9) {
          _feedbackMessage = "Correct! (Similarity: ${(score * 100).toStringAsFixed(1)}%)";
          widget.settings.addCoins(1); // Add coin
          // Optional: Mark as familiar
        } else {
          _feedbackMessage = "Incorrect. (Similarity: ${(score * 100).toStringAsFixed(1)}%)";
          _showPopup = true;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _feedbackMessage = "Error checking: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentWord == null) {
      return Center(
        child: Text(
          "Add words to vocabulary to start testing!",
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 18),
        ),
      );
    }

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Define this word:",
                style: GoogleFonts.outfit(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 10),
              Text(
                _currentWord!.word,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 30),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.white.withOpacity(0.8), width: 2),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                child: TextField(
                  controller: _inputController,
                  maxLines: 3,
                  style: GoogleFonts.outfit(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Enter definition...",
                    hintStyle: GoogleFonts.outfit(color: Colors.white54),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (_feedbackMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(
                    _feedbackMessage!,
                    style: GoogleFonts.outfit(
                      color: _feedbackMessage!.startsWith("Correct") ? Colors.greenAccent : Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _nextWord,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.2),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("Skip"),
                  ),
                  ElevatedButton(
                    onPressed: _isChecking ? null : _checkAnswer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4FACFE),
                      foregroundColor: Colors.white,
                    ),
                    child: _isChecking 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text("Check"),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        if (_showPopup)
          VocabularyDetailPopup(
            word: _currentWord!.word,
            definition: _currentWord!.definition,
            onClose: () => setState(() => _showPopup = false),
            onDelete: () {
               widget.vocabularyService.removeWord(_currentWord!.word);
               setState(() => _showPopup = false);
               _nextWord();
            },
            onRefresh: () {
               // Refresh logic not strictly needed here as it's a test, 
               // but we can just close and let them try again or show current def.
               // For now, just close.
               setState(() => _showPopup = false);
            },
          ),
      ],
    );
  }
}
