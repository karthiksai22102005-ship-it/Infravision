import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:infravision_camera/infravision_camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../config/app_config.dart';
import 'lightweight_object_detector.dart';

enum ModelStatus {
  loading,
  ready,
  error,
}

/// On-device Model Runner for Object Detection.
///
/// Loads and executes TFLite detection models locally with fallback to
/// high-speed visual feature extraction.
class LocalModelRunner {
  LocalModelRunner();

  Interpreter? _interpreter;
  List<String> _labels = [];
  ModelStatus _status = ModelStatus.loading;
  String? _errorMessage;
  final LightweightObjectDetector _fallbackDetector = LightweightObjectDetector();

  ModelStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isReady => _status == ModelStatus.ready;

  /// Initialize and load the model from assets.
  Future<void> initialize() async {
    _status = ModelStatus.loading;
    _errorMessage = null;

    try {
      // 1. Load class labels
      await _loadLabels();

      // 2. Initialize TFLite interpreter
      try {
        final options = InterpreterOptions()..threads = Platform.numberOfProcessors.clamp(1, 4);
        _interpreter = await Interpreter.fromAsset(
          AppConfig.modelAssetPath,
          options: options,
        );
        _status = ModelStatus.ready;
        debugPrint('TFLite Model loaded successfully: ${AppConfig.modelAssetPath}');
      } catch (e) {
        debugPrint('TFLite Interpreter init notice (using built-in CV engine): $e');
        // Native TFLite library fallback to built-in CV detector
        _status = ModelStatus.ready;
      }
    } catch (e) {
      _status = ModelStatus.error;
      _errorMessage = 'Model initialization failed: $e';
      debugPrint(_errorMessage!);
    }
  }

  Future<void> _loadLabels() async {
    try {
      final labelsData = await rootBundle.loadString(AppConfig.modelLabelsAssetPath);
      _labels = labelsData
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && s != '???')
          .toList();
    } catch (e) {
      try {
        final labelMapData = await rootBundle.loadString('assets/models/labelmap.txt');
        _labels = labelMapData
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && s != '???')
            .toList();
      } catch (_) {
        _labels = const [
          'person', 'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train',
          'truck', 'boat', 'traffic light', 'fire hydrant', 'stop sign', 'bench',
          'bird', 'cat', 'dog', 'horse', 'sheep', 'cow', 'elephant', 'bear',
          'zebra', 'giraffe', 'backpack', 'umbrella', 'handbag', 'tie', 'suitcase',
          'bottle', 'cup', 'fork', 'knife', 'spoon', 'bowl', 'banana', 'apple',
          'sandwich', 'orange', 'chair', 'couch', 'potted plant', 'bed',
          'dining table', 'tv', 'laptop', 'mouse', 'remote', 'keyboard', 'cell phone',
          'book', 'clock', 'vase', 'scissors', 'teddy bear', 'object'
        ];
      }
    }
  }

  /// Run object detection on a camera frame.
  List<VisionDetection> runInference(CameraFrame frame, {double minConfidence = 0.45}) {
    if (_interpreter != null) {
      try {
        return _runTfliteInference(frame, minConfidence);
      } catch (e) {
        debugPrint('TFLite inference fallback: $e');
      }
    }

    // High-performance CV Feature Extraction & Localization
    return _fallbackDetector.detect(frame, minConfidence: minConfidence);
  }

  List<VisionDetection> _runTfliteInference(CameraFrame frame, double minConfidence) {
    if (_interpreter == null || frame.width <= 0 || frame.height <= 0) {
      return const [];
    }

    final inputShape = _interpreter!.getInputTensor(0).shape; // e.g. [1, 300, 300, 3] or [1, 320, 320, 3]
    final inH = inputShape.length >= 3 ? inputShape[1] : 300;
    final inW = inputShape.length >= 3 ? inputShape[2] : 300;

    // Convert raw frame bytes to RGB tensor input
    final input = _preprocessFrame(frame, inW, inH);

    // TFLite MobileNet-SSD standard output tensors:
    // [0]: locations [1, num_boxes, 4]
    // [1]: classes [1, num_boxes]
    // [2]: scores [1, num_boxes]
    // [3]: count [1]
    final outputLocations = List.generate(1, (_) => List.generate(10, (_) => List<double>.filled(4, 0.0)));
    final outputClasses = List.generate(1, (_) => List<double>.filled(10, 0.0));
    final outputScores = List.generate(1, (_) => List<double>.filled(10, 0.0));
    final numDetections = List<double>.filled(1, 0.0);

    final outputs = {
      0: outputLocations,
      1: outputClasses,
      2: outputScores,
      3: numDetections,
    };

    _interpreter!.runForMultipleInputs([input], outputs);

    final count = numDetections[0].toInt().clamp(0, 10);
    final results = <VisionDetection>[];

    for (var i = 0; i < count; i++) {
      final score = outputScores[0][i];
      if (score < minConfidence) continue;

      final classId = outputClasses[0][i].toInt();
      final label = (classId >= 0 && classId < _labels.length) ? _labels[classId] : 'object';

      final loc = outputLocations[0][i];
      final top = loc[0].clamp(0.0, 1.0);
      final left = loc[1].clamp(0.0, 1.0);
      final bottom = loc[2].clamp(0.0, 1.0);
      final right = loc[3].clamp(0.0, 1.0);

      final box = Rect.fromLTRB(left, top, right, bottom);
      final cx = (left + right) / 2.0;
      final cy = (top + bottom) / 2.0;

      final colorHex = _getColorForLabel(label);

      results.add(VisionDetection(
        box: box,
        label: label,
        confidence: score,
        colorHex: colorHex,
        center: Offset(cx, cy),
      ));
    }

    return results;
  }

  List<List<List<List<int>>>> _preprocessFrame(CameraFrame frame, int targetW, int targetH) {
    final image = img.Image.fromBytes(
      width: frame.width,
      height: frame.height,
      bytes: frame.bytes.buffer,
      order: img.ChannelOrder.rgba,
    );

    final resized = img.copyResize(image, width: targetW, height: targetH);
    final input = List.generate(
      1,
      (_) => List.generate(
        targetH,
        (y) => List.generate(
          targetW,
          (x) {
            final pixel = resized.getPixel(x, y);
            return [pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()];
          },
        ),
      ),
    );

    return input;
  }

  int _getColorForLabel(String label) {
    switch (label.toLowerCase()) {
      case 'person':
        return 0xFF00E5A0; // Cyan
      case 'cell phone':
      case 'phone':
      case 'laptop':
      case 'tv':
        return 0xFF00B4D8; // Blue
      case 'bottle':
      case 'cup':
        return 0xFFFFB703; // Amber
      case 'car':
      case 'vehicle':
      case 'truck':
      case 'bus':
        return 0xFFFF5400; // Orange
      case 'backpack':
      case 'handbag':
      case 'bag':
        return 0xFFFF006E; // Pink
      default:
        return 0xFF5EF2A6; // Neon Green
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}
