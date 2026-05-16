// ── AppConfig ─────────────────────────────────────────────────────────────

/// Compile-time configuration injected via `--dart-define`.
///
/// Inject the server URL at build time — never hardcode it here:
///
///   flutter run  --dart-define=WIRED_SERVER_URL=https://your-app.onrender.com
///   flutter build linux --dart-define=WIRED_SERVER_URL=https://your-app.onrender.com
///
/// In CI/CD (e.g. GitHub Actions) store the URL as a repository secret and
/// pass it with:
///   --dart-define=WIRED_SERVER_URL=${{ secrets.WIRED_SERVER_URL }}
///
/// If [wiredServerUrl] is empty "The Wired" mode will show
/// SIGNALING_SERVER_UNAVAILABLE — The Wired simply won't work until the
/// server URL is provided.
class AppConfig {
  AppConfig._();

  /// Base URL of the GoHackMe server (no trailing slash).
  ///
  /// Set via `--dart-define=WIRED_SERVER_URL=https://...` at build time.
  /// Empty string means the server URL was not configured.
  static const String wiredServerUrl = String.fromEnvironment(
    'WIRED_SERVER_URL',
    defaultValue: '',
  );

  /// Whether the server URL has been configured for The Wired mode.
  static bool get isWiredConfigured => wiredServerUrl.isNotEmpty;
}
