import 'package:flutter/material.dart';
import 'package:infravision_camera/infravision_camera.dart';
import 'model_metadata.dart';

/// Single raw candidate detection output from a vision model.
class RawModelDetection {
  const RawModelDetection({
    required this.modelId,
    required this.classId,
    required this.className,
    required this.confidence,
    required this.box,
    required this.timestamp,
    this.colorHex = 0xFF5EF2A6,
  });

  final String modelId;
  final int classId;
  final String className;
  final double confidence;
  final Rect box;
  final int timestamp;
  final int colorHex;

  Offset get center => Offset(
        (box.left + box.right) / 2.0,
        (box.top + box.bottom) / 2.0,
      );
}

/// Abstract common interface for all Level-2 vision models.
abstract class VisionModel {
  ModelMetadata get metadata;
  ModelStatus get status;
  String? get errorMessage;
  bool get isReady;

  /// Load and initialize model weights and runtime resources.
  Future<void> load();

  /// Execute inference on a camera frame and return normalized detections.
  List<RawModelDetection> infer(CameraFrame frame, {double minConfidence = 0.45});

  /// Dispose and release native buffers/interpreters.
  void dispose();
}
