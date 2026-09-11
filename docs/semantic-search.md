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

**No model ships in this prompt.** `UnavailableEmbeddingProvider` is the
production wiring today — the subsystem is honestly unavailable and does no
work. The rest of the pipeline is unaffected.

### Evaluation criteria (for the eventual model decision)

Any candidate must satisfy:

1. **Size** — small enough for a typical Android APK (target < 50 MB total
   model footprint).
2. **RAM** — peak memory within budget for mid-range devices during inference.
3. **CPU** — single-embedding latency that keeps batch indexing responsive.
4. **Dimensions** — moderate (128–768) so storage and retrieval stay bounded.
5. **Quantization** — INT8/float16 preferred to halve storage with minimal
   quality loss.
6. **License** — compatible with an Android app distributed via Play Store.
7. **Offline** — must run entirely on-device with no network dependency.
8. **Flutter integration** — a maintained LiteRT/TFLite/ONNX runtime, or a
   thin native bridge.
9. **Compatibility** — targets ARM64 and x86_64 with graceful fallbacks.

Candidates evaluated directionally: LiteRT-compatible MiniLM-style sentence
embedding models, and compact ONNX embedding models. The final selection is
deferred; the architecture lets a real model drop in behind `EmbeddingProvider`
without any search-layer change.