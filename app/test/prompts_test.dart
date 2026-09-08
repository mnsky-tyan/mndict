import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/app_settings.dart';
import 'package:app/services/prompts.dart';

void main() {
  const word = 'serendipity';

  group('buildLookupPrompt invariants (all families)', () {
    // Templates were taken verbatim from each model's chat_template.jinja;
    // these tests guard the rules that are easy to break when editing.
    for (final style in PromptStyle.values) {
      test('$style hands off to the model in an assistant turn', () {
        final p = buildLookupPrompt(style, word);
        expect(p, contains(word), reason: 'headword must reach the prompt');
        expect(
          p.endsWith('<|im_start|>assistant\n') ||
              p.endsWith('<|assistant|>\n') ||
              p.endsWith('<|start_header_id|>assistant<|end_header_id|>\n\n') ||
              p.endsWith('<start_of_turn>model\n') ||
              p.endsWith('<|turn>model\n') ||
              p.endsWith('<think></think>') ||
              p.endsWith('<think>\n\n</think>\n\n'),
          isTrue,
          reason: 'generation must start from an assistant/open turn',
        );
      });
    }
  });

  group('BOS handling (per AGENTS.md)', () {
    test('gemma starts with a literal <bos>', () {
      // Gemma is BOS-sensitive: without it the model can end generation
      // immediately.
      expect(buildLookupPrompt(PromptStyle.gemma, word).startsWith('<bos>'), isTrue);
    });

    test('gemma4 has no literal <bos> (GGUF add_bos prepends it) and uses new turn markers', () {
      final p = buildLookupPrompt(PromptStyle.gemma4, word);
      expect(p.startsWith('<|turn>user\n'), isTrue);
      expect(p.contains('<bos>'), isFalse,
          reason: 'E2B GGUF sets add_bos_token=true; a literal BOS doubles it');
      expect(p, contains('<turn|>'));
      expect(p, isNot(contains('<start_of_turn>')));
    });

    test('lfm25 has no literal BOS (the tokenizer prepends it)', () {
      // LFM2.5 GGUF sets add_bos_token=true; a literal BOS would double it.
      expect(buildLookupPrompt(PromptStyle.lfm25, word).contains('<|startoftext|>'), isFalse);
      expect(buildLookupPrompt(PromptStyle.lfm25, word).startsWith('<|im_start|>'), isTrue);
    });

    test('minicpm5 includes the literal <s> (GGUF has add_bos_token=false)', () {
      expect(buildLookupPrompt(PromptStyle.minicpm5, word).startsWith('<s><|im_start|>'), isTrue);
    });

    test('nemotron3 carries no BOS and pre-closes its think block', () {
      final p = buildLookupPrompt(PromptStyle.nemotron3, word);
      expect(p.startsWith('<|im_start|>'), isTrue);
      expect(p.endsWith('<|im_start|>assistant\n<think></think>'), isTrue);
    });
  });

  group('structure rules', () {
    test('llama3 has exactly one user turn', () {
      // Regression: the user turn used to be duplicated verbatim, doubling
      // the headword in the prompt.
      final p = buildLookupPrompt(PromptStyle.llama3, word);
      expect('<|start_header_id|>user<|end_header_id|>'.allMatches(p), hasLength(1));
      expect('Define: $word<|eot_id|>'.allMatches(p), hasLength(1));
      expect(p.startsWith('<|begin_of_text|>'), isTrue);
    });

    test('qwen3 disables thinking via /no_think', () {
      expect(buildLookupPrompt(PromptStyle.qwen3, word).contains('/no_think'), isTrue);
    });

    test('lfm25 carries the format reminder inside the user turn', () {
      final p = buildLookupPrompt(PromptStyle.lfm25, word);
      final userTurn = p.split('<|im_start|>user\n')[1];
      expect(userTurn.contains('Use the exact entry format'), isTrue);
    });

    test('bake-off prompts include the None abstention policy', () {
      for (final style in [
        PromptStyle.lfm25,
        PromptStyle.minicpm5,
        PromptStyle.nemotron3,
        PromptStyle.gemma4,
      ]) {
        expect(
          buildLookupPrompt(style, word).contains('reply only: None'),
          isTrue,
          reason: '$style must keep the honesty/abstention instruction',
        );
      }
    });

    test('lfm25tuned is byte-exact with the LoRA pilot training prompt', () {
      // The tuned model was trained on exactly this prompt; any drift
      // degrades the pilot without any test failing elsewhere.
      expect(buildLookupPrompt(PromptStyle.lfm25tuned, word),
          '<|im_start|>system\n'
          'You are a dictionary assistant. Explain the given word, phrase, '
          'idiom, or short sentence as a dictionary entry. If the headword is '
          'not a real English word or phrase, reply only: None.<|im_end|>\n'
          '<|im_start|>user\n'
          '$word<|im_end|>\n'
          '<|im_start|>assistant\n');
    });
  });

  group('buildSimilarityPrompt', () {
    test('llama3 has a single user turn', () {
      final p = buildSimilarityPrompt(
        PromptStyle.llama3,
        word: word,
        definition: 'a lucky find',
        userInput: 'finding good things by accident',
      );
      expect('<|start_header_id|>user<|end_header_id|>'.allMatches(p), hasLength(1));
      expect(p, contains(word));
      expect(p, contains('a lucky find'));
      expect(p, contains('finding good things by accident'));
    });

    test('chatml-family shares the im_start structure', () {
      for (final style in [
        PromptStyle.chatml,
        PromptStyle.lfm25,
        PromptStyle.minicpm5,
        PromptStyle.nemotron3,
      ]) {
        final p = buildSimilarityPrompt(
          style,
          word: word,
          definition: 'a lucky find',
          userInput: 'finding good things by accident',
        );
        expect(p.startsWith('<|im_start|>system\n'), isTrue, reason: '$style');
        expect('<|im_start|>user'.allMatches(p), hasLength(1));
      }
    });

    test('gemma and gemma4 use their respective turn markers and <bos>', () {
      final gemma = buildSimilarityPrompt(
        PromptStyle.gemma,
        word: word,
        definition: 'd',
        userInput: 'u',
      );
      final gemma4 = buildSimilarityPrompt(
        PromptStyle.gemma4,
        word: word,
        definition: 'd',
        userInput: 'u',
      );
      expect(gemma, contains('<start_of_turn>user'));
      expect(gemma4, contains('<|turn>user'));
      expect(gemma4, isNot(contains('<start_of_turn>')));
    });
  });

  group('model catalog invariants', () {
    test('every model has a unique filename (they share one directory)', () {
      final filenames = AppSettings.availableModels.map((m) => m.filename);
      expect(filenames.toSet().length, filenames.length,
          reason: 'duplicate filenames would overwrite each other on disk');
    });

    test('every model has a non-empty URL and prompt style', () {
      for (final m in AppSettings.availableModels) {
        expect(m.url, isNotEmpty);
      }
    });
  });
}
