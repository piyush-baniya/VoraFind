import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'bert_tokenizer.dart';
import 'embedding_provider.dart';
import 'neural_embedding_runtime.dart';
import 'semantic_models.dart';

/// Production embedding provider: the bundled int8-quantized
/// `all-MiniLM-L6-v2` sentence transformer running fully offline via ONNX
/// Runtime (docs `semantic-search.md` §Selected model).
///
/// Responsibilities:
/// * lazily loads the model graph and WordPiece vocabulary from bundled
///   assets (never downloaded at runtime) on the first [embed];
/// * tokenizes with a port of the Hugging Face BERT tokenizer and truncates
///   to the model's 256-token ceiling ([SemanticDefaults.neuralMaxTokens]);
/// * runs inference in a fresh worker isolate per embedding (the ONNX session
///   is safe for concurrent `Run` calls), so long indexing batches never block
///   the UI thread;
/// * normalizes model failures to the [EmbeddingProvider] contract so the
///   coordinator persists durable `failed`/`unsupported` rows instead of
///   crashing the enrichment run.
///
/// [isAvailable] is optimistic before the first load (the model ships with the
/// app); a load/inference failure flips it terminal, mirroring the semantics
/// of the coordinator's `unavailable` run status.
final class NeuralEmbeddingProvider implements EmbeddingProvider {
  /// [modelBytes] and [vocabText] override the bundled assets for tests and
  /// for embedding a future model without a rebuild.
  // Public test-facing params; private init formals (`this._modelBytes`) would
  // make the constructor uncallable outside this library.
  NeuralEmbeddingProvider({Uint8List? modelBytes, String? vocabText})
    : _modelBytes = modelBytes, // ignore: prefer_initializing_formals
      _vocabText = vocabText; // ignore: prefer_initializing_formals

  final Uint8List? _modelBytes;
  final String? _vocabText;

  /// Intra-op thread count for ONNX Runtime inference. Fixed: battery-conscious
  /// single-embedding jobs benefit more from keeping the phone cool than from
  /// squeezing a few extra milliseconds out of a 384-dim pass.
  static const int _intraOpNumThreads = 2;

  OnnxSession? _session;
  BertTokenizer? _tokenizer;
  Future<OnnxSession>? _loading;
  bool _unavailable = false;

  @override
  String get modelId => SemanticDefaults.neuralModelId;

  /// Persistent tag of the Float32 vectors this provider writes. A provider
  /// that changes encoding must bump `SemanticDefaults.quantizationF32` to a
  /// new tag; rows written under an older tag are treated as stale by the
  /// repository (docs `semantic-search.md` §Versioning).
  String get quantizationTag => SemanticDefaults.quantizationF32;

  @override
  int get dimensions => SemanticDefaults.dimensions;

  @override
  bool get isAvailable => !_unavailable;

  @override
  Future<List<double>> embed(String text) async {
    final session = await _ensureLoaded();
    final tokenizer = _tokenizer!;
    final encoding = tokenizer.encode(text);

    // [CLS] + [SEP] with no content in between the model cannot represent.
    if (encoding.inputIds.length <= 2) {
      throw const EmbeddingException(EmbeddingErrorCode.unsupportedInput);
    }

    final Float32List embedded;
    try {
      embedded = await session.embed(
        inputIds: encoding.inputIds,
        attentionMask: encoding.attentionMask,
      );
    } on OnnxRuntimeException {
      throw const EmbeddingException(EmbeddingErrorCode.failed);
    } catch (_) {
      // Worker-isolate failures surface as RemoteException; treat as transient.
      throw const EmbeddingException(EmbeddingErrorCode.failed);
    }

    if (embedded.length != dimensions) {
      throw const EmbeddingException(EmbeddingErrorCode.invalidOutput);
    }
    final vector = List<double>.from(embedded);
    if (vector.any((value) => value.isNaN || value.isInfinite)) {
      throw const EmbeddingException(EmbeddingErrorCode.invalidOutput);
    }
    return vector;
  }

  /// Resolves the shared session, loading it at most once even when several
  /// embeds race during startup.
  Future<OnnxSession> _ensureLoaded() {
    final session = _session;
    if (session != null) return Future.value(session);
    if (_unavailable) {
      return Future.error(
        const EmbeddingException(EmbeddingErrorCode.unavailable),
      );
    }
    final inFlight = _loading;
    if (inFlight != null) return inFlight;
    final future = _load();
    _loading = future;
    return future;
  }

  Future<OnnxSession> _load() async {
    try {
      final modelBytes =
          _modelBytes ??
          (await rootBundle.load(SemanticDefaults.neuralModelAssetPath)).buffer
              .asUint8List();
      final vocabText =
          _vocabText ??
          await rootBundle.loadString(SemanticDefaults.neuralVocabAssetPath);
      final tokenizer = BertTokenizer.fromVocabText(
        vocabText,
        maxTokens: SemanticDefaults.neuralMaxTokens,
      );
      final options = OnnxSessionOptions(intraOpNumThreads: _intraOpNumThreads);
      final session = OnnxSession.create(
        modelBytes: modelBytes,
        options: options,
      );
      _tokenizer = tokenizer;
      _session = session;
      return session;
    } catch (_) {
      // Missing/undecodable asset or a native runtime failure: the bundled
      // model cannot serve today, and retrying on every batch would burn
      // battery. Flip terminal — the coordinator reports `unavailable`.
      _unavailable = true;
      throw const EmbeddingException(EmbeddingErrorCode.unavailable);
    } finally {
      _loading = null;
    }
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) =>
      Future.wait(texts.map(embed));

  @override
  Future<void> dispose() async {
    final session = _session;
    _session = null;
    _tokenizer = null;
    session?.release();
  }
}
