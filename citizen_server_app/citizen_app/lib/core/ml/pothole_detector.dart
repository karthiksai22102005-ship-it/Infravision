import 'package:flutter/foundation.dart';

import '../vision/defect_detector.dart';

class Detection {
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double confidence;
  final String label;

  const Detection({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.confidence,
    required this.label,
  });

  double get width => x2 - x1;
  double get height => y2 - y1;

  Map<String, dynamic> toJson() => {
        'x1': x1,
        'y1': y1,
        'x2': x2,
        'y2': y2,
        'confidence': confidence,
        'label': label,
      };
}

/// Compatibility adapter used by the capture overlay and report state.
/// The shared vision detector owns model loading, tensor validation,
/// preprocessing, decoding, and NMS so both photo screens use one pipeline.
class PotholeDetector {
  CitizenDefectDetector? _engine;
  bool _initialized = false;

  bool get isReady => _initialized && _engine != null;

  Future<void> init() async {
    if (_initialized) return;
    _engine = await CitizenDefectDetector.load();
    _initialized = true;
    debugPrint('PotholeDetector initialized with the bundled citizen model');
  }

  void dispose() {
    _engine?.close();
    _engine = null;
    _initialized = false;
  }

  Future<List<Detection>> detect(
    String imagePath, {
    double confidenceThreshold = CitizenDefectDetector.confidenceThreshold,
  }) async {
    if (!isReady) await init();
    final engine = _engine;
    if (engine == null) {
      throw StateError('The on-device pothole model did not initialize.');
    }
    final result = await engine.analyzeFile(imagePath);
    if (result.hasError) {
      throw StateError('On-device pothole inference failed.');
    }
    return result.detections
        .where((d) => d.confidence >= confidenceThreshold)
        .map((d) => Detection(
              x1: d.left,
              y1: d.top,
              x2: d.right,
              y2: d.bottom,
              confidence: d.confidence,
              label: d.label,
            ))
        .toList();
  }
}
