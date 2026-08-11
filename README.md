# mndict

An experimental dictionary app powered by a **local LLM running directly on your phone**.

mndict uses [llama.cpp](https://github.com/ggml-org/llama.cpp) to run language models locally on mobile CPUs. You can enter individual words, phrases, idioms, or even short sentences and have the model explain them without sending your queries to an external API. Since the model runs locally, **your searches can work entirely offline**. The project is still highly experimental, and because it relies on generative AI, its answers can be inconsistent or occasionally incorrect.

> **Current release:** `v0.1.0` (pre-release)
> This release includes a test setup for the Gemma 3 270M IT Q4_K_M model. See the [Releases](../../releases) page for the model files.

---

## Inspiration

Whenever I wanted to look up the meaning of a word, phrase, or term, I often ended up using ChatGPT instead of a traditional dictionary.

My workflow was basically to keep a dedicated ChatGPT conversation as a dictionary. I could paste in a word, phrase, idiom, or short sentence, and the model would explain it in whatever format I wanted. This was particularly useful for things that traditional dictionaries don't handle particularly well, such as:

* Short phrases and sentences
* Idioms and expressions
* Context-dependent meanings
* Explanations tailored to my preferred format
* Translation and language-learning use cases

I also liked that the output format could be customized simply by changing the prompt.

However, using a chat conversation as a dictionary has some obvious problems.

The model's formatting becomes less consistent as the conversation gets longer. Finding an old word I searched for can also be difficult, and there is no particularly good way to organize the things I've learned for later review. Eventually, the conversation becomes too long and I have to start another one.

That led to the idea behind mndict: **what if an AI dictionary actually behaved like a dictionary?**

Instead of being limited to conventional dictionary entries, it could accept almost anything you want to look up, while also keeping track of your searches and allowing much more personalization. With an appropriate model, the same system could potentially work across many different languages.

---

## Why Local AI?

The obvious problem with using an API is cost.

A dictionary is something I might use many times a day. Having every lookup make an API request means continually paying for tokens just to look up words.

The alternative seemed appealing:

> **Put the language model directly on the phone.**

No API costs.
No internet connection required.
No sending queries to a server.
Just run the model locally and use the phone's CPU for inference.

Unfortunately, I significantly underestimated how difficult this is in practice.

---

## What I Found

Small language models are much less capable than I initially expected, especially when running under the constraints of a mobile device.

For example, a roughly **2.7B-parameter Q4 model** can run on a phone, but inference speed can be around **3 tokens/second** depending on the device and configuration. At the same time, its response quality can be substantially worse than what is available through modern API-based models.

Going smaller doesn't necessarily solve the problem either. Models around 1B parameters or below can be considerably faster, but their instruction-following ability can become too weak for the kind of structured dictionary output I want.

This created an awkward trade-off:

```text
Smaller model
    ↓
Faster inference
    ↓
Poorer instruction following / quality

Larger model
    ↓
Better quality
    ↓
Much slower inference on a phone
```

---

## Attempts to Improve Inference

I experimented with several approaches to make local inference more practical on mobile devices.

### Shortening the context window

I initially expected a shorter context window to significantly improve inference speed.

It didn't help nearly as much as I expected.

### Clearing the context after every lookup

Since a dictionary doesn't need a conversational history, I experimented with clearing the KV cache/context after every search.

This makes sense conceptually because every lookup can be treated as an independent request.

However, it doesn't solve the fundamental problem of model inference speed.

### More aggressive quantization

I also experimented with highly quantized models, including roughly 2.6B-parameter Q2 models.

This reduces memory requirements, but the resulting trade-off between quality and inference speed still wasn't good enough.

---

## Prompt Engineering

The next approach was to improve instruction following through prompting.

I experimented with injecting a system prompt describing exactly how the model should behave as a dictionary.

With smaller models, however, simply giving instructions wasn't reliable enough.

I then tried adding examples directly into the system prompt so that the model could imitate the desired dictionary format.

This worked much better in terms of instruction following.

Unfortunately, the examples substantially increased the context/KV cache, which made inference even slower on a phone.

So I ended up with another trade-off:

```text
More examples
    ↓
Better formatting / instruction following
    ↓
Larger context
    ↓
Slower inference
```

---

## Fine-Tuning

Eventually I tried training the model myself.

I prepared roughly 200 examples showing the model how I wanted dictionary responses to be structured and fine-tuned the model using **LoRA**.

LoRA only modifies a small fraction of the model's parameters, which made it seem like a promising approach for teaching a relatively small model the specific behavior needed for mndict.

The results were not as successful as I hoped.

With fewer training iterations, the model struggled to consistently follow the desired dictionary format.

With more iterations, it began to overfit the training examples. The formatting became more consistent, but the actual quality and generalization of the answers became noticeably worse.

In other words:

```text
Less training
    → Better generalization
    → Poorer adherence to the desired format

More training
    → Better adherence to the format
    → More overfitting
    → Worse answer quality
```

---

## Current Status

At the moment, **mndict is essentially a stale/experimental project**.

The main problem isn't that local LLM inference on phones is impossible. It is possible.

The problem is getting all three of these at the same time:

1. **Good enough language quality**
2. **Reliable instruction following**
3. **Acceptable inference speed on a phone**

The models and hardware I have tested so far don't provide a good enough combination of all three.

Unless a significant improvement in mobile inference or small-model capability appears, I don't currently see a particularly compelling path toward making the original idea work as intended.

---

## Possible Future Direction

There is another possibility: abandoning the local model approach and using an API instead.

Technically, that would make the dictionary much more capable and responsive.

But that also creates a problem for me personally.

If the application becomes an AI wrapper that mainly consists of UI, prompts, and API calls, it loses much of what made the project interesting to me in the first place.

I'd still like an AI-powered dictionary because I genuinely enjoy using AI for language learning. But paying for API calls every time I use it is not particularly appealing either.

And if I'm going to build an application that is primarily an API wrapper, I would probably rather start a separate project than continue turning mndict into something fundamentally different from the original idea.

For now, I'm leaving the project here.

Maybe mobile hardware gets faster.
Maybe small models get dramatically better.
Maybe inference techniques improve enough to make the original idea practical.

If that happens, I'd be interested in picking this project back up.

---

## Project Structure

The repository roughly consists of:

```text
mndict/
├── app/                 # Flutter application
├── llama.cpp/           # llama.cpp Git submodule
├── scripts/             # Utility/setup scripts
├── test_model/          # Local model files (ignored by Git)
├── .gitignore
└── README.md
```

The GGUF model files are intentionally **not stored in the Git repository** because they exceed GitHub's normal 100 MB per-file limit. Test models are distributed separately through GitHub Releases.

---

## Disclaimer

mndict is an experimental project and should not be treated as a reliable source of factual information.

The underlying language model is generative and can produce incorrect, incomplete, or inconsistent explanations. Always verify important information using reliable sources.
