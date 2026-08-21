/// Central, single-source-of-truth configuration for InfraVision Level 1.
///
/// Nothing here is infrastructure-specific. This is purely the reusable
/// computer-vision foundation configuration. Future levels (GPS, infra
/// defect model, backend) will add their own config files instead of
/// bloating this one.
class AppConfig {
  AppConfig._();

  // ---------------------------------------------------------------------
  // Model identity — swappable later without touching camera/UI/tracking.
  // ---------------------------------------------------------------------
  static const String modelAssetPath = 'assets/models/yolov5n.tflite';
  static const String modelLabelsAssetPath = 'assets/models/labels.txt';
  static const String modelName = 'YOLOv5n (COCO, 80 classes)';
  static const int modelInputSize = 320; // square input, e.g. 320x320

  // ---------------------------------------------------------------------
  // Inference throttling — camera FPS and AI FPS are independent.
  // ---------------------------------------------------------------------
  static const List<int> selectableInferenceFps = [3, 5, 8, 10, 15];
  static const int defaultInferenceFps = 8;

  // ---------------------------------------------------------------------
  // FPS measurement — sliding window for actual measured FPS.
  // ---------------------------------------------------------------------
  static const int fpsMeasurementWindowUs = 1000000; // 1 second in microseconds

  // ---------------------------------------------------------------------
  // Detection thresholds
  // ---------------------------------------------------------------------
  static const double defaultConfidenceThreshold = 0.45;
  static const double minConfidenceThreshold = 0.20;
  static const double maxConfidenceThreshold = 0.90;
  static const double iouThresholdNms = 0.45;

  // ---------------------------------------------------------------------
  // Tracking
  // ---------------------------------------------------------------------
  static const double trackingIouMatchThreshold = 0.3;
  static const int trackingMaxMissedFrames = 5; // frames before ID retires
  static const bool defaultTrackingEnabled = true;

  // ---------------------------------------------------------------------
  // Settings persistence keys (SharedPreferences)
  // ---------------------------------------------------------------------
  static const String prefKeyInferenceFps = 'infravision.inferenceFps';
  static const String prefKeyConfidenceThreshold =
      'infravision.confidenceThreshold';
  static const String prefKeyTrackingEnabled = 'infravision.trackingEnabled';
  static const String prefKeyAiEnabled = 'infravision.aiEnabled';
  static const String prefKeyCameraLensIndex = 'infravision.cameraLensIndex';
}

