# Similar Image Search

Local, on-device image-to-image similarity for VoraFind. A 1280-dimensional
MobileNetV2 feature vector is compared against every indexed image vector using
cosine similarity, returning the closest matches. Everything runs offline; no
image pixels or embeddings leave the device.

Two user flows:

* **Flow A** — tap a similar-images button on an indexed image result tile to
  find visually related images already stored on the phone.
* **Flow B** — pick any image from a gallery picker; the app decodes it once,
  embeds it ephemerally, and returns similar indexed images.

Both flows are served by the same `SimilarImageService` which delegates
embedding and retrieval to the image visual subsystem introduced for
prompt #16.

## Non-goals

Duplicate detection, face recognition, OCR-based similarity, content-based
recommendations, cloud AI, semantic search across text-and-image, neural
re-ranking, and WorkManager scheduling are explicitly out of scope.

## Architecture

```
LOCAL CONTENT (images)
       ↓
IMAGE INDEXING
  ┌───────────────────────────────┐
  │ image_visual_index_coordinator│
  │   pixel source → provider     │
  │   → DriftImageVisualRepository│
  └───────────────────────────────┘
       ↓
image_visual_embeddings table
  (stableKey, vector, modelId, dimensions, status)
       ↓
QUERY
  ┌───────────────────────────────┐
  │ SimilarImageService           │
  │  Flow A: getCurrentEmbedding  │
  │  Flow B: pick → readImageRgb  │
  │          → embed → ephemeral  │
  │  → findSimilarImages (SQL)    │
  │  → cosine scoring             │
  └───────────────────────────────┘
       ↓
RANKED RESULTS (top-24)
```

## Model and license

| Item              | Value                                                          |
|-------------------|----------------------------------------------------------------|
| Model             | MobileNetV2 (`mobilenetv2-12`, ONNX Model Zoo)                |
| Source            | `mobilenetv2-12.onnx` (opset 12, 1000-class image classifier)|
| Slice point       | `GlobalAveragePool` → output `464` `[1, 1280, 1, 1]` FLOAT   |
| Graph asset       | `assets/models/mobilenetv2_features.onnx` — **8.8 MB float**  |
| Dimensions        | 1280                                                           |
| Model ID          | `mobilenet-v2-features-v1` (`ImageVisualDefaults.modelId`)     |
| Quantization      | float32 (the plugin's ORT build lacks `ConvInteger` support)   |
| License           | Apache-2.0 (ONNX Model Zoo, Play-Store compatible)            |
| Input             | 224×224×3 BGR, NCHW float                                     |
| Preprocessing     | `(pixel - mean) / std` per-channel: B (103.53, 57.375), G (116.28, 57.12), R (123.675, 58.395) |
| Normalization     | L2, applied after ONNX inference                              |

The sliced float model was produced from the ONNX Model Zoo `mobilenetv2-12`
graph. The original graph outputs 1000 ImageNet class logits; the slice
removes the classification head and retains only the GlobalAveragePool feature
embedding, reducing the APK delta from ~14 MB to ~9 MB while keeping identical
visual feature quality.

### Host validation

Measured on the host with the exact Python equivalents of
`ImagePreprocessor.mobilenetNchw` and L2 normalization:

| Pair              | Cosine similarity |
|-------------------|-------------------|
| blue ↔ blue       | 1.000             |
| blue ↔ green      | 0.784             |
| blue ↔ noise      | 0.509             |

The float model produces feature vectors in the same range as the original int8
slice but loads reliably on the bundled ORT build (the int8 models contain
`ConvInteger` ops the plugin cannot execute).

## Provider internals

| Property       | Value                                                      |
|----------------|------------------------------------------------------------|
| Model ID       | `mobilenet-v2-features-v1`                                 |
| Dimensions     | 1280                                                       |
| Preprocessing  | `ImagePreprocessor.mobilenetNchw` (BGR mean/std)           |
| Normalization  | L2 (applied in `NeuralImageEmbeddingProvider`)              |
| Runtime        | `VisionOnnxSession` (identical FFI pattern to BERT runtime)|
| Concurrency    | One fresh worker isolate per embed (session reused)         |
| Deterministic  | Yes (host-validated, identical across calls)                |

`DeterministicImageEmbeddingProvider` is retained as a test fixture for the
pipeline tests — never wired into production.

## Similarity and thresholds

The cosine similarity range for real images in this feature space sits above
0.4 for related images. The retrieval minimum `minSimilarity = 0.4` rejects
only degenerate or zero-norm matches; real visual similarity is determined
entirely by the top-K ranking, which never lets an unrelated image push a
similar one out.

| Parameter              | Value  | Purpose                               |
|------------------------|--------|---------------------------------------|
| `minSimilarity`        | 0.4    | Floor below which a match is excluded |
| `topK`                 | 24     | Maximum results returned              |
| `candidatePoolMultiple`| 2×     | SQL fetch multiplier                  |
| `maxCandidatePool`     | 200    | Absolute SQL fetch cap                |

Tie-breaking is deterministic: similarity descending → stableKey ascending.

## Indexing lifecycle

Image embedding runs after the video visual stage in the indexing coordinator.

```
idle → running → completed | failed | cancelled | unavailable
```

| Status          | Meaning                                                  |
|-----------------|----------------------------------------------------------|
| `completed`     | Vector stored, `modelId` + `dimensions` recorded         |
| `failed`        | Transient; retries after `retryCooldownSeconds` (1 hour) |
| `unsupported`   | Terminal (zero-size read, wrong model/dims, bad vector)   |

One corrupt image never stops the remaining queue — each failure is isolated.

The `image_visual_embeddings` Drift table is joined with `media_items` on
`stableKey` and cascade-deleted when a media row is removed.

## Retrieval SQL

`DriftImageVisualRepository.findSimilarImages` runs a bounded SQL query
limited to `maxCandidatePool` rows, decodes the vectors in Dart, computes
cosine similarity, applies `minSimilarity`, and returns the top-K. No
repeated full-library scans.

Optional SQL filters applied before ranking:

* `isScreenshot` — boolean
* `dateFrom` / `dateTo` — `dateModified` bounds
* `pathPrefix` — `LIKE` prefix on `relativePath`
* `excludeStableKey` — omits the reference image from results

## UI integration

### Flow A — on indexed image tiles

Image search result tiles display a small "similar images" action button
(`Icons.image_search_outlined`). Tapping pushes `SimilarImagesScreen` with the
tile's stable key, content URI, and display metadata.

### Flow B — pick any image

An "Find similar image" button in the idle home state triggers a platform
gallery picker (`ImagePixelSource.pickImage`). The selected URI is forwarded
to `SimilarImagesScreen`, which decodes the pixels once via the method channel,
embeds them ephemerally (never persisted), and retrieves similar indexed images.

### Screen states

* Loading: circular progress with "Scanning library…"
* Results: grid (3 columns) showing thumbnail + name + similarity percentage
* Empty: "No similar images found"
* Error: mapped from `SimilarImageErrorCode` to a user-readable message

## Error mapping

`SimilarImageService` maps platform and embedding errors to a stable error
code surface for the UI:

| `SimilarImageErrorCode` | Source conditions                               |
|-------------------------|------------------------------------------------|
| `notIndexed`            | Flow A: stored embedding is null (pending index)|
| `decodeFailed`          | corrupt / denied / invalidContentUri / unsupported pixel read; invalidInput embedding |
| `unavailable`           | platform runtime or embedding provider unavailable |
| `failed`                | any other transient error                      |

A throwing pixel decode is caught and mapped to `failed` — it never crashes
the search flow.

## Testing

All pipeline behavior is covered by unit tests:

* `DriftImageVisualRepository` — persistence, eligibility, retrieval with
  media filters, malformed-row safety, cross-boundary isolation.
* `ImageVisualIndexCoordinator` — unavailable short-circuit, failure
  isolation, cancellation, resumability.
* `SimilarImageService` — Flow A / Flow B, error mapping, self-match
  exclusion, missing-media filtering, throwing-pixel safety.
* `ImageEmbeddingFixture` — real-model inference (guarded by
  `OnnxRuntime.isAvailable()`), determinism, norm, similarity ordering.
* `media_items_test` — migration tests updated for schema v8.

## Out of scope (discovered during implementation)

The video visual classifier's `mobilenetv2_int8.onnx` model contains
`ConvInteger` ops that the bundled ONNX Runtime build cannot execute on any
platform. This is a pre-existing latent issue unrelated to image similarity
and is tracked separately.

## See also

* `image_visual_models.dart` — all bounds and policy constants
* `docs/semantic-search.md` — the parallel text-embedding pipeline
