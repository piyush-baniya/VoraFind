/// Static product identity used across the application.
///
/// Values here are single source of truth for the VoraFind name and
/// core message. Keep this file dependency-free so it can be imported
/// anywhere, including tests.
abstract final class AppInfo {
  static const String name = 'VoraFind';

  static const String tagline = 'Find anything you\'ve saved on your phone.';

  static const String privacyStatement = 'Your content stays on your device.';

  /// Matches `pubspec.yaml` (`version:`). Single source for the About screen.
  static const String version = '1.0.0';

  /// Matches `pubspec.yaml` (`version+`).
  static const String buildNumber = '1';
}
