import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class VocabularyItem {
  final String word;
  final String definition;
  final DateTime addedAt;
  final double familiarity;

  VocabularyItem({
    required this.word,
    required this.definition,
    required this.addedAt,
    this.familiarity = 0.0,
  });

  Map<String, dynamic> toJson() => {
    'word': word,
    'definition': definition,
    'addedAt': addedAt.toIso8601String(),
    'familiarity': familiarity,
  };

  factory VocabularyItem.fromJson(Map<String, dynamic> json) {
    return VocabularyItem(
      word: json['word'],
      definition: json['definition'],
      addedAt: DateTime.parse(json['addedAt']),
      familiarity: (json['familiarity'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

enum SortType { latest, alphabetical, familiarity }

class VocabularyService {
  static const String _keySavedWords = 'saved_words';
  
  late SharedPreferences _prefs;
  // Map of word -> VocabularyItem
  Map<String, VocabularyItem> _savedWords = {};

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadWords();
  }

  void _loadWords() {
    final String? jsonString = _prefs.getString(_keySavedWords);
    if (jsonString != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(jsonString);
        _savedWords = {};
        
        decoded.forEach((key, value) {
          if (value is String) {
            // Migration: Old format was just the definition string
            _savedWords[key] = VocabularyItem(
              word: key,
              definition: value,
              addedAt: DateTime.now(), // Default to now for migrated items
            );
          } else {
            // New format
            _savedWords[key] = VocabularyItem.fromJson(value);
          }
        });
      } catch (e) {
        print("Error loading vocabulary: $e");
        _savedWords = {};
      }
    }
  }

  Future<void> _saveToPrefs() async {
    final Map<String, dynamic> encoded = _savedWords.map(
      (key, value) => MapEntry(key, value.toJson()),
    );
    final String jsonString = jsonEncode(encoded);
    await _prefs.setString(_keySavedWords, jsonString);
  }

  Future<void> saveWord(String word, String content) async {
    if (word.isEmpty) return;
    
    // If updating existing, keep original addedAt
    final existing = _savedWords[word];
    
    _savedWords[word] = VocabularyItem(
      word: word,
      definition: content,
      addedAt: existing?.addedAt ?? DateTime.now(),
      familiarity: existing?.familiarity ?? 0.0,
    );
    await _saveToPrefs();
  }

  Future<void> removeWord(String word) async {
    _savedWords.remove(word);
    await _saveToPrefs();
  }

  bool isWordSaved(String word) {
    return _savedWords.containsKey(word);
  }

  String? getDefinition(String word) {
    return _savedWords[word]?.definition;
  }

  List<VocabularyItem> getSortedWords(SortType type, bool ascending) {
    final list = _savedWords.values.toList();
    
    list.sort((a, b) {
      int result;
      switch (type) {
        case SortType.latest:
          result = a.addedAt.compareTo(b.addedAt);
          break;
        case SortType.alphabetical:
          result = a.word.toLowerCase().compareTo(b.word.toLowerCase());
          break;
        case SortType.familiarity:
          result = a.familiarity.compareTo(b.familiarity);
          break;
      }
      return ascending ? result : -result;
    });
    
    return list;
  }
  
  // Deprecated: Use getSortedWords instead
  List<String> getWordList() {
    return _savedWords.keys.toList()..sort();
  }
}
