import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/providers.dart';
import 'ocr_coordinator.dart';
import 'ocr_detector.dart';

/// The app's on-device OCR bridge. UI code depends on this provider (never on
/// the platform channel directly).
final ocrDetectorProvider = Provider<OcrDetector>((ref) {
  return MethodChannelOcrDetector();
});

/// One coordinator shared by every surface that triggers or observes OCR runs.
final ocrCoordinatorProvider = Provider<OcrCoordinator>((ref) {
  return OcrCoordinator(
    repository: ref.watch(mediaRepositoryProvider),
    detector: ref.watch(ocrDetectorProvider),
  );
});

/// The latest OCR-run snapshot. Stays in [AsyncLoading] until the first run
/// emits, which the UI renders as "no extraction activity" (never an error).
final ocrRunProgressProvider = StreamProvider<OcrRunProgress>((ref) {
  return ref.watch(ocrCoordinatorProvider).progress;
});
