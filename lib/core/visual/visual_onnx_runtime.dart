import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../semantic/neural_embedding_runtime.dart'
    show OnnxRuntime, OnnxRuntimeException;

// Vision-classifier ONNX session runner.
//
// VoraFind intentionally imports only the generated pure-`dart:ffi` bindings,
// never the package-level `onnxruntime.dart` facade (see the identical note in
// `neural_embedding_runtime.dart` — this file mirrors that design).
// ignore: implementation_imports
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart'
    as bg;

const int _ortApiVersion = 14;

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

/// A loaded, CPU-only ONNX Runtime session for a single float-input,
/// float-output image model (the bundled MobileNetV2 — one batch, one image).
/// Serves both the classifier head ([classify], 1000 logits) and the sliced
/// feature embedding ([embed], 1280 values), which are the same graph forward
/// pass minus the classification head.
///
/// Mirrors the BERT runtime's ownership pattern: environment and session live
/// on the owning (main) isolate, while each [classify]/[embed] run happens in
/// a fresh worker isolate that reopens the library, re-negotiates the API
/// pointer, and reuses this session's pointer address. Only the fixed-length
/// float output (or one error) crosses the isolate boundary.
class VisionOnnxSession {
  VisionOnnxSession._(
    this._api,
    this._env,
    this._session,
    this._inputName,
    this._outputName,
  );

  static VisionOnnxSession create({
    required Uint8List modelBytes,
    int intraOpNumThreads = 2,
  }) {
    final api = _OrtApi();

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
          'vorafind-vision'.toNativeUtf8().cast<ffi.Char>(),
          envPtrPtr,
        );
    api.check(envStatus, 'CreateEnv');
    final env = envPtrPtr.value;
    calloc.free(envPtrPtr);

    final optionsPtrPtr = calloc<ffi.Pointer<bg.OrtSessionOptions>>();
    final optionsStatus = api.ptr.ref.CreateSessionOptions
        .asFunction<
          bg.OrtStatusPtr Function(
            ffi.Pointer<ffi.Pointer<bg.OrtSessionOptions>>,
          )
        >()(optionsPtrPtr);
    api.check(optionsStatus, 'CreateSessionOptions');
    final options = optionsPtrPtr.value;
    calloc.free(optionsPtrPtr);
    api.check(
      api.ptr.ref.SetIntraOpNumThreads
          .asFunction<
            bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>, int)
          >()(options, intraOpNumThreads),
      'SetIntraOpNumThreads',
    );
    api.check(
      api.ptr.ref.SetSessionGraphOptimizationLevel
          .asFunction<
            bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>, int)
          >()(options, bg.GraphOptimizationLevel.ORT_ENABLE_ALL),
      'SetSessionGraphOptimizationLevel',
    );

    final sessionPtrPtr = calloc<ffi.Pointer<bg.OrtSession>>();
    final bytes = calloc<ffi.Uint8>(modelBytes.length);
    bytes
        .asTypedList(modelBytes.length)
        .setRange(0, modelBytes.length, modelBytes);
    final status = api.ptr.ref.CreateSessionFromArray
        .asFunction<
          bg.OrtStatusPtr Function(
            ffi.Pointer<bg.OrtEnv>,
            ffi.Pointer<ffi.Void>,
            int,
            ffi.Pointer<bg.OrtSessionOptions>,
            ffi.Pointer<ffi.Pointer<bg.OrtSession>>,
          )
        >()(env, bytes.cast(), modelBytes.length, options, sessionPtrPtr);
    calloc.free(bytes);
    api.check(status, 'CreateSessionFromArray');
    final session = sessionPtrPtr.value;
    calloc.free(sessionPtrPtr);
    api.ptr.ref.ReleaseSessionOptions
        .asFunction<void Function(ffi.Pointer<bg.OrtSessionOptions>)>()(
      options,
    );

    return VisionOnnxSession._(
      api,
      env,
      session,
      _readTensorNames(api, session, output: false).first,
      _readTensorNames(api, session, output: true).first,
    );
  }

  final _OrtApi _api;
  final ffi.Pointer<bg.OrtEnv> _env;
  final ffi.Pointer<bg.OrtSession> _session;
  final String _inputName;
  final String _outputName;

  /// Runs the classifier on one preprocessed image tensor (already resized and
  /// normalized, float `CHW` in BGR order) and returns the 1000 logits.
  ///
  /// Runs in a fresh worker isolate (matches the BERT runtime's contract: never
  /// block the main isolate during indexing).
  Future<Float32List> classify(Float32List imageNchw) {
    final sessionAddress = _session.address;
    final inputName = _inputName;
    final outputName = _outputName;
    return Isolate.run(
      () => _classifyIsolate(
        sessionAddress: sessionAddress,
        inputName: inputName,
        outputName: outputName,
        imageNchw: imageNchw,
        expectedCount: 1000,
      ),
    );
  }

  /// Runs the model on one preprocessed image tensor and returns the raw
  /// feature embedding of [dimension] values — the sliced MobileNetV2
  /// GlobalAveragePool output ahead of the 1000-class classification head
  /// (docs `similar-image-search.md` §Selected model).
  ///
  /// Same worker-isolate and threading contract as [classify]; only the
  /// expected output length differs.
  Future<Float32List> embed(Float32List imageNchw, {required int dimension}) {
    final sessionAddress = _session.address;
    final inputName = _inputName;
    final outputName = _outputName;
    return Isolate.run(
      () => _classifyIsolate(
        sessionAddress: sessionAddress,
        inputName: inputName,
        outputName: outputName,
        imageNchw: imageNchw,
        expectedCount: dimension,
      ),
    );
  }

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
// Worker-isolate classification path. Serialization is limited to sendable
// values (the session pointer address and the already-preprocessed floats);
// the worker reopens the library and re-negotiates the API pointer locally.
// ---------------------------------------------------------------------------

Float32List _classifyIsolate({
  required int sessionAddress,
  required String inputName,
  required String outputName,
  required Float32List imageNchw,
  required int expectedCount,
}) {
  final api = _OrtApi();
  final session = ffi.Pointer<bg.OrtSession>.fromAddress(sessionAddress);

  final inputNamePtrs = calloc<ffi.Pointer<ffi.Char>>(1);
  inputNamePtrs[0] = inputName.toNativeUtf8().cast<ffi.Char>();
  final outputNamePtrs = calloc<ffi.Pointer<ffi.Char>>(1);
  outputNamePtrs[0] = outputName.toNativeUtf8().cast<ffi.Char>();

  final memoryInfo = _cpuMemoryInfo(api);
  // `ffi.nullptr` variants differ in nullability across ffi versions; keep
  // local variables explicitly typed so record inference cannot collapse them
  // into `Pointer<Never>`.
  ffi.Pointer<bg.OrtValue> tensorValue = ffi.Pointer<bg.OrtValue>.fromAddress(
    0,
  );
  ffi.Pointer<ffi.Float> tensorData = ffi.Pointer<ffi.Float>.fromAddress(0);
  var hasTensor = false;
  try {
    final created = _createFloatTensor(api, memoryInfo, data: imageNchw);
    tensorValue = created.$1;
    tensorData = created.$2;
    hasTensor = true;
    final inputPtrs = calloc<ffi.Pointer<bg.OrtValue>>(1);
    inputPtrs[0] = tensorValue;

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
          1,
          outputNamePtrs,
          1,
          outputPtr,
        ),
        'Run',
      );
      final outputValue = outputPtr.value;
      final logits = _readFloatTensor(
        api,
        outputValue,
        expectedCount: expectedCount,
      );
      api.ptr.ref.ReleaseValue
          .asFunction<void Function(ffi.Pointer<bg.OrtValue>)>()(outputValue);
      calloc.free(outputPtr);
      return logits;
    } finally {
      api.ptr.ref.ReleaseRunOptions
          .asFunction<void Function(ffi.Pointer<bg.OrtRunOptions>)>()(
        runOptions,
      );
    }
  } finally {
    if (hasTensor) {
      api.ptr.ref.ReleaseValue
          .asFunction<void Function(ffi.Pointer<bg.OrtValue>)>()(tensorValue);
      calloc.free(tensorData);
    }
    calloc.free(inputNamePtrs[0]);
    calloc.free(inputNamePtrs);
    calloc.free(outputNamePtrs[0]);
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

(ffi.Pointer<bg.OrtValue>, ffi.Pointer<ffi.Float>) _createFloatTensor(
  _OrtApi api,
  ffi.Pointer<bg.OrtMemoryInfo> memoryInfo, {
  required Float32List data,
}) {
  // Batch of 1, NCHW layout as the bundled model expects: [1, 3, 224, 224].
  const shape = <int>[1, 3, 224, 224];
  final dataPtr = calloc<ffi.Float>(data.length);
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
      data.length * 4,
      shapePtr,
      shape.length,
      bg.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
      valuePtrPtr,
    ),
    'CreateTensorWithDataAsOrtValue',
  );
  calloc.free(shapePtr);
  final value = valuePtrPtr.value;
  calloc.free(valuePtrPtr);
  return (value, dataPtr);
}

Float32List _readFloatTensor(
  _OrtApi api,
  ffi.Pointer<bg.OrtValue> value, {
  required int expectedCount,
}) {
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

  if (count != expectedCount) {
    throw OnnxRuntimeException(
      'unexpected tensor length $count (expected $expectedCount values)',
    );
  }
  return dataPtr.cast<ffi.Float>().asTypedList(count);
}
