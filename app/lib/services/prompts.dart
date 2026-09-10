import 'app_settings.dart';

// Prompt templates, taken verbatim from each model family's
// chat_template.jinja. BOS handling differs per family and is easy to get
// wrong — see the tests in test/prompts_test.dart before editing.

const String _systemPrompt = """
You are a dictionary assistant. Output the definition in the following format:
Definition: [Definition]
Examples:
- [Example 1]
- [Example 2]
Synonyms: [Synonym 1], [Synonym 2]
Antonyms: [Antonym 1], [Antonym 2]
Do not use markdown formatting. Just plain text.
""";

// Instruction carried in the system turn for the 2026 bake-off models:
// strict format + explicit permission to abstain (the honesty play).
const String _dictionarySystemPrompt = "You are a dictionary assistant. Explain the given word, "
    "phrase, idiom, or short sentence. Reply in exactly this format:\n"
    "Definition: <definition>\n"
    "Examples:\n- <example sentence>\n- <example sentence>\n"
    "Synonyms: <comma-separated synonyms, or none>\n"
    "Antonyms: <comma-separated antonyms, or none>\n"
    "Plain text only, no markdown. "
    "If you are not certain the entry exists, or you don't know it, reply only: None.";

/// Public alias so engines outside the local-llama path (the Gemini
/// service) carry the same system instruction VERBATIM - this is what
/// preserves the entry format and the None abstention.
const String dictionarySystemPrompt = _dictionarySystemPrompt;

/// Semantic-similarity scorer instruction, shared by the per-family
/// templates and the Gemini engine.
String similarityInstruction({
  required String word,
  required String definition,
}) {
  return "You are a semantic similarity checker. Compare the user's definition to the actual definition. "
      "Output ONLY a single number between 0.0 and 1.0 representing the similarity score. "
      "0.0 means completely wrong, 1.0 means perfect match. No other text.\n"
      "Word: $word\n"
      "Actual Definition: $definition";
}

/// Builds the lookup prompt for one headword, per model family.
String buildLookupPrompt(PromptStyle style, String word) {
  switch (style) {
    case PromptStyle.chatml:
      return "<|im_start|>system\n"
          "$_systemPrompt<|im_end|>\n"
          "<|im_start|>user\n"
          "Define: $word<|im_end|>\n"
          "<|im_start|>assistant\n";
    case PromptStyle.gemma:
      // Gemma is BOS-sensitive: the <bos> token must start the prompt or
      // the model can end generation immediately.
      return "<bos><start_of_turn>user\n"
          "Give a dictionary definition for the word: $word\n"
          "Include Definition, Examples, Synonyms, and Antonyms.<end_of_turn>\n"
          "<start_of_turn>model\n";
    case PromptStyle.qwen3:
      return "<|im_start|>system\n"
          "$_systemPrompt\n"
          "Use **bold** for headings (Definition, Examples, Synonyms, Antonyms).\n"
          "Do not output thinking process. Do not use <think> tags.<|im_end|>\n"
          "<|im_start|>user\n"
          "Define: $word /no_think<|im_end|>\n"
          "<|im_start|>assistant\n";
    case PromptStyle.lfm25:
      // LFM2.5: the GGUF's add_bos_token=true makes the tokenizer prepend
      // <|startoftext|> — a literal BOS here would double it.
      // Format reminder rides in the user turn: small models obey the user
      // turn far better than the system turn (locally verified 2026-09-05).
      return "<|im_start|>system\n"
          "$_dictionarySystemPrompt<|im_end|>\n"
          "<|im_start|>user\n"
          "$word\n\n"
          "Use the exact entry format: numbered Meanings with a short sense "
          "label in parentheses, an Example block with bullet sentence(s) under "
          "each meaning, and Synonyms/Antonyms lines each formatted as: "
          "word - short gloss.<|im_end|>\n"
          "<|im_start|>assistant\n";
    case PromptStyle.lfm25tuned:
      // Byte-exact match with the LoRA pilot's training prompt
      // (training/train_pilot.py SYSTEM_PROMPT): persona + None policy only,
      // bare headword — the format itself is baked into the weights.
      const tunedSystem =
          "You are a dictionary assistant. Explain the given word, phrase, "
          "idiom, or short sentence as a dictionary entry. If the headword is "
          "not a real English word or phrase, reply only: None.";
      return "<|im_start|>system\n"
          "$tunedSystem<|im_end|>\n"
          "<|im_start|>user\n"
          "$word<|im_end|>\n"
          "<|im_start|>assistant\n";
    case PromptStyle.minicpm5:
      // MiniCPM5: GGUF add_bos_token=false, so the template's <s> is included
      // literally. The empty <think> block is the model's own non-thinking
      // form (its template injects exactly this when thinking is disabled).
      return "<s><|im_start|>system\n"
          "$_dictionarySystemPrompt<|im_end|>\n"
          "<|im_start|>user\n"
          "$word<|im_end|>\n"
          "<|im_start|>assistant\n<think>\n\n</think>\n\n";
    case PromptStyle.nemotron3:
      // Nemotron 3: Qwen-style template, no BOS; empty think block disables
      // its reasoning-by-default mode.
      return "<|im_start|>system\n"
          "$_dictionarySystemPrompt<|im_end|>\n"
          "<|im_start|>user\n"
          "$word<|im_end|>\n"
          "<|im_start|>assistant\n<think></think>";
    case PromptStyle.gemma4:
      // Gemma-4 replaced <start_of_turn>/<end_of_turn> with <|turn>/<turn|>;
      // no system role, so the instruction rides in the user turn.
      // NO literal <bos>: the E2B GGUF sets add_bos_token=true, and the
      // native tokenize call runs with add_special=true — a literal BOS
      // would double it (verified in the GGUF metadata, 2026-09-07).
      return "<|turn>user\n"
          "$_dictionarySystemPrompt\n\n"
          "$word<turn|>\n"
          "<|turn>model\n";
    case PromptStyle.phi:
      return "<|user|>\n"
          "$_systemPrompt\n"
          "Define: $word<|end|>\n"
          "<|assistant|>\n";
    case PromptStyle.llama3:
      return "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n"
          "$_systemPrompt<|eot_id|>\n"
          "<|start_header_id|>user<|end_header_id|>\n\n"
          "Define: $word<|eot_id|>\n"
          "<|start_header_id|>assistant<|end_header_id|>\n\n";
  }
}

/// Builds the semantic-similarity prompt for the Test tab: the model is
/// asked to score the user's definition against the real one, 0.0..1.0.
String buildSimilarityPrompt(
  PromptStyle style, {
  required String word,
  required String definition,
  required String userInput,
}) {
  final systemMsg = similarityInstruction(word: word, definition: definition);

  final userMsg = "User Definition: $userInput";

  // The im_start/im_end turn structure is shared by chatml, LFM2.5,
  // MiniCPM5 and Nemotron 3.
  if (style == PromptStyle.chatml ||
      style == PromptStyle.lfm25 ||
      style == PromptStyle.minicpm5 ||
      style == PromptStyle.nemotron3) {
    return "<|im_start|>system\n"
        "$systemMsg<|im_end|>\n"
        "<|im_start|>user\n"
        "$userMsg<|im_end|>\n"
        "<|im_start|>assistant\n";
  } else if (style == PromptStyle.gemma || style == PromptStyle.gemma4) {
    final isGemma4 = style == PromptStyle.gemma4;
    // gemma4: no literal <bos> — its GGUF auto-prepends BOS (see lookup).
    return "${isGemma4 ? '' : '<bos>'}${isGemma4 ? '<|turn>user\n' : '<start_of_turn>user\n'}"
        "$systemMsg\n"
        "$userMsg${isGemma4 ? '<turn|>\n<|turn>model\n' : '<end_of_turn>\n<start_of_turn>model\n'}";
  } else if (style == PromptStyle.phi) {
    return "<|user|>\n"
        "$systemMsg\n"
        "$userMsg<|end|>\n"
        "<|assistant|>\n";
  } else {
    // Llama 3
    return "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n"
        "$systemMsg<|eot_id|>\n"
        "<|start_header_id|>user<|end_header_id|>\n\n"
        "$userMsg<|eot_id|>\n"
        "<|start_header_id|>assistant<|end_header_id|>\n\n";
  }
}
