import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
// VoraFind intentionally imports only the generated pure-`dart:ffi` bindings,
// never the package-level `onnxruntime.dart` facade, which opens the native
// library at library-load time (crashing any process without the DLL). This
// is a deliberate, documented design decision — see `docs/semantic-search.md`
// §Runtime.
// ignore: implementation_imports
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart'
    as bg;

/// ONNX Runtime C API version negotiated via `OrtGetApiBase().GetApi`.
///
/// api-14 matches the `onnxruntime` pub package; every function this wrapper
/// uses (`CreateEnv`, `CreateSessionFromArray`, `Run`, tensor accessors)
/// predates it by many releases, so this is a stable ceiling, not a feature
/// gate.
const int _ortApiVersion = 14;

/// Embedding dimension of the bundled `all-MiniLM-L6-v2` model — every token's
/// `last_hidden_state` row is 384 floats. Mirrors
/// `SemanticDefaults.dimensions`; repeated here because the runtime layer must
/// not depend on the app model layer.
const int _embeddingDimension = 384;

/// How the native `onnxruntime` shared library is located at runtime.
///
/// Android loads the plugin-bundled `libonnxruntime.so`. On Windows hosts we
/// resolve the DLL shipped inside the `onnxruntime` pub package (so unit tests
/// can exercise real inference); other platforms fall back to name-based opens.
abstract final class OnnxRuntime {
  static ffi.DynamicLibrary openLibrary() {
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libonnxruntime.so');
    }
    if (Platform.isWindows) {
      final packaged = _windowsPackageLibrary();
      if (packaged != null) {
        return ffi.DynamicLibrary.open(packaged);
      }
      return ffi.DynamicLibrary.open('onnxruntime.dll');
    }
    if (Platform.isIOS) {
      return ffi.DynamicLibrary.process();
    }
    if (Platform.isMacOS) {
      return ffi.DynamicLibrary.open('libonnxruntime.1.15.1.dylib');
    }
    if (Platform.isLinux) {
      return ffi.DynamicLibrary.open('libonnxruntime.so.1.15.1');
    }
    throw UnsupportedError('unsupported platform: ${Platform.operatingSystem}');
  }

  /// True when the native library loads on this platform right now. Host tests
  /// use this to skip inference assertions when the DLL is unavailable.
  static bool isAvailable() {
    try {
      openLibrary();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Absolute path of the DLL shipped inside the `onnxruntime` pub package,
  /// resolved via `.dart_tool/package_config.json` so no pub-cache location is
  /// ever hard-coded.
  static String? _windowsPackageLibrary() {
    try {
      final packageConfig = File('.dart_tool/package_config.json');
      if (!packageConfig.existsSync()) return null;
      final packages =
          (jsonDecode(packageConfig.readAsStringSync()) as Map)['packages']
              as List;
      for (final package in packages.cast<Map>()) {
        if (package['name'] != 'onnxruntime') continue;
        final rootUri = package['rootUri'] as String;
        final root = rootUri.startsWith('file://')
            ? Uri.parse(rootUri).toFilePath()
            : rootUri;
        final candidate = File(
          '$root${Platform.pathSeparator}windows'
          '${Platform.pathSeparator}onnxruntime.dll',
        );
        if (candidate.existsSync()) return candidate.absolute.path;
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

/// Thrown for any native ONNX Runtime failure. The embedding provider maps
/// these to durable [EmbeddingErrorCode] values; this type keeps the runtime
/// wrapper ML-agnostic.
final class OnnxRuntimeException implements Exception {
  const OnnxRuntimeException(this.message);

  final String message;

  @override
  String toString() => 'OnnxRuntimeException: $message';
}

/// Holds the negotiated API pointer AND the bindings object that produced it,
/// so the native library handle is never collected while pointer calls are in
/// flight. One per isolate that touches native memory.
final class _OrtApi {
  _OrtApi() : _bindings = bg.OnnxRuntimeBindings(OnnxRuntime.openLibrary()) {
    _ptr = _bindings.OrtGetApiBase().ref.GetApi
        .asFunction<ffi.Pointer<bg.OrtApi> Function(int)>()(_ortApiVersion);
  }

  final bg.OnnxRuntimeBindings _bindings;
  late final ffi.Pointer<bg.OrtApi> _ptr;

  ffi.Pointer<bg.OrtApi> get ptr => _ptr;

  /// Rolls a status pointer into an [OnnxRuntimeException] (mirrors the
  /// upstream `OrtStatus.checkOrtStatus` error extraction).
  void check(ffi.Pointer<bg.OrtStatus> status, String operation) {
    if (status == ffi.nullptr) return;
    final message = _ptr.ref.GetErrorMessage
        .asFunction<
          ffi.Pointer<ffi.Char> Function(ffi.Pointer<bg.OrtStatus>)
        >()(status)
        .cast<Utf8>()
        .toDartString();
    _ptr.ref.ReleaseStatus
        .asFunction<void Function(ffi.Pointer<bg.OrtStatus>)>()(status);
    throw OnnxRuntimeException('$operation: $message');
  }
}

/// Prepared session options: CPU execution provider, modest intra-op thread
/// count (battery-conscious indexing on phones), and full graph optimization.
///
/// Handed to [OnnxSession.create] via [releaseSessionOptions] and destroyed
/// with the session.
final class OnnxSessionOptions {
  OnnxSessionOptions({this.intraOpNumThreads = 2}) {
    final optionsPtrPtr = calloc<ffi.Pointer<bg.OrtSessionOptions>>();
    final status = _api.ptr.ref.CreateSessionOptions
        .asFunction<
          bg.OrtStatusPtr Function(
            ffi.Pointer<ffi.Pointer<bg.OrtSessionOptions>>,
          )
        >()(optionsPtrPtr);
    _api.check(status, 'CreateSessionOptions');
    _sessionOptions = optionsPtrPtr.value;
    calloc.free(optionsPtrPtr);

    _api.check(
      _api.ptr.ref.SetIntraOpNumThreads
          .asFunction<
            bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>, int)
          >()(_sessionOptions!, intraOpNumThreads),
      'SetIntraOpNumThreads',
    );
    _api.check(
      _api.ptr.ref.SetSessionGraphOptimizationLevel
          .asFunction<
            bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>, int)
          >()(_sessionOptions!, bg.GraphOptimizationLevel.ORT_ENABLE_ALL),
      'SetSessionGraphOptimizationLevel',
    );
  }

  final _OrtApi _api = _OrtApi();
  ffi.Pointer<bg.OrtSessionOptions>? _sessionOptions;
  final int intraOpNumThreads;

  void release() {
    final options = _sessionOptions;
    if (options == null) return;
    _api.ptr.ref.ReleaseSessionOptions
        .asFunction<void Function(ffi.Pointer<bg.OrtSessionOptions>)>()(
      options,
    );
    _sessionOptions = null;
  }

  ffi.Pointer<bg.OrtSessionOptions> releaseSessionOptions() {
    final options = _sessionOptions;
    if (options == null) {
      throw StateError('session options already released');
    }
    _sessionOptions = null;
    return options;
  }
}

/// A loaded, CPU-only ONNX Runtime environment bound to one model.
///
/// Owned by the calling (main) isolate: environment and session are created
/// and destroyed here. Inference runs in a fresh worker isolate (see [embed])
/// because spawned isolates cannot capture [ffi.Pointer] or
/// [ffi.DynamicLibrary] values — each worker reopens the library,
/// re-negotiates the API pointer, and reuses this session's pointer address.
/// ONNX Runtime sessions are safe for concurrent `Run` calls.
final class OnnxSession {
  OnnxSession._(
    this._api,
    this._env,
    this._session,
    this._inputNames,
    this._outputNames,
  );

  /// Creates a session from raw model bytes.
  ///
  /// [modelBytes] are copied by ONNX Runtime during `CreateSessionFromArray`
  /// (matching the upstream package, which frees the source buffer immediately
  /// after creation).
  static OnnxSession create({
    required Uint8List modelBytes,
    required OnnxSessionOptions options,
  }) {
    final api = options._api;
    final envPtrPtr = calloc<ffi.Pointer<bg.OrtEnv>>();
    final envStatus =
        api.ptr.ref.CreateEnv
            .asFunction<
              bg.OrtStatusPtr Function(
                int,
                ffi.Pointer<ffi.Char>,
                ffi.Pointer<ffi.Pointer<bg.OrtEnv>>,
              )
            >()(
          bg.OrtLoggingLevel.ORT_LOGGING_LEVEL_WARNING,
          'vorafind'.toNativeUtf8().cast<ffi.Char>(),
          envPtrPtr,
        );
    api.check(envStatus, 'CreateEnv');
    final env = envPtrPtr.value;
    calloc.free(envPtrPtr);

    final sessionOptions = options.releaseSessionOptions();
    final sessionPtrPtr = calloc<ffi.Pointer<bg.OrtSession>>();
    final bytes = calloc<ffi.Uint8>(modelBytes.length);
    bytes
        .asTypedList(modelBytes.length)
        .setRange(0, modelBytes.length, modelBytes);
    final status =
        api.ptr.ref.CreateSessionFromArray
            .asFunction<
              bg.OrtStatusPtr Function(
                ffi.Pointer<bg.OrtEnv>,
                ffi.Pointer<ffi.Void>,
                int,
                ffi.Pointer<bg.OrtSessionOptions>,
                ffi.Pointer<ffi.Pointer<bg.OrtSession>>,
              )
            >()(
          env,
          bytes.cast(),
          modelBytes.length,
          sessionOptions,
          sessionPtrPtr,
        );
    calloc.free(bytes);
    api.check(status, 'CreateSessionFromArray');
    final session = sessionPtrPtr.value;
    calloc.free(sessionPtrPtr);

    // The options blob is no longer needed once the session is created.
    api.ptr.ref.ReleaseSessionOptions
        .asFunction<void Function(ffi.Pointer<bg.OrtSessionOptions>)>()(
      sessionOptions,
    );

    return OnnxSession._(
      api,
      env,
      session,
      _readTensorNames(api, session, output: false),
      _readTensorNames(api, session, output: true),
    );
  }

  final _OrtApi _api;
  final ffi.Pointer<bg.OrtEnv> _env;
  final ffi.Pointer<bg.OrtSession> _session;
  final List<String> _inputNames;
  final List<String> _outputNames;

  /// Model input names in graph order (`input_ids`, `attention_mask`,
  /// `token_type_ids` for the bundled model).
  List<String> get inputNames => List.unmodifiable(_inputNames);

  /// Declared output tensor names (a single `last_hidden_state`).
  List<String> get outputNames => List.unmodifiable(_outputNames);

  /// Runs inference for one tokenized sequence and returns the sentence
  /// embedding: mean-pooled over unmasked positions, then L2-normalized
  /// (the sentence-transformers `all-MiniLM-L6-v2` `1_Pooling` +
  /// `2_Normalize` contract — see `docs/semantic-search.md` §Pooling).
  ///
  /// Runs in a fresh worker isolate; only sendable values are captured (never
  /// `this`), so the main isolate stays responsive during indexing.
  Future<Float32List> embed({
    required List<int> inputIds,
    required List<int> attentionMask,
  }) {
    final sessionAddress = _session.address;
    final inputNames = List<String>.of(_inputNames);
    final outputName = _outputNames.first;
    final ids = Int64List.fromList(inputIds);
    final mask = Int64List.fromList(attentionMask);
    final typeIds = Int64List.fromList(List<int>.filled(inputIds.length, 0));
    return Isolate.run(
      () => _runIsolate(
        sessionAddress: sessionAddress,
        inputNames: inputNames,
        outputName: outputName,
        inputIds: ids,
        attentionMask: mask,
        tokenTypeIds: typeIds,
      ),
    );
  }

  /// Releases the session and its environment. Safe to call once; subsequent
  /// [embed] calls fail in the worker and surface as provider failures rather
  /// than crashing.
  void release() {
    _api.ptr.ref.ReleaseSession
        .asFunction<void Function(ffi.Pointer<bg.OrtSession>)>()(_session);
    _api.ptr.ref.ReleaseEnv.asFunction<void Function(ffi.Pointer<bg.OrtEnv>)>()(
      _env,
    );
  }

  static List<String> _readTensorNames(
    _OrtApi api,
    ffi.Pointer<bg.OrtSession> session, {
    required bool output,
  }) {
    final countPtr = calloc<ffi.Size>();
    api.check(
      output
          ? api.ptr.ref.SessionGetOutputCount
                .asFunction<
                  bg.OrtStatusPtr Function(
                    ffi.Pointer<bg.OrtSession>,
                    ffi.Pointer<ffi.Size>,
                  )
                >()(session, countPtr)
          : api.ptr.ref.SessionGetInputCount
                .asFunction<
                  bg.OrtStatusPtr Function(
                    ffi.Pointer<bg.OrtSession>,
                    ffi.Pointer<ffi.Size>,
                  )
                >()(session, countPtr),
      output ? 'SessionGetOutputCount' : 'SessionGetInputCount',
    );
    final count = countPtr.value;
    calloc.free(countPtr);

    final allocator = _defaultAllocator(api);
    final names = <String>[];
    for (var i = 0; i < count; i++) {
      final namePtrPtr = calloc<ffi.Pointer<ffi.Char>>();
      api.check(
        output
            ? api.ptr.ref.SessionGetOutputName
                  .asFunction<
                    bg.OrtStatusPtr Function(
                      ffi.Pointer<bg.OrtSession>,
                      int,
                      ffi.Pointer<bg.OrtAllocator>,
                      ffi.Pointer<ffi.Pointer<ffi.Char>>,
                    )
                  >()(session, i, allocator, namePtrPtr)
            : api.ptr.ref.SessionGetInputName
                  .asFunction<
                    bg.OrtStatusPtr Function(
                      ffi.Pointer<bg.OrtSession>,
                      int,
                      ffi.Pointer<bg.OrtAllocator>,
                      ffi.Pointer<ffi.Pointer<ffi.Char>>,
                    )
                  >()(session, i, allocator, namePtrPtr),
        output ? 'SessionGetOutputName' : 'SessionGetInputName',
      );
      names.add(namePtrPtr.value.cast<Utf8>().toDartString());
      api.check(
        api.ptr.ref.AllocatorFree
            .asFunction<
              bg.OrtStatusPtr Function(
                ffi.Pointer<bg.OrtAllocator>,
                ffi.Pointer<ffi.Void>,
              )
            >()(allocator, namePtrPtr.value.cast()),
        'AllocatorFree',
      );
      calloc.free(namePtrPtr);
    }
    return names;
  }

  static ffi.Pointer<bg.OrtAllocator> _defaultAllocator(_OrtApi api) {
    final allocatorPtrPtr = calloc<ffi.Pointer<bg.OrtAllocator>>();
    api.check(
      api.ptr.ref.GetAllocatorWithDefaultOptions
          .asFunction<
            bg.OrtStatusPtr Function(ffi.Pointer<ffi.Pointer<bg.OrtAllocator>>)
          >()(allocatorPtrPtr),
      'GetAllocatorWithDefaultOptions',
    );
    final allocator = allocatorPtrPtr.value;
    calloc.free(allocatorPtrPtr);
    return allocator;
  }
}

// ---------------------------------------------------------------------------
// Worker-isolate inference path.
//
// `Isolate.run` serializes its closure: it may carry only sendable values
// (strings, numbers, typed-data lists) — never a pointer or library. The
// worker therefore reopens the native library, re-negotiates the API pointer,
// and reuses the main-isolate session pointer by address. After `Run` it reads
// the `last_hidden_state` tensor and performs mean-pooling + L2 normalization,
// so only 384 floats (or one error) cross the isolate boundary.
// ---------------------------------------------------------------------------

Float32List _runIsolate({
  required int sessionAddress,
  required List<String> inputNames,
  required String outputName,
  required Int64List inputIds,
  required Int64List attentionMask,
  required Int64List tokenTypeIds,
}) {
  final api = _OrtApi();
  final session = ffi.Pointer<bg.OrtSession>.fromAddress(sessionAddress);
  final seq = inputIds.length;

  final inputNamePtrs = calloc<ffi.Pointer<ffi.Char>>(inputNames.length);
  for (var i = 0; i < inputNames.length; i++) {
    inputNamePtrs[i] = inputNames[i].toNativeUtf8().cast<ffi.Char>();
  }
  final outputNamePtrs = calloc<ffi.Pointer<ffi.Char>>(1);
  outputNamePtrs[0] = outputName.toNativeUtf8().cast<ffi.Char>();

  final memoryInfo = _cpuMemoryInfo(api);
  final inputPtrs = calloc<ffi.Pointer<bg.OrtValue>>(3);
  final tensors = <(ffi.Pointer<bg.OrtValue>, ffi.Pointer<ffi.Int64>)>[];
  try {
    for (final data in [inputIds, attentionMask, tokenTypeIds]) {
      tensors.add(_createInt64Tensor(api, memoryInfo, data: data));
    }
    for (var i = 0; i < tensors.length; i++) {
      inputPtrs[i] = tensors[i].$1;
    }

    final runOptionsPtrPtr = calloc<ffi.Pointer<bg.OrtRunOptions>>();
    api.check(
      api.ptr.ref.CreateRunOptions
          .asFunction<
            bg.OrtStatusPtr Function(ffi.Pointer<ffi.Pointer<bg.OrtRunOptions>>)
          >()(runOptionsPtrPtr),
      'CreateRunOptions',
    );
    final runOptions = runOptionsPtrPtr.value;
    calloc.free(runOptionsPtrPtr);

    try {
      final outputPtr = calloc<ffi.Pointer<bg.OrtValue>>();
      outputPtr.value = ffi.nullptr;
      api.check(
        api.ptr.ref.Run
            .asFunction<
              bg.OrtStatusPtr Function(
                ffi.Pointer<bg.OrtSession>,
                ffi.Pointer<bg.OrtRunOptions>,
                ffi.Pointer<ffi.Pointer<ffi.Char>>,
                ffi.Pointer<ffi.Pointer<bg.OrtValue>>,
                int,
                ffi.Pointer<ffi.Pointer<ffi.Char>>,
                int,
                ffi.Pointer<ffi.Pointer<bg.OrtValue>>,
              )
            >()(
          session,
          runOptions,
          inputNamePtrs,
          inputPtrs,
          3,
          outputNamePtrs,
          1,
          outputPtr,
        ),
        'Run',
      );
      final outputValue = outputPtr.value;
      final hidden = _readFloatTensor(api, outputValue);
      api.ptr.ref.ReleaseValue
          .asFunction<void Function(ffi.Pointer<bg.OrtValue>)>()(outputValue);
      calloc.free(outputPtr);
      return _meanPoolAndNormalize(hidden, seq, attentionMask);
    } finally {
      api.ptr.ref.ReleaseRunOptions
          .asFunction<void Function(ffi.Pointer<bg.OrtRunOptions>)>()(
        runOptions,
      );
    }
  } finally {
    for (final (value, dataPtr) in tensors) {
      api.ptr.ref.ReleaseValue
          .asFunction<void Function(ffi.Pointer<bg.OrtValue>)>()(value);
      calloc.free(dataPtr);
    }
    calloc.free(inputPtrs);
    for (var i = 0; i < inputNames.length; i++) {
      malloc.free(inputNamePtrs[i]);
    }
    calloc.free(inputNamePtrs);
    malloc.free(outputNamePtrs[0]);
    calloc.free(outputNamePtrs);
  }
}

ffi.Pointer<bg.OrtMemoryInfo> _cpuMemoryInfo(_OrtApi api) {
  final allocatorPtrPtr = calloc<ffi.Pointer<bg.OrtAllocator>>();
  api.check(
    api.ptr.ref.GetAllocatorWithDefaultOptions
        .asFunction<
          bg.OrtStatusPtr Function(ffi.Pointer<ffi.Pointer<bg.OrtAllocator>>)
        >()(allocatorPtrPtr),
    'GetAllocatorWithDefaultOptions',
  );
  final allocator = allocatorPtrPtr.value;
  calloc.free(allocatorPtrPtr);

  // The returned OrtMemoryInfo is owned by the allocator (not ours to free);
  // the ORT environment cleans it up. Mirrors the upstream package's lifetime
  // handling.
  final infoPtrPtr = calloc<ffi.Pointer<bg.OrtMemoryInfo>>();
  api.check(
    api.ptr.ref.AllocatorGetInfo
        .asFunction<
          bg.OrtStatusPtr Function(
            ffi.Pointer<bg.OrtAllocator>,
            ffi.Pointer<ffi.Pointer<bg.OrtMemoryInfo>>,
          )
        >()(allocator, infoPtrPtr),
    'AllocatorGetInfo',
  );
  final info = infoPtrPtr.value;
  calloc.free(infoPtrPtr);
  return info;
}

(ffi.Pointer<bg.OrtValue>, ffi.Pointer<ffi.Int64>) _createInt64Tensor(
  _OrtApi api,
  ffi.Pointer<bg.OrtMemoryInfo> memoryInfo, {
  required Int64List data,
}) {
  // Batch of 1 with the full sequence length.
  final shape = <int>[1, data.length];
  final dataPtr = calloc<ffi.Int64>(data.length);
  dataPtr.asTypedList(data.length).setRange(0, data.length, data);
  final shapePtr = calloc<ffi.Int64>(shape.length);
  shapePtr.asTypedList(shape.length).setRange(0, shape.length, shape);

  final valuePtrPtr = calloc<ffi.Pointer<bg.OrtValue>>();
  api.check(
    api.ptr.ref.CreateTensorWithDataAsOrtValue
        .asFunction<
          bg.OrtStatusPtr Function(
            ffi.Pointer<bg.OrtMemoryInfo>,
            ffi.Pointer<ffi.Void>,
            int,
            ffi.Pointer<ffi.Int64>,
            int,
            int,
            ffi.Pointer<ffi.Pointer<bg.OrtValue>>,
          )
        >()(
      memoryInfo,
      dataPtr.cast(),
      data.length * 8,
      shapePtr,
      shape.length,
      bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
      valuePtrPtr,
    ),
    'CreateTensorWithDataAsOrtValue',
  );
  calloc.free(shapePtr);
  final value = valuePtrPtr.value;
  calloc.free(valuePtrPtr);
  return (value, dataPtr);
}

Float32List _readFloatTensor(_OrtApi api, ffi.Pointer<bg.OrtValue> value) {
  final dataPtrPtr = calloc<ffi.Pointer<ffi.Void>>();
  api.check(
    api.ptr.ref.GetTensorMutableData
        .asFunction<
          bg.OrtStatusPtr Function(
            ffi.Pointer<bg.OrtValue>,
            ffi.Pointer<ffi.Pointer<ffi.Void>>,
          )
        >()(value, dataPtrPtr),
    'GetTensorMutableData',
  );
  final dataPtr = dataPtrPtr.value;
  calloc.free(dataPtrPtr);

  final infoPtrPtr = calloc<ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>>();
  api.check(
    api.ptr.ref.GetTensorTypeAndShape
        .asFunction<
          bg.OrtStatusPtr Function(
            ffi.Pointer<bg.OrtValue>,
            ffi.Pointer<ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>>,
          )
        >()(value, infoPtrPtr),
    'GetTensorTypeAndShape',
  );
  final info = infoPtrPtr.value;
  calloc.free(infoPtrPtr);

  final countPtr = calloc<ffi.Size>();
  api.check(
    api.ptr.ref.GetTensorShapeElementCount
        .asFunction<
          bg.OrtStatusPtr Function(
            ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>,
            ffi.Pointer<ffi.Size>,
          )
        >()(info, countPtr),
    'GetTensorShapeElementCount',
  );
  final count = countPtr.value;
  calloc.free(countPtr);
  api.ptr.ref.ReleaseTensorTypeAndShapeInfo
      .asFunction<void Function(ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>)>()(
    info,
  );

  if (count == 0 || count % _embeddingDimension != 0) {
    throw OnnxRuntimeException(
      'unexpected tensor length $count (expected a multiple of the model '
      'dimension $_embeddingDimension)',
    );
  }
  return dataPtr.cast<ffi.Float>().asTypedList(count);
}

/// Mean pooling over unmasked positions, then L2 normalization — the
/// sentence-transformers `all-MiniLM-L6-v2` pipeline (`1_Pooling` mean-tokens
/// + `2_Normalize`). See `docs/semantic-search.md` §Pooling.
Float32List _meanPoolAndNormalize(
  Float32List hidden,
  int seq,
  Int64List attentionMask,
) {
  final dims = hidden.length ~/ seq;
  final maskSum = attentionMask.fold<int>(0, (sum, value) => sum + value);
  final pooled = Float32List(dims);
  for (var token = 0; token < seq; token++) {
    if (attentionMask[token] == 0) continue;
    final offset = token * dims;
    for (var d = 0; d < dims; d++) {
      pooled[d] += hidden[offset + d];
    }
  }
  for (var d = 0; d < dims; d++) {
    pooled[d] /= maskSum;
  }
  var norm = 0.0;
  for (var d = 0; d < dims; d++) {
    norm += pooled[d] * pooled[d];
  }
  final root = math.sqrt(norm);
  if (root != 0) {
    for (var d = 0; d < dims; d++) {
      pooled[d] /= root;
    }
  }
  return pooled;
}
