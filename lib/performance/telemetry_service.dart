import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Performance & Telemetry monitor for on-device AI computer vision inference.
class TelemetryService extends ChangeNotifier {
  TelemetryService._();
  static final TelemetryService instance = TelemetryService._();

  // Sliding window for FPS and Latency calculations
  final Queue<double> _latencySamples = Queue<double>();
  static const int _maxSamples = 30;

  double _currentFps = 0.0;
  double _currentInferenceFps = 0.0;
  double _averageLatencyMs = 0.0;
  int _totalDetectionsProcessed = 0;
  int _totalFramesSampled = 0;
  int _droppedFrames = 0;

  DateTime? _lastFrameTime;
  DateTime? _lastInferenceTime;

  // Getters
  double get currentFps => _currentFps;
  double get currentInferenceFps => _currentInferenceFps;
  double get averageLatencyMs => _averageLatencyMs;
  int get totalDetectionsProcessed => _totalDetectionsProcessed;
  int get totalFramesSampled => _totalFramesSampled;
  int get droppedFrames => _droppedFrames;

  /// Records a new camera frame arrival.
  void recordCameraFrame() {
    _totalFramesSampled++;
    final now = DateTime.now();
    if (_lastFrameTime != null) {
      final deltaMs = now.difference(_lastFrameTime!).inMicroseconds / 1000.0;
      if (deltaMs > 0) {
        final instantFps = 1000.0 / deltaMs;
        _currentFps = (_currentFps * 0.8) + (instantFps * 0.2);
      }
    }
    _lastFrameTime = now;
    notifyListeners();
  }

  /// Records an inference pass completion with execution duration.
  void recordInference({required double latencyMs, int detectionsCount = 0}) {
    _totalDetectionsProcessed += detectionsCount;

    _latencySamples.addLast(latencyMs);
    if (_latencySamples.length > _maxSamples) {
      _latencySamples.removeFirst();
    }

    if (_latencySamples.isNotEmpty) {
      _averageLatencyMs = _latencySamples.reduce((a, b) => a + b) / _latencySamples.length;
    }

    final now = DateTime.now();
    if (_lastInferenceTime != null) {
      final deltaMs = now.difference(_lastInferenceTime!).inMicroseconds / 1000.0;
      if (deltaMs > 0) {
        final instantInferenceFps = 1000.0 / deltaMs;
        _currentInferenceFps = (_currentInferenceFps * 0.8) + (instantInferenceFps * 0.2);
      }
    }
    _lastInferenceTime = now;

    notifyListeners();
  }

  /// Records a dropped frame when inference pipeline is busy.
  void recordDroppedFrame() {
    _droppedFrames++;
    notifyListeners();
  }

  /// Resets session telemetry counters.
  void reset() {
    _latencySamples.clear();
    _currentFps = 0.0;
    _currentInferenceFps = 0.0;
    _averageLatencyMs = 0.0;
    _totalDetectionsProcessed = 0;
    _totalFramesSampled = 0;
    _droppedFrames = 0;
    _lastFrameTime = null;
    _lastInferenceTime = null;
    notifyListeners();
  }
}
