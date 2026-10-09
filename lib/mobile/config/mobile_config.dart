/// Central configuration for the Android InfraVision Observation Portal.
///
/// IMPORTANT: no production API endpoint, credential or secret is hard-coded
/// here. The backend base URL is supplied at build time with
/// `--dart-define=INFRAVISION_API_BASE_URL=https://...` or configured at
/// runtime in Settings (stored locally, never committed).
class MobileConfig {
  MobileConfig._();

  // ---------------------------------------------------------------------------
  // Build environment (§81) — never accidentally point release at dev APIs.
  // ---------------------------------------------------------------------------
  static const String buildEnvironment =
      String.fromEnvironment('INFRAVISION_ENV', defaultValue: 'development');

  static bool get isProduction => buildEnvironment == 'production';
  static bool get isStaging => buildEnvironment == 'staging';

  /// Optional compile-time backend base URL. Empty means "backend not
  /// configured": the portal then works fully offline and stores reports
  /// locally, and the Sync Center says so honestly.
  static const String compileTimeApiBaseUrl =
      String.fromEnvironment('INFRAVISION_API_BASE_URL', defaultValue: '');

  /// API version header/prefix used by every request (§69/70).
  static const String apiPathPrefix = '/api/v1';
  static const int apiVersion = 1;

  // ---------------------------------------------------------------------------
  // Networking
  // ---------------------------------------------------------------------------
  static const Duration connectTimeout = Duration(seconds: 12);
  static const Duration readTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(minutes: 5);
  static const Duration reachabilityTimeout = Duration(seconds: 4);

  /// Exponential backoff bounds for the sync engine (§30).
  static const Duration retryBaseDelay = Duration(seconds: 20);
  static const Duration retryMaxDelay = Duration(minutes: 30);
  static const int maxSyncAttempts = 6;

  /// Bounded upload concurrency (§32): photos are uploaded a few at a time,
  /// videos always after report metadata + essential photos.
  static const int maxConcurrentUploads = 2;
  static const int maxConcurrentVideoUploads = 1;

  // ---------------------------------------------------------------------------
  // Evidence limits (§16/17)
  // ---------------------------------------------------------------------------
  static const int maxPhotoBytes = 14 * 1024 * 1024;
  static const int maxVideoBytes = 220 * 1024 * 1024;
  static const int maxVideoDurationSeconds = 45;
  static const int maxEvidencePerObservation = 8;
  static const Set<String> allowedImageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
  };
  static const Set<String> allowedVideoExtensions = {
    'mp4',
    'mov',
    'mkv',
    '3gp',
  };

  // ---------------------------------------------------------------------------
  // Location (§19-24). Thresholds classify what the device actually reported.
  // ---------------------------------------------------------------------------
  static const double accuracyExcellentMeters = 5.0;
  static const double accuracyGoodMeters = 15.0;
  static const double accuracyModerateMeters = 30.0;

  /// Total time budget for a fresh high-accuracy acquisition before the UI
  /// offers "Try again" / "Continue with current location".
  static const Duration locationAcquisitionTimeout = Duration(seconds: 18);

  /// Maximum time we keep a live GPS stream open on the capture screen.
  static const Duration locationStreamMaxDuration = Duration(minutes: 4);

  // ---------------------------------------------------------------------------
  // Quality gate (§18)
  // ---------------------------------------------------------------------------
  static const double minBlurVariance = 45.0;
  static const double minBrightness = 32.0;
  static const double maxBrightness = 232.0;
  static const int minImageWidth = 480;
  static const int minImageHeight = 360;

  // ---------------------------------------------------------------------------
  // Duplicate protection (§33/40)
  // ---------------------------------------------------------------------------
  static const double duplicateRadiusMeters = 25.0;
  static const Duration duplicateWindow = Duration(days: 7);
  static const int duplicateHashDistance = 12;

  // ---------------------------------------------------------------------------
  // Storage caps (§60)
  // ---------------------------------------------------------------------------
  static const int thumbnailMaxDimension = 320;
  static const int aiDerivativeMaxDimension = 640;
  static const int uploadDerivativeMaxDimension = 1920;
  static const int cacheBudgetBytes = 120 * 1024 * 1024;

  /// Fraction of device storage that must remain free before the portal
  /// warns the user and stops writing regenerable derivatives.
  static const double lowStorageFreeRatio = 0.05;

  // ---------------------------------------------------------------------------
  // Startup / UI
  // ---------------------------------------------------------------------------
  static const Duration splashMinimum = Duration(milliseconds: 900);
  static const Duration defaultPageSize = Duration.zero; // placeholder-free
  static const int reportsPageSize = 20;
  static const int nearbyMaxMarkers = 300;

  /// Current application version values are provided by the Android build
  /// (versionName/versionCode) and mirrored here for the About screen.
  static const String appVersionName = String.fromEnvironment(
    'INFRAVISION_VERSION_NAME',
    defaultValue: '1.3.0',
  );
  static const int appVersionCode = int.fromEnvironment(
    'INFRAVISION_VERSION_CODE',
    defaultValue: 4,
  );
}
