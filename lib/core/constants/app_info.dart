/// Static product identity used across the application.
///
/// Values here are single source of truth for the VoraFind name and
/// core message. Keep this file dependency-free so it can be imported
/// anywhere, including tests.
abstract final class AppInfo {
  static const String name = 'VoraFind';

  static const String tagline = 'Find anything you\'ve saved on your phone.';

  static const String privacyStatement = 'Your content stays on your device.';
}
