import '../search/search_normalizer.dart';

/// Bounds and policy constants for the local video visual subsystem
/// (`docs/video-visual-search.md`).
abstract final class VisualDefaults {
  /// Stable identity of the bundled vision model. Changing it invalidates every
  /// stored frame row and re-analyzes all videos (single invalidation lever,
  /// mirrors `SemanticDefaults.neuralModelId`).
  static const String visualModelId = 'mobilenet-v2-int8-v1';

  /// Bundled int8-quantized `mobilenetv2` ONNX graph (Apache-2.0, converted
  /// from the ONNX Model Zoo, opset auto-upgraded to 11 during quantization).
  /// Shipped in the APK (see `pubspec.yaml`); never downloaded at runtime.
  static const String visualModelAssetPath =
      'assets/models/mobilenetv2_int8.onnx';

  /// ImageNet class labels for the bundled model (`synset.txt`, one
  /// `label` per line — the line number indexes the 1000-class output).
  static const String visualLabelsAssetPath = 'assets/models/synset.txt';

  /// Model input side length in pixels (RGB bytes are 224×224×3).
  static const int inputDimension = 224;

  /// ImageNet labels inspected per frame before concept mapping. Taking the
  /// softmax top-N (instead of all 1000) bounds the per-frame work and keeps
  /// concept extraction reading only confident signal.
  static const int topLabelsPerFrame = 8;

  /// Frames sampled per video, uniformly spaced across the duration. Bounded
  /// indexing (AGENTS.md §12): a 4-hour video never costs more than a 1-minute
  /// clip. See `docs/video-visual-search.md` §Sampling.
  static const int maxFramesPerVideo = 12;

  /// Softmax-of-label confidence required for a concept to be persisted. Below
  /// this the label is treated as noise and dropped (retrieval stays precise).
  static const double minConceptConfidence = 0.15;

  /// Videos analyzed per coordinator batch; each batch is persisted before the
  /// next starts (AGENTS.md §12 — bounded memory, resumable).
  static const int batchSize = 2;

  /// Rank points a confidence-1.0 visual match contributes on top of keyword
  /// and semantic scores. A confidence `c` maps linearly to `c ×
  /// visualRankWeight`.
  ///
  /// Chosen to complement (never override) keyword precision: a confident
  /// visual match on a real phone (0.6–0.9 → 24–36 points) outranks the
  /// weakest metadata substring hits so raw-video queries ("find the video with
  /// the beach") surface, yet stays below any exact filename/title/OCR/doc hit
  /// and below a strong semantic match — keyword correctness keeps priority
  /// (AGENTS.md §6), and semantic meaning still beats a camera guess.
  static const int visualRankWeight = 40;

  /// Candidate pool multiplier for visual retrieval (bounded SQL fetch).
  static const int candidatePoolMultiple = 2;

  /// Absolute ceiling for the visual candidate pool.
  static const int maxCandidatePool = 200;

  /// How long a transient analysis failure cools down before retry (mirrors
  /// the OCR and semantic policies).
  static const int retryCooldownSeconds = 60 * 60;

  /// Maximum stable keys resolved in one deletion-cleanup batch.
  static const int deleteChunkSize = 500;
}

/// One recognizable visual concept with its deterministic mapping.
///
/// [labelKeywords] match against lowercase ImageNet label text (word-boundary
/// contained) at analysis time; [queryWords] match against normalized query
/// tokens at search time. A label maps to a concept when any label keyword
/// appears in the label; a query maps to a concept when any query word
/// overlaps a token. Values are curated and documented in
/// `docs/video-visual-search.md` §Concept map — this is not a learned mapping.
class VisualConceptDefinition {
  const VisualConceptDefinition({
    required this.concept,
    required this.labelKeywords,
    required this.queryWords,
  });

  /// Canonical concept identity persisted in `video_visual_frames.concept`.
  final String concept;

  /// ImageNet label fragments that imply this concept (matched with word
  /// boundaries against the lowercased label text).
  final List<String> labelKeywords;

  /// Search vocabulary that expresses this concept ("beach", "seaside", ...).
  final List<String> queryWords;
}

/// A scored concept match on one analyzed frame.
class VisualFrameConcept {
  const VisualFrameConcept({
    required this.concept,
    required this.confidenceLabel,
  });

  final String concept;

  /// Confidence of the (aggregated) ImageNet label that produced this concept,
  /// in `[minConceptConfidence, 1]`.
  final double confidenceLabel;
}

/// The best visual evidence for one video in a search: the concept that
/// matched the query, its confidence, and the frame where it appeared.
class BestVisualMatch {
  const BestVisualMatch({
    required this.concept,
    required this.confidence,
    required this.frameTsMs,
  });

  final String concept;

  /// Confidence of the frame-label that produced this concept.
  final double confidence;

  /// Millisecond timestamp of the frame inside the video ("around 0:42").
  final int frameTsMs;
}

/// Durable lifecycle of one video's visual analysis (mirrors the
/// embedding/OCR statuses). Missing row → not yet analyzed.
enum VisualVideoStatus { completed, failed, unsupported }

/// Reasons a frame could not be classified, mapped to a durable status by the
/// consumer (docs `video-visual-search.md` §Indexing lifecycle).
enum VisualErrorCode {
  /// The image/reshape produced no usable input.
  invalidInput,

  /// The runtime produced no usable output (empty logits, model mismatch).
  invalidOutput,

  /// The local model runtime is unavailable.
  unavailable,

  /// Any other transient failure (busy, initialization, native error) —
  /// retried after the cooldown.
  failed,
}

class VisualClassificationException implements Exception {
  const VisualClassificationException(this.code);

  final VisualErrorCode code;

  @override
  String toString() => 'VisualClassificationException(${code.name})';
}

/// Runtime lifecycle of one visual enrichment run (never persisted).
enum VisualRunStatus {
  idle,
  running,
  completed,
  failed,
  cancelled,

  /// The classifier (no local model) or the platform frame sampler is
  /// unavailable. Not an error — the rest of the pipeline runs unaffected.
  unavailable,
}

/// Progress snapshot emitted at batch granularity (mirrors the OCR/semantic
/// coordinators so the UI is not flooded per video).
class VisualRunProgress {
  const VisualRunProgress({
    required this.status,
    required this.processed,
    required this.total,
    required this.succeeded,
    required this.failed,
  });

  final VisualRunStatus status;

  /// Videos analyzed (or terminally skipped) so far this run.
  final int processed;

  /// Videos eligible at run start; 0 means "nothing queued".
  final int total;

  final int succeeded;
  final int failed;

  /// 0..1 share of [total] covered by [processed].
  double get fraction => total == 0 ? 1 : (processed / total).clamp(0.0, 1.0);
}

/// Terminal or interrupted outcome of one visual enrichment run.
class VisualRunSummary {
  const VisualRunSummary({
    required this.status,
    this.processed = 0,
    this.succeeded = 0,
    this.failed = 0,
    this.errorMessage,
  });

  final VisualRunStatus status;
  final int processed;
  final int succeeded;
  final int failed;

  /// Set only when the run itself failed (never for per-video outcomes).
  final String? errorMessage;
}

/// Snapshot of the visual index store for progress surfaces.
class VisualStats {
  const VisualStats({
    required this.total,
    required this.completed,
    required this.failed,
    required this.unsupported,
    required this.videoFrames,
  });

  /// Analysis rows regardless of model/state.
  final int total;
  final int completed;
  final int failed;
  final int unsupported;

  /// Persisted frame-concept rows (derived index volume).
  final int videoFrames;
}

/// Curated, deterministic vocabulary of recognizable video concepts.
///
/// Separate lookup entry points mirror the two directions search must travel:
/// mapping a label to concepts at analysis time, and mapping query tokens to
/// concepts at search time. Word-boundary containment keeps "car" from
/// matching "taxicab" twice and "beach" from matching "beach wagon" verbatim
/// in a surprising way.
abstract final class VisualConceptMap {
  static const List<VisualConceptDefinition> definitions = [
    VisualConceptDefinition(
      concept: 'mountain',
      labelKeywords: [
        'alp',
        'volcano',
        'cliff',
        'promontory',
        'valley',
        'butte',
        'mountain',
        'crag',
      ],
      queryWords: [
        'mountain',
        'mountains',
        'hill',
        'peak',
        'peakview',
        'summit',
      ],
    ),
    VisualConceptDefinition(
      concept: 'beach',
      labelKeywords: ['seashore', 'sandbar', 'seacoast', 'beach', 'breakwater'],
      queryWords: ['beach', 'beaches', 'shore', 'seaside', 'sand'],
    ),
    VisualConceptDefinition(
      concept: 'ocean',
      labelKeywords: [
        'ocean',
        'coral',
        'jellyfish',
        'whale',
        'shark',
        'squid',
        'octopus',
        'nautilus',
        'dolphin',
        'seal',
        'seaside',
      ],
      queryWords: ['ocean', 'sea', 'underwater', 'swimming', 'dive', 'diving'],
    ),
    VisualConceptDefinition(
      concept: 'lake',
      labelKeywords: [
        'lake',
        'lakeside',
        'lakefront',
        'dam',
        'fountain',
        'waterfall',
        'creek',
        'pond',
      ],
      queryWords: ['lake', 'river', 'water', 'waterfall', 'pond'],
    ),
    VisualConceptDefinition(
      concept: 'forest',
      labelKeywords: [
        'forest',
        'jungle',
        'woodland',
        'rainforest',
        'banyan',
        'pine',
        'fir',
        'oak',
        'maple',
        'birch',
        'willow',
      ],
      queryWords: [
        'forest',
        'woods',
        'jungle',
        'tree',
        'trees',
        'hiking',
        'nature',
      ],
    ),
    VisualConceptDefinition(
      concept: 'snow',
      labelKeywords: [
        'snow',
        'ice',
        'ski',
        'sledge',
        'snowmobile',
        'snowplow',
        'igloo',
      ],
      queryWords: ['snow', 'winter', 'ski', 'snowboard', 'ice'],
    ),
    VisualConceptDefinition(
      concept: 'car',
      labelKeywords: [
        'limousine',
        'convertible',
        'minivan',
        'jeep',
        'race car',
        'sports car',
        'taxicab',
        'taxi',
        'grille',
        'bumper',
        'car wheel',
        'beach wagon',
        'ambulance',
        'police van',
        'minibus',
        'trolleybus',
        'streetcar',
        'moving van',
        'pickup',
        'fire engine',
        'tow truck',
        'garbage truck',
        'trailer truck',
        'car',
      ],
      queryWords: [
        'car',
        'cars',
        'vehicle',
        'drive',
        'driving',
        'road',
        'auto',
        'automobile',
      ],
    ),
    VisualConceptDefinition(
      concept: 'motorcycle',
      labelKeywords: ['motorcycle', 'moped', 'scooter', 'crash helmet'],
      queryWords: ['motorcycle', 'motorbike', 'scooter', 'riding'],
    ),
    VisualConceptDefinition(
      concept: 'bicycle',
      labelKeywords: ['bicycle', 'mountain bike', 'unicycle', 'tricycle'],
      queryWords: ['bicycle', 'bike', 'biking', 'cycling', 'cycle'],
    ),
    VisualConceptDefinition(
      concept: 'airplane',
      labelKeywords: [
        'airplane',
        'airliner',
        'aircraft',
        'seaplane',
        'wing',
        'helicopter',
        'jet',
      ],
      queryWords: [
        'airplane',
        'plane',
        'flight',
        'flying',
        'aviation',
        'airport',
        'jet',
      ],
    ),
    VisualConceptDefinition(
      concept: 'boat',
      labelKeywords: [
        'canoe',
        'kayak',
        'yawl',
        'yacht',
        'catamaran',
        'schooner',
        'speedboat',
        'lifeboat',
        'fireboat',
        'gondola',
        'paddlewheel',
        'rowboat',
        'fishing boat',
        'container ship',
        'boat',
      ],
      queryWords: [
        'boat',
        'boats',
        'sailing',
        'sail',
        'yacht',
        'canoeing',
        'kayak',
      ],
    ),
    VisualConceptDefinition(
      concept: 'train',
      labelKeywords: [
        'locomotive',
        'railroad',
        'railway',
        'tram',
        'subway',
        'freight car',
        'passenger car',
      ],
      queryWords: ['train', 'railway', 'tracks', 'railroad', 'metro'],
    ),
    VisualConceptDefinition(
      concept: 'person',
      labelKeywords: [
        'person',
        'man',
        'woman',
        'baby',
        'child',
        'boy',
        'girl',
        'pedestrian',
        'bride',
        'groom',
        'photographer',
        'scuba diver',
        'suit',
      ],
      queryWords: [
        'person',
        'people',
        'selfie',
        'family',
        'friend',
        'wedding',
        'birthday',
        'celebration',
        'group',
        'man',
        'woman',
      ],
    ),
    VisualConceptDefinition(
      concept: 'dog',
      labelKeywords: [
        'dog',
        'puppy',
        'terrier',
        'hound',
        'spaniel',
        'retriever',
        'poodle',
        'collie',
        'shepherd',
        'corgi',
        'husky',
        'malamute',
        'chihuahua',
        'papillon',
        'mastiff',
        'whippet',
        'pug',
        'pinscher',
        'schnauzer',
        'dalmatian',
        'pomeranian',
        'keeshond',
        'shih',
        'bluetick',
        'bloodhound',
        'deerhound',
        'vizsla',
        'saluki',
        'cairn',
        'borzoi',
        'maltese',
        'pekinese',
        'basenji',
        'basset',
        'beagle',
        'briard',
        'greyhound',
        'labrador',
        'leonberg',
        'lhasa',
        'newfoundland',
        'otterhound',
        'samoyed',
        'kelpie',
        'komondor',
        'havanese',
        'puli',
        'shiba',
        'cocker',
      ],
      queryWords: ['dog', 'dogs', 'puppy', 'pet', 'pets', 'walk'],
    ),
    VisualConceptDefinition(
      concept: 'cat',
      labelKeywords: [
        'cat',
        'tabby',
        'tiger cat',
        'persian cat',
        'siamese',
        'egyptian cat',
        'lynx',
        'cougar',
      ],
      queryWords: ['cat', 'cats', 'kitten', 'pet', 'pets'],
    ),
    VisualConceptDefinition(
      concept: 'wildlife',
      labelKeywords: [
        'tiger',
        'lion',
        'leopard',
        'elephant',
        'zebra',
        'giraffe',
        'rhino',
        'hippo',
        'monkey',
        'chimpanzee',
        'gorilla',
        'bear',
        'panda',
        'koala',
        'kangaroo',
        'deer',
        'moose',
        'bison',
        'camel',
        'fox',
        'wolf',
        'raccoon',
        'squirrel',
        'rabbit',
        'hedgehog',
        'porcupine',
        'otter',
        'badger',
        'skunk',
        'snake',
        'lizard',
        'turtle',
        'frog',
        'crocodile',
        'alligator',
        'tortoise',
        'iguana',
        'gecko',
        'penguin',
        'ostrich',
        'peacock',
        'parrot',
        'eagle',
        'owl',
        'hawk',
        'falcon',
        'swan',
        'goose',
        'duck',
        'flamingo',
        'pigeon',
        'crow',
        'turkey',
        'butterfly',
        'bee',
        'beetle',
        'starfish',
      ],
      queryWords: [
        'animal',
        'animals',
        'wildlife',
        'safari',
        'zoo',
        'penguin',
        'bird',
      ],
    ),
    VisualConceptDefinition(
      concept: 'food',
      labelKeywords: [
        'pizza',
        'burger',
        'hotdog',
        'sandwich',
        'steak',
        'soup',
        'salad',
        'spaghetti',
        'pancake',
        'waffle',
        'croissant',
        'bagel',
        'pretzel',
        'cheeseburger',
        'french loaf',
        'ice cream',
        'chocolate',
        'donut',
        'cake',
        'cookie',
        'pie',
        'taco',
        'burrito',
        'guacamole',
        'sushi',
        'candy',
        'popcorn',
        'kebab',
        'gyro',
        'mushroom',
        'pasta',
        'potato',
        'corn',
        'bean',
        'pepper',
        'onion',
        'tomato',
        'apple',
        'banana',
        'orange',
        'mango',
        'pineapple',
        'grape',
        'pear',
        'peach',
        'strawberry',
        'lemon',
        'pomegranate',
      ],
      queryWords: [
        'food',
        'cooking',
        'cook',
        'eat',
        'eating',
        'recipe',
        'breakfast',
        'lunch',
        'dinner',
        'snack',
        'meal',
        'restaurant',
        'pizza',
        'coffee',
      ],
    ),
    VisualConceptDefinition(
      concept: 'laptop',
      labelKeywords: [
        'laptop',
        'notebook',
        'computer',
        'keyboard',
        'monitor',
        'screen',
        'hard disk',
        'joystick',
        'webcam',
        'mouse',
        'modem',
      ],
      queryWords: ['laptop', 'computer', 'desktop', 'coding', 'work', 'office'],
    ),
    VisualConceptDefinition(
      concept: 'phone',
      labelKeywords: [
        'cellphone',
        'iphone',
        'telephone',
        'hand-held computer',
        'ipod',
      ],
      queryWords: ['phone', 'mobile', 'iphone', 'smartphone'],
    ),
    VisualConceptDefinition(
      concept: 'city',
      labelKeywords: [
        'skyscraper',
        'palace',
        'castle',
        'church',
        'mosque',
        'synagogue',
        'temple',
        'monastery',
        'dome',
        'grocery store',
        'bookshop',
        'restaurant',
        'street sign',
        'traffic light',
        'market',
        'shop',
      ],
      queryWords: ['city', 'urban', 'cityscape', 'downtown', 'street', 'town'],
    ),
    VisualConceptDefinition(
      concept: 'wedding',
      labelKeywords: [
        'bride',
        'groom',
        'wedding',
        'gown',
        'tuxedo',
        'kimono',
        'mortarboard',
        'academic gown',
      ],
      queryWords: ['wedding', 'marriage', 'bride', 'groom'],
    ),
  ];

  static final Map<String, VisualConceptDefinition> _byName = {
    for (final definition in definitions) definition.concept: definition,
  };

  /// Maps ImageNet label text to the concepts its keywords imply.
  ///
  /// Word-boundary containment on the lowercased label: "sports car, sport
  /// car" implies `car`, "tabby, tabby cat" implies `cat`, and "beach wagon"
  /// implies both `car` and `beach` (its literal words). Used only over the
  /// softmax top-[VisualDefaults.topLabelsPerFrame], so cost is bounded.
  static Set<String> conceptsForLabel(String label) {
    final lower = label.toLowerCase();
    final result = <String>{};
    for (final definition in definitions) {
      for (final keyword in definition.labelKeywords) {
        if (_containsWord(lower, keyword)) {
          result.add(definition.concept);
          break;
        }
      }
    }
    return result;
  }

  /// Maps normalized query tokens to the concepts they express.
  ///
  /// A token matches a concept when it equals a query word, is a prefix of one,
  /// or one is the prefix of it ("mountain", "mountains", "beach" from
  /// "beachside"). Deterministic; unmapped tokens are ignored (visual search is
  /// a recall complement, never a filter).
  static Set<String> conceptsForTokens(Iterable<String> tokens) {
    final result = <String>{};
    final canonTokens = [
      for (final token in tokens)
        if (token.isNotEmpty) SearchNormalizer.canonical(token),
    ];
    for (final definition in definitions) {
      for (final word in definition.queryWords) {
        final canonWord = SearchNormalizer.canonical(word);
        if (canonWord.isEmpty) continue;
        for (final token in canonTokens) {
          if (token == canonWord ||
              canonWord.startsWith(token) ||
              token.startsWith(canonWord)) {
            result.add(definition.concept);
            break;
          }
        }
      }
    }
    return result;
  }

  static bool _containsWord(String text, String keyword) {
    if (keyword.isEmpty) return false;
    final escaped = RegExp.escape(keyword);
    return RegExp(
      '(^|[^\\p{L}\\p{N}])$escaped([^\\p{L}\\p{N}]|\$)',
      unicode: true,
    ).hasMatch(text);
  }

  /// Whether [concept] is a known concept identity.
  static bool contains(String concept) => _byName.containsKey(concept);
}
