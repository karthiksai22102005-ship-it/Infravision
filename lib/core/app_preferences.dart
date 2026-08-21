import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  AppPreferences._();
  static final AppPreferences instance = AppPreferences._();

  static const String _keyConfidence = 'pref_confidence';
  static const String _keyTargetFps = 'pref_target_fps';
  static const String _keyOverlay = 'pref_overlay_enabled';
  static const String _keyTracking = 'pref_tracking_enabled';
  static const String _keyWorkspace = 'pref_workspace_index';
  static const String _keyCameraDevice = 'pref_camera_device';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  double get confidenceThreshold =>
      _prefs?.getDouble(_keyConfidence) ?? 0.45;

  Future<void> setConfidenceThreshold(double val) async {
    await _prefs?.setDouble(_keyConfidence, val);
  }

  int get targetInferenceFps =>
      _prefs?.getInt(_keyTargetFps) ?? 8;

  Future<void> setTargetInferenceFps(int val) async {
    await _prefs?.setInt(_keyTargetFps, val);
  }

  bool get overlayEnabled =>
      _prefs?.getBool(_keyOverlay) ?? false;

  Future<void> setOverlayEnabled(bool val) async {
    await _prefs?.setBool(_keyOverlay, val);
  }

  bool get trackingEnabled =>
      _prefs?.getBool(_keyTracking) ?? true;

  Future<void> setTrackingEnabled(bool val) async {
    await _prefs?.setBool(_keyTracking, val);
  }

  int get workspaceIndex =>
      _prefs?.getInt(_keyWorkspace) ?? 0;

  Future<void> setWorkspaceIndex(int val) async {
    await _prefs?.setInt(_keyWorkspace, val);
  }

  String? get selectedCameraDevice =>
      _prefs?.getString(_keyCameraDevice);

  Future<void> setSelectedCameraDevice(String id) async {
    await _prefs?.setString(_keyCameraDevice, id);
  }
}
