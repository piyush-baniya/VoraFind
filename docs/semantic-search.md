# Semantic Search

Local, on-device semantic retrieval for VoraFind. This document describes the
current implementation: a real neural sentence-embedding model
(`all-MiniLM-L6-v2`, int8) running fully offline through ONNX Runtime, behind
the isolate-and-representable `EmbeddingProvider` interface that complements
(never replaces) the existing keyword/OCR/document search.

## Non-goals

Video segments, audio segments, speech transcription, face recognition,
conversational AI, cloud inference, and WorkManager scheduling are explicitly
out of scope and deferred to later prompts.

## Architecture

```
LOCAL CONTENT
     ↓
INDEXING
     ↓
+---------------------------+
| metadata                  |
| OCR                       |
| document text             |
| semantic representation   |  ← this layer
+---------------------------+
     ↓
LOCAL INDEX
     ↓
+---------------------------+
| keyword index             |
| semantic/vector index     |  ← semantic_embeddings table
+---------------------------+
     ↓
QUERY
     ↓
+---------------------------+
| query parser              |
| keyword retrieval         |
| semantic retrieval        |  ← behind SemanticSearchRepository
+---------------------------+
     ↓
MERGE + RE-RANK
     ↓
TOP RESULTS
```

The ML runtime is fully isolated behind `EmbeddingProvider`; `SearchService`
and the coordinators never touch ML types.

## Selected model

**Production uses `NeuralEmbeddingProvider`** — sentence-transformers
`all-MiniLM-L6-v2` (Apache-2.0), int8-quantized, bundled inside the APK and
executed with ONNX Runtime. Everything runs on-device; there is no model
download and no network access at any point.

### Model and assets

| Item                 | Value / notes                                          |
|----------------------|--------------------------------------------------------|
| Model                | `all-MiniLM-L6-v2` (SBERT, 384-dim sentence embeddings) |
| Graph                | `assets/models/model_quantized.onnx` — 22.9 MB int8     |
| Vocabulary           | `assets/models/vocab.txt` (30522 tokens)                |
| Config provenance    | `config.json`, `tokenizer_config.json`, `tokenizer.json` (bundled, not referenced) |
| License              | Apache-2.0 (Play-Store compatible)                      |
| Model ID             | `minilm-l6-v2-int8-v1` (SemanticDefaults.neuralModelId) |
| Quantization         | int8 weights; inputs/outputs remain int64/Float32       |
| Dimensions           | 384 (unchanged from the deterministic provider)         |

The assets are committed exceptions to the `assets/` gitignore rule
(offline-first) and declared in `pubspec.yaml` `flutter.assets`.

### Why this model / runtime

The provider contract and vector plumbing were validated through Prompt #11
and #12 with a deterministic provider. Replacing it came down to a measured
trade-off, closed here:

* **Size** — 22.9 MB int8 meets the < 50 MB budget and is acceptable as a
  one-time APK delta (see `docs/` measurements in the Prompt #13 report).
* **Accuracy** — the real model demonstrates synonymy the deterministic
  sketch cannot: "vehicle maintenance" ↔ "car repair receipts" scores ~0.63
  cosine; unrelated text sits at ≤ 0.19 (baseline mean 0.047). The existing
  `minSimilarity = 0.35` threshold is validated with wide margin on both
  sides.
* **Runtime** — `onnxruntime` (pub package ^1.4.1) ships `libonnxruntime.so`
  jniLibs for arm64-v8a and armeabi-v7a and a Windows DLL for host tests.
* **Offline** — the graph is a file asset; nothing is fetched at runtime.

### Provider internals

| Property      | Value                                          |
|---------------|------------------------------------------------|
| Model ID      | `minilm-l6-v2-int8-v1`                         |
| Dimensions    | 384                                            |
| Tokenizer     | Ported HuggingFace BERT (slow) WordPiece       |
| Max tokens    | 256 (incl. `[CLS]`/`[SEP]`), truncation-aware  |
| Pooling       | Mean tokens over attention mask                |
| Normalization | L2                                            |
| Quantization  | int8 weights / f32 vectors (`f32` tag)         |
| Runtime       | ONNX Runtime CPU, intra-op 2 threads, graph-opt ALL |
| Concurrency   | One worker isolate per embedding (session is concurrency-safe) |

`DeterministicEmbeddingProvider` (model id `deterministic-384`) and
`LocalEmbeddingProvider` (`local-ngram-rp-384`) are retained as test
fixtures / reference implementations — never wired into production.

## Runtime (FFI)

`NeuralEmbeddingProvider` talks to ORT through `NeuralEmbeddingRuntime`
(`lib/core/semantic/neural_embedding_runtime.dart`):

* The native library is opened **lazily**, at first session creation, and only
  the generated `dart:ffi` bindings are imported — never the package-level
  `onnxruntime.dart` facade, which calls `DynamicLibrary.open` at import time
  and would crash any process (or test) without the DLL. This is marked with
  `// ignore: implementation_imports` and must not be "cleaned up".
* Library resolution: Android → `libonnxruntime.so` (plugin jniLibs); Windows
  host tests → the DLL inside the pub package (resolved via
  `.dart_tool/package_config.json`, never a hard-coded path).
* Every `OrtStatus` is checked and rolled into `OnnxRuntimeException`
  (message + failing operation), matching upstream ownership rules:
  `OrtValue`s via `ReleaseValue`, ORT-name strings via `AllocatorFree`, and
  `OrtMemoryInfo` intentionally left owned by the env.
* **Isolate policy**: a worker isolate per `embed` reopens the DLL,
  re-negotiates the API pointer, and reuses the main-isolate session pointer
  by address (spawned isolates cannot capture `ffi.Pointer`/`DynamicLibrary`).
  This keeps indexing batches off the UI thread and is safe because ORT
  sessions allow concurrent `Run` calls.
* Session teardown (`dispose`) releases the session and env; re-affinity on
  a new run is handled by the provider re-loading on the next embed.

## Tokenizer

`BertTokenizer` (`lib/core/semantic/bert_tokenizer.dart`) is a faithful port
of the HuggingFace **slow** BERT tokenizer for the bundled vocab, executed in
exact upstream order:

1. `_clean_text` (drop control chars + U+FFFD; normalize whitespace)
2. `_tokenize_chinese_chars` (space-surround CJK, one piece per char)
3. lowercase + accent stripping (`diacritic` package)
4. punctuation splitting
5. longest-match WordPiece with `##` continuation (default `max_input_chars`
   = 100, unseen → `[UNK]=100`)
6. truncation to 256 tokens and wrap in `[CLS] … [SEP]` (attention mask all
   ones; segment ids all zeros — inputs are never padded at inference)

The slow implementation was chosen over a port of `tokenizers`' fast one
because token-to-vocabulary relationships are unambiguous, and both the slow
and fast paths agree on every edge case that matters here (U+FFFD is dropped
by both; Deseret → `[UNK]`; CJK punctuation splits).

**Compatibility provenance.** `test/semantic/bert_tokenizer_test.dart` pins
byte-for-byte parity with the Python reference (`transformers` + `tokenizers`
dumps, recorded in `%LOCALAPPDATA%\Temp\opencode\ref_tokens.json`). If the
model is ever swapped, regenerate those fixtures (Python `tokenizers` with
`no_padding()/no_truncation()`) and update the test together with
`SemanticDefaults.neuralModelId`.

## Pooling

Sentence-transformers `all-MiniLM-L6-v2` embeds a sentence by
*(1)* Transformer → `last_hidden_state`, *(2)* mean-pooling over the
attention mask (`1_Pooling/config.json`: `pooling_mode_mean_tokens: true`),
*(3)* L2 normalization (`2_Normalize`). The worker does exactly this in Dart
over the raw `last_hidden_state` floats, so stored vectors are byte-compatible
with what the reference model computes.

## Model invalidation

Every stored row carries `model_id`. `SemanticDefaults.neuralModelId` is the
single invalidation lever: changing the model, quantization, pooling, or
tokenizer bumps it, making all prior rows stale and re-embedded on the next
run. Consumers (coordinator, `SearchService`) filter strictly by
`model_id`, so mixed generations never mix in one retrieval.

## Performance

Measured on the development host (Windows x64, `flutter test`, release-mode
binaries not enabled) — real numbers, single-user scale:

| Operation                              | Result                     |
|----------------------------------------|----------------------------|
| Model + session load (first embed)     | ~193 ms (one-time)         |
| Single embed, median / mean / p95      | 3.2 / 3.4 / 4.5 ms         |
| Batch of 8 embeds (`embedBatch`)       | ~9 ms                      |
| 256-token (max) truncated input        | ~24 ms                     |

A phone (arm64) will differ; Android-level validation is pending a physical
device and is explicitly on the future-work list. The UI thread is never
blocked — inference runs in worker isolates; `embed` results are awaited.

## Storage

| Item               | Size                          |
|--------------------|-------------------------------|
| Per embedding row  | ~1.5 KB (384 × 4 bytes)       |
| 10,000 items       | ~15 MB                        |
| 50,000 items       | ~75 MB                        |

INT8 vector quantization is deferred — Float32 is acceptable given dimensions
and the bounded retrieval pool. A future migration adds an `INT8`
quantization tag; rows carrying unknown tags are handled as stale.

## Hybrid ranking

Search combines keyword and semantic candidates:

```text
Keyword candidates (from metadata, OCR, document text)
      ↓
Semantic candidates (from vector store, bounded pool, model-current only)
      ↓
Merge by stable_key (deduplicate, preserve keyword metadata)
      ↓
Resolve semantic-only rows (a key keyword pools never found is loaded by
stable key so the ranker can produce a real result — never a fragment)
      ↓
SearchRanker: keyword_score + semantic_score
      ↓
Deterministic sort: score desc → dateModified desc → stableKey asc
      ↓
Match explanations: keyword signals first, "Semantic match" last
```

### Similarity threshold (measured)

`minSimilarity = 0.35` was chosen with the real bundled model (Prompt #14), not
intuition. On the development host the relevant query→document pairs landed in
**[0.417, 0.717]** cosine and unrelated pairs at **≤ 0.27**, a clean gap that
keeps retrieval recall-relevant without flooding results with noise
(measurements saved at `%TEMP%\opencode\measures.txt`).

### Ranking rules

1. **Exact filename match (150+) always beats any semantic contribution.**
   `semanticRankWeight = 50`, so even a perfect similarity (50 points) stays
   below an exact filename (150), exact title (132), exact doc-text (66) or
   exact OCR (60) hit — precision outranks fuzzy recall.
2. **A *strong* semantic match rescues weak keyword misses.** The measured
   minimum relevant similarity (0.42) contributes ~21 points, enough to beat a
   path (12) or genre/artist (8) substring hit; a very strong match (> 0.8 →
   40+) beats every substring/metadata-tier hit (≤ 24). This is what surfaces
   `Vehicle Maintainace Guide.pdf` for `car repair information` (0.47, zero
   keyword overlap) or `Chapter_4.pdf` for `neural networks`.
3. **Semantic is additive and gated at the threshold.** Similarity maps
   linearly via `similarity × semanticRankWeight`. The ranker independently
   mirrors `minSimilarity` (defense-in-depth) so a sub-threshold value can
   never fabricate a "semantic match" on a weak coincidence.
4. **Explanation order is keyword-first.** Each result's match list leads with
   the specific literal signals (`Matched in name: aadhaar, card`) and appends
   `Semantic match` last; a result whose *only* signal is conceptual shows
   `Semantic match` (never the phrase "semantic match").

## Limitations

* ANN-only retrieval is not implemented — bounded brute-force over a capped
  candidate pool (`maxCandidatePool` = 200) remains adequate and keeps memory
  predictable as the library grows.
* Real-device (Android) CPU/RAM/battery numbers are not yet measured; host
  benchmarks above are the current evidence.
* The first embedding after app start pays the ~190 ms model-load cost;
  production startup should warm the session during indexing rather than on
  the first keystroke (future work).

## Future work

* Validate Android CPU, RAM, and battery on a physical device and tune
  `intraOpNumThreads` / batching accordingly.
* Warm the session at app startup / index time to move model load off the
  critical search path.
* Add model-level graceful fallback to deterministic semantics on runtime
  failure (already mapped to per-row durable failure today).
* Replace bounded brute-force with a native ANN index if vector counts
  exceed the bounded pool's effectiveness.