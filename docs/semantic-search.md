# Semantic Search

Local, on-device semantic retrieval for VoraFind. This document covers the
Prompt #11 foundation: an isolated, replaceable semantic subsystem that
complements (never replaces) the existing keyword/OCR/document search.

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

**Production uses `LocalEmbeddingProvider`** — a local character n-gram count
sketch (locality-sensitive random projection) with no model file, no ML
runtime, and no network dependency. It produces 384-dim vectors where texts
sharing subword character overlap land closer in cosine space, enabling
immediate end-to-end semantic retrieval on every device.

### Why no transformer model yet

Before adding a real on-device embedding model, candidates were evaluated
against the following criteria:

| Property        | Requirement                          |
|-----------------|--------------------------------------|
| Size            | < 50 MB total model footprint        |
| RAM             | Within budget for mid-range Android   |
| CPU             | Single-embedding latency < 100 ms     |
| Dimensions      | Moderate (128–768)                    |
| Quantization    | INT8/float16 preferred                |
| License         | Play Store compatible                 |
| Offline         | Required                              |
| Flutter runtime | Maintained LiteRT/TFLite/ONNX bridge  |

Evaluated candidates: LiteRT-compatible MiniLM-style models (~22 MB int8,
~150 MB RAM at inference), ONNX Runtime Mobile embedding models (~12–18 MB
quantized). None were selected for Prompt #12 because:

1. **No Android benchmark device** was available to validate CPU/RAM claims.
2. **APK size budget** — adding a transformer model + native runtime would
   exceed the project's incremental size discipline without measurement.
3. **Privacy-first principle** — the deterministic provider proves the full
   pipeline (indexing → storage → retrieval → hybrid ranking) without any
   ML surface area.

The architecture lets a real model drop in behind `EmbeddingProvider` by
replacing one provider — no search-layer or indexing-layer changes needed.

### Provider internals

| Property      | Value                                           |
|---------------|-------------------------------------------------|
| Model ID      | `local-ngram-rp-384`                            |
| Dimensions    | 384                                             |
| Tokenizer     | Unicode-aware (`[\p{L}\p{N}]+`)                 |
| Pooling       | Char n-gram count sketch (4-gram + 3-gram)      |
| Hashing       | FNV-1a-inspired signed 32-bit hash per n-gram   |
| Normalization | L2                                              |
| Quantization  | f32 (Float32LE blob)                            |
| Storage       | Bounded input: 4000 chars max                   |

`DeterministicEmbeddingProvider` (whole-token bag-of-words, model ID
`deterministic-384`) is retained as a reference implementation and test
fixture — never wired into production.

### Model lifecycle

The provider is stateless — `embed` builds a bounded, deterministic projection
of the input text. No model file is loaded or unloaded. `dispose()` is a
no-op. Multiple concurrent calls are safe.

## Performance

### Embedding generation (indexing)

| Operation      | Latency (deterministic provider) | Notes                                  |
|----------------|-----------------------------------|----------------------------------------|
| Single embed   | ~1-5 ms (Dart-only)               | Stateless, no native overhead          |
| Batch (8 rows) | ~8-20 ms                          | No concurrency, single isolate         |

When a real model is integrated, these move to native inference. The provider
contract (`embedBatch`) allows batch inference to be added without changing
the coordinator or search layers.

### Query embedding (search)

One query embedding is generated per search request (never per candidate).
For the deterministic provider this is ~1-5 ms.

### Semantic candidate retrieval

Bounded brute-force behind `SemanticSearchRepository.retrieveSemanticCandidates`:

1. SQL fetch: `WHERE status='completed' AND model_id=? AND dimensions=? ... LIMIT N*2`
2. Decode only the fetched vectors in Dart
3. Cosine similarity against the query vector
4. Top-N by similarity (deterministic tie-break: stableKey ascending)

Default pool ceiling: 200 vectors. Never loads all vectors.

## Storage

| Item               | Size                          |
|--------------------|-------------------------------|
| Per embedding row  | ~1.5 KB (384 × 4 bytes)       |
| 10,000 items       | ~15 MB                        |
| 50,000 items       | ~75 MB                        |

INT8 quantization is deferred — Float32 is acceptable given dimensions and
the bounded pool size. Future migration adds an `INT8` quantization tag; rows
with unknown tags are treated as stale.

## Hybrid ranking

Search combines keyword and semantic candidates:

```text
Keyword candidates (from metadata, OCR, document text)
      ↓
Semantic candidates (from vector store)
      ↓
Merge by stable_key (deduplicate, preserve keyword metadata)
      ↓
SearchRanker: keyword_score + min(semantic_score_weighted, cap)
```

### Ranking rules

1. Exact filename match (150+ points) always beats weak semantic similarity.
2. Semantic similarity (weight 30, floored at 0.35 cosine) rescues cases
   where keyword search finds nothing.
3. A semantic-only candidate (no keyword match) gets `semanticScore` only.
4. The worst keyword hit (substring OCR: 20 points) is still below the
   strongest semantic contribution (30 points), so strong semantic matches
   can surface content the keyword search barely touched.

## Limitations

* The local provider captures subword character overlap, not true semantic
  meaning. A query like "automobile" will not retrieve a document containing
  only "car". A real transformer-based embedding (e.g. MiniLM) would capture
  synonymy and paraphrase — deferred to a future prompt.
* Real transformer-based embeddings are deferred to a future prompt once a
  validated Android device and model are available.
* No ANN index yet — bounded brute-force is adequate for the current vector
  count and deferred otherwise.

## Future work

* Replace `LocalEmbeddingProvider` with a LiteRT/ONNX sentence embedding
  model (same interface, one file change).
* Add INT8 quantization to halve vector storage.
* Replace bounded brute-force with a native ANN index if vector counts
  exceed the bounded pool's effectiveness.
* Add model warmup and inference benchmarks on a physical device.