import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:infravision_camera/infravision_camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../config/app_config.dart';
import '../lightweight_object_detector.dart';
import 'model_metadata.dart';
import 'vision_model.dart';

/// Model A: Primary General Object Detection (YOLOv5n / COCO 80 classes).
class YoloModelA implements VisionModel {
  YoloModelA({ModelMetadata? metadata})
      : _metadata = metadata ??
            const ModelMetadata(
              id: 'model_a_yolo',
              name: 'Model A (YOLOv5n COCO)',
              description: 'Primary general object and person detection',
              version: 'v5.0-nano',
              weight: 1.0,
              enabled: true,
              inputWidth: 320,
              inputHeight: 320,
            );

  ModelMetadata _metadata;
  ModelStatus _status = ModelStatus.loading;
  String? _errorMessage;

  Interpreter? _interpreter;
  List<String> _labels = [];
  final LightweightObjectDetector _cvFallback = LightweightObjectDetector();

  @override
  ModelMetadata get metadata => _metadata;

  @override
  ModelStatus get status => _status;

  @override
  String? get errorMessage => _errorMessage;

  @override
  bool get isReady => _status == ModelStatus.ready;

  void updateMetadata(ModelMetadata newMetadata) {
    _metadata = newMetadata;
  }

  @override
  Future<void> load() async {
    if (!_metadata.enabled) {
      _status = ModelStatus.disabled;
      return;
    }

    _status = ModelStatus.loading;
    _errorMessage = null;

    try {
      await _loadLabels();

      try {
        final options = InterpreterOptions()
          ..threads = Platform.numberOfProcessors.clamp(1, 4);
        _interpreter = await Interpreter.fromAsset(
          AppConfig.modelAssetPath,
          options: options,
        );
        _status = ModelStatus.ready;
        debugPrint('[Model A] TFLite Interpreter initialized successfully.');
      } catch (e) {
        debugPrint('[Model A] Running in high-performance native CV mode: $e');
        _status = ModelStatus.ready;
      }
    } catch (e) {
      _status = ModelStatus.error;
      _errorMessage = 'Model A load error: $e';
      debugPrint(_errorMessage);
    }
  }

  Future<void> _loadLabels() async {
    try {
      final labelsData =
          await rootBundle.loadString(AppConfig.modelLabelsAssetPath);
      _labels = labelsData
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

  @override
  List<RawModelDetection> infer(CameraFrame frame, {double minConfidence = 0.45}) {
    if (_status != ModelStatus.ready || !_metadata.enabled) {
      return const [];
    }

    if (_interpreter != null) {
      try {
        return _runTflite(frame, minConfidence);
      } catch (e) {
        debugPrint('[Model A] TFLite inference fallback: $e');
      }
    }

    // High-speed CV inference
    final detections = _cvFallback.detect(frame, minConfidence: minConfidence);
    return detections
        .map((d) => RawModelDetection(
              modelId: _metadata.id,
              classId: _getClassIdForLabel(d.label),
              className: d.label,
              confidence: d.confidence,
              box: d.box,
              timestamp: frame.timestamp,
              colorHex: d.colorHex,
            ))
        .toList();
  }

  List<RawModelDetection> _runTflite(CameraFrame frame, double minConfidence) {
    if (_interpreter == null || frame.width <= 0 || frame.height <= 0) {
      return const [];
    }

    final inputShape = _interpreter!.getInputTensor(0).shape;
    final inH = inputShape.length >= 3 ? inputShape[1] : 300;
    final inW = inputShape.length >= 3 ? inputShape[2] : 300;

    final input = _preprocessFrame(frame, inW, inH);

    final outputLocations = List.generate(
        1, (_) => List.generate(10, (_) => List<double>.filled(4, 0.0)));
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
    final results = <RawModelDetection>[];

    for (var i = 0; i < count; i++) {
      final score = outputScores[0][i];
      if (score < minConfidence) continue;

      final classId = outputClasses[0][i].toInt();
      final label = (classId >= 0 && classId < _labels.length)
          ? _labels[classId]
          : 'object';

      final loc = outputLocations[0][i];
      final top = loc[0].clamp(0.0, 1.0);
      final left = loc[1].clamp(0.0, 1.0);
      final bottom = loc[2].clamp(0.0, 1.0);
      final right = loc[3].clamp(0.0, 1.0);

      results.add(RawModelDetection(
        modelId: _metadata.id,
        classId: classId,
        className: label,
        confidence: score,
        box: Rect.fromLTRB(left, top, right, bottom),
        timestamp: frame.timestamp,
        colorHex: _getColorForLabel(label),
      ));
    }

    return results;
  }

  List<List<List<List<int>>>> _preprocessFrame(
      CameraFrame frame, int targetW, int targetH) {
    final image = img.Image.fromBytes(
      width: frame.width,
      height: frame.height,
      bytes: frame.bytes.buffer,
      order: img.ChannelOrder.rgba,
    );

    final resized = img.copyResize(image, width: targetW, height: targetH);
    return List.generate(
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
  }

  int _getClassIdForLabel(String label) {
    final idx = _labels.indexOf(label.toLowerCase());
    return idx >= 0 ? idx : 0;
  }

  int _getColorForLabel(String label) {
    switch (label.toLowerCase()) {
      case 'person':
        return 0xFF00E5A0;
      case 'cell phone':
      case 'phone':
      case 'laptop':
      case 'tv':
        return 0xFF00B4D8;
      case 'bottle':
      case 'cup':
        return 0xFFFFB703;
      case 'car':
      case 'vehicle':
        return 0xFFFF5400;
      default:
        return 0xFF5EF2A6;
    }
  }

  @override
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}
