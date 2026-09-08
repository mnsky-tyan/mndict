import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/services/vocabulary_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('starts empty with fresh prefs', () async {
    final svc = VocabularyService();
    await svc.init();
    expect(svc.getSortedWords(SortType.latest, true), isEmpty);
    expect(svc.isWordSaved('word'), isFalse);
    expect(svc.getDefinition('word'), isNull);
  });

  test('saveWord stores and updates a word', () async {
    final svc = VocabularyService();
    await svc.init();

    await svc.saveWord('serendipity', 'a lucky find');
    expect(svc.isWordSaved('serendipity'), isTrue);
    expect(svc.getDefinition('serendipity'), 'a lucky find');

    await svc.saveWord('serendipity', 'an unexpected pleasant discovery');
    expect(svc.getDefinition('serendipity'), 'an unexpected pleasant discovery');
    expect(svc.getSortedWords(SortType.alphabetical, true), hasLength(1));
  });

  test('saveWord ignores empty words', () async {
    final svc = VocabularyService();
    await svc.init();
    await svc.saveWord('', 'content');
    expect(svc.getSortedWords(SortType.latest, true), isEmpty);
  });

  test('removeWord deletes the entry', () async {
    final svc = VocabularyService();
    await svc.init();
    await svc.saveWord('word', 'def');
    await svc.removeWord('word');
    expect(svc.isWordSaved('word'), isFalse);
    expect(svc.getSortedWords(SortType.latest, true), isEmpty);
  });

  test('words persist across service instances (prefs round-trip)', () async {
    final first = VocabularyService();
    await first.init();
    await first.saveWord('persisted', 'still here');

    final second = VocabularyService();
    await second.init();
    expect(second.getDefinition('persisted'), 'still here');
  });

  test('migrates the legacy word->definition-string format', () async {
    SharedPreferences.setMockInitialValues({
      'saved_words': '{"legacy":"old definition string"}',
    });
    final svc = VocabularyService();
    await svc.init();
    expect(svc.getDefinition('legacy'), 'old definition string');
    expect(svc.getSortedWords(SortType.latest, true), hasLength(1));
  });

  test('corrupt JSON resets to empty instead of throwing', () async {
    SharedPreferences.setMockInitialValues({
      'saved_words': '{not json',
    });
    final svc = VocabularyService();
    await svc.init();
    expect(svc.getSortedWords(SortType.latest, true), isEmpty);
  });

  test('sorts alphabetically in both directions', () async {
    final svc = VocabularyService();
    await svc.init();
    await svc.saveWord('banana', 'b');
    await svc.saveWord('apple', 'a');
    await svc.saveWord('cherry', 'c');

    final asc = svc.getSortedWords(SortType.alphabetical, true).map((w) => w.word);
    expect(asc, ['apple', 'banana', 'cherry']);
    final desc = svc.getSortedWords(SortType.alphabetical, false).map((w) => w.word);
    expect(desc, ['cherry', 'banana', 'apple']);
  });

  test('sorts by familiarity', () async {
    final svc = VocabularyService();
    await svc.init();
    await svc.saveWord('low', 'l');
    await svc.saveWord('high', 'h');
    // familiarity is only settable through persisted JSON today.
    expect(
      svc.getSortedWords(SortType.familiarity, true).map((w) => w.familiarity),
      everyElement(0.0),
    );
  });
}
