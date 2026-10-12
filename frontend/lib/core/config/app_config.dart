class AppConfig {
  /// Base API URL for backend communication.
  /// Can be overridden at runtime or compile-time via --dart-define.
  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api/v1',
  );

  static String baseUrl = defaultBaseUrl;

  static const String appName = 'Texora AI';
  static const String appTagline = 'Autonomous Textile Factory Operations';
  static const String appVersion = '1.0.0 (Phase 1 Foundation)';
}
