import 'dart:math';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../services/app_settings.dart';
import '../../services/vocabulary_service.dart';
import '../../services/dictionary_service.dart';
import '../theme/glass_theme.dart';
import '../widgets/aurora_orb.dart';
import '../widgets/glass_container.dart';
import '../widgets/glass_page.dart';
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

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
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
    final p = GlassScope.of(context).palette;

    if (_currentWord == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassContainer(
              width: 64,
              height: 64,
              borderRadius: 32,
              blur: 0,
              padding: EdgeInsets.zero,
              child: Center(
                child: FaIcon(FontAwesomeIcons.graduationCap,
                    size: 20, color: p.accent),
              ),
            ),
            const SizedBox(height: 16),
            Text('Add words to vocabulary\nto start testing',
                textAlign: TextAlign.center,
                style: GlassText.display(p, 18, weight: FontWeight.w600)),
          ],
        ),
      );
    }

    final isCorrect = _feedbackMessage != null && _feedbackMessage!.startsWith("Correct");
    final isError = _feedbackMessage != null && _feedbackMessage!.startsWith("Error");

    return Stack(
      children: [
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('DEFINE THIS WORD',
                    textAlign: TextAlign.center,
                    style: GlassText.eyebrow(p)),
                const SizedBox(height: 10),
                Text(
                  _currentWord!.word,
                  textAlign: TextAlign.center,
                  style: GlassText.display(p, 38, tracking: -1.2),
                ),
                const SizedBox(height: 24),
                GlassContainer(
                  blur: 0,
                  borderRadius: 22,
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: TextField(
                    controller: _inputController,
                    maxLines: 3,
                    minLines: 2,
                    style: GlassText.body(p, 15, height: 1.5),
                    cursorColor: p.accent,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: "Write your definition…",
                      hintStyle:
                          GlassText.body(p, 14, color: p.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (_feedbackMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Align(
                      alignment: Alignment.center,
                      child: GlassContainer(
                        blur: 0,
                        sheen: false,
                        borderRadius: 16,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FaIcon(
                              isError
                                  ? FontAwesomeIcons.circleXmark
                                  : FontAwesomeIcons.circleCheck,
                              size: 14,
                              color: isCorrect
                                  ? p.success
                                  : isError
                                      ? p.danger
                                      : p.warn,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _feedbackMessage!,
                                style: GlassText.body(p, 12.5,
                                    weight: FontWeight.w600,
                                    color: isCorrect
                                        ? p.success
                                        : isError
                                            ? p.danger
                                            : p.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: GlassButton(
                        label: 'Skip',
                        height: 48,
                        onTap: _isChecking ? null : _nextWord,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrimaryButton(
                        label: _isChecking ? '' : 'Check',
                        height: 48,
                        onTap: _isChecking ? null : _checkAnswer,
                        leading: _isChecking
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: AuroraOrb(
                                  size: 18,
                                  colorA: Colors.white,
                                  colorB: Colors.white.withValues(alpha: 0.5),
                                ),
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        if (_showPopup)
          Positioned(
            left: 8,
            right: 8,
            top: 8,
            bottom: 8,
            child: VocabularyDetailPopup(
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
          ),
      ],
    );
  }
}
