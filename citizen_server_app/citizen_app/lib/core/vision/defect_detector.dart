import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class DefectDetection {
  const DefectDetection({
    required this.classId,
    required this.label,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int classId;
  final String label;
  final double confidence;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => (right - left).clamp(0.0, 1.0);
  double get height => (bottom - top).clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => {
        'classId': classId,
        'label': label,
        'confidence': confidence,
        'left': left,
        'top': top,
        'right': right,
        'bottom': bottom,
      };

  factory DefectDetection.fromJson(Map<String, dynamic> json) =>
      DefectDetection(
        classId: json['classId'] as int? ?? 0,
        label: json['label'] as String? ?? 'pothole',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        left: (json['left'] as num?)?.toDouble() ?? 0.0,
        top: (json['top'] as num?)?.toDouble() ?? 0.0,
        right: (json['right'] as num?)?.toDouble() ?? 0.0,
        bottom: (json['bottom'] as num?)?.toDouble() ?? 0.0,
      );
}

class PhotoDefectAnalysis {
  const PhotoDefectAnalysis({
    required this.detections,
    required this.width,
    required this.height,
    required this.inferenceMs,
    required this.modelVersion,
    this.errorMessage,
  });

  final List<DefectDetection> detections;
  final int width;
  final int height;
  final int inferenceMs;
  final String modelVersion;
  final String? errorMessage;

  bool get hasError =>
      errorMessage != null || modelVersion.endsWith('-fallback');

  Map<String, dynamic> toJson() => {
        'detections': detections.map((d) => d.toJson()).toList(),
        'width': width,
        'height': height,
        'inferenceMs': inferenceMs,
        'modelVersion': modelVersion,
        'errorMessage': errorMessage,
      };

  factory PhotoDefectAnalysis.fromJson(Map<String, dynamic> json) =>
      PhotoDefectAnalysis(
        detections: (json['detections'] as List<dynamic>? ?? [])
            .map((item) => DefectDetection.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList(),
        width: json['width'] as int? ?? 0,
        height: json['height'] as int? ?? 0,
        inferenceMs: json['inferenceMs'] as int? ?? 0,
        modelVersion: json['modelVersion'] as String? ?? 'pothole-v1',
        errorMessage: json['errorMessage'] as String?,
      );
}

/// Runs the verified, offline on-device YOLOv8 pothole detector.
/// Note: The verified model is trained specifically on 'pothole'.
class CitizenDefectDetector {
  CitizenDefectDetector._(this._interpreter, this.inputSize);

  static const assetPath = 'assets/models/pothole_model.tflite';
  static const fallbackAssetPath =
      'assets/models/citizen_damage_yolov8n.tflite';
  static const modelVersion = 'citizen-pothole-yolov8n-float16-v1';

  /// The verified model detects only potholes.
  static const labels = <String>['pothole'];
  static const confidenceThreshold = 0.35;
  static const nmsIouThreshold = 0.45;

  final Interpreter _interpreter;
  final int inputSize;

  static Future<CitizenDefectDetector> load() async {
    String resolvedPath = assetPath;
    try {
      await rootBundle.load(assetPath);
    } catch (_) {
      resolvedPath = fallbackAssetPath;
      await rootBundle.load(fallbackAssetPath);
    }

    final options = InterpreterOptions()..threads = 2;
    final interpreter =
        await Interpreter.fromAsset(resolvedPath, options: options);
    final shape = interpreter.getInputTensor(0).shape;
    if (shape.length != 4 ||
        shape[0] != 1 ||
        shape[3] != 3 ||
        shape[1] != shape[2]) {
      interpreter.close();
      throw StateError('Unsupported model input tensor shape: $shape');
    }
    return CitizenDefectDetector._(interpreter, shape[1]);
  }

  Future<PhotoDefectAnalysis> analyzeFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        throw FileSystemException('Selected photo no longer exists.', path);
      }
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw const FormatException('This image could not be decoded.');
      }
      final original = img.bakeOrientation(decoded);

      final scale =
          math.min(inputSize / original.width, math.min(inputSize / original.height, 1.0));
      final resizedWidth =
          (original.width * scale).round().clamp(1, inputSize).toInt();
      final resizedHeight =
          (original.height * scale).round().clamp(1, inputSize).toInt();
      final padLeft = (inputSize - resizedWidth) ~/ 2;
      final padTop = (inputSize - resizedHeight) ~/ 2;
      final resized = img.copyResize(original,
          width: resizedWidth,
          height: resizedHeight,
          interpolation: img.Interpolation.linear);
      final canvas = img.Image(width: inputSize, height: inputSize);
      img.fill(canvas, color: img.ColorRgb8(114, 114, 114));
      img.compositeImage(canvas, resized, dstX: padLeft, dstY: padTop);

      final inputTensor = _interpreter.getInputTensor(0);
      final isFp16Input = inputTensor.type == TensorType.float16;
      final outputTensor = _interpreter.getOutputTensor(0);
      final isFp16Output = outputTensor.type == TensorType.float16;

      final watch = Stopwatch()..start();

      dynamic inputObj;
      if (isFp16Input) {
        final totalFloats = inputSize * inputSize * 3;
        final bd = ByteData(totalFloats * 2);
        var offset = 0;
        for (var y = 0; y < inputSize; y++) {
          for (var x = 0; x < inputSize; x++) {
            final p = canvas.getPixel(x, y);
            bd.setUint16(offset, _float32ToFloat16(p.r / 255.0), Endian.little);
            bd.setUint16(offset + 2, _float32ToFloat16(p.g / 255.0), Endian.little);
            bd.setUint16(offset + 4, _float32ToFloat16(p.b / 255.0), Endian.little);
            offset += 6;
          }
        }
        inputObj = bd.buffer;
      } else {
        final totalFloats = inputSize * inputSize * 3;
        final f32 = Float32List(totalFloats);
        var offset = 0;
        for (var y = 0; y < inputSize; y++) {
          for (var x = 0; x < inputSize; x++) {
            final p = canvas.getPixel(x, y);
            f32[offset++] = p.r / 255.0;
            f32[offset++] = p.g / 255.0;
            f32[offset++] = p.b / 255.0;
          }
        }
        inputObj = f32.buffer;
      }

      List<double> raw;
      final numOutputFloats = outputTensor.shape.reduce((a, b) => a * b);

      if (isFp16Output) {
        final outBytes = Uint8List(numOutputFloats * 2);
        _interpreter.run(inputObj, outBytes);
        final bd = ByteData.view(outBytes.buffer);
        raw = List<double>.generate(
          numOutputFloats,
          (i) => _float16ToFloat32(bd.getUint16(i * 2, Endian.little)),
          growable: false,
        );
      } else {
        final outF32 = Float32List(numOutputFloats);
        _interpreter.run(inputObj, outF32);
        raw = outF32.toList(growable: false);
      }
      watch.stop();

      final squareDetections = decodeYoloV8(
        values: raw,
        shape: outputTensor.shape,
        labels: labels,
        inputSize: inputSize,
        confidenceThreshold: confidenceThreshold,
        iouThreshold: nmsIouThreshold,
      );

      final detections = squareDetections
          .map((d) {
            double toOriginalX(double x) =>
                ((x * inputSize - padLeft) / resizedWidth).clamp(0.0, 1.0);
            double toOriginalY(double y) =>
                ((y * inputSize - padTop) / resizedHeight).clamp(0.0, 1.0);
            return DefectDetection(
              classId: d.classId,
              label: d.label,
              confidence: d.confidence,
              left: toOriginalX(d.left),
              top: toOriginalY(d.top),
              right: toOriginalX(d.right),
              bottom: toOriginalY(d.bottom),
            );
          })
          .where((d) => d.right > d.left && d.bottom > d.top)
          .toList();

      return PhotoDefectAnalysis(
        detections: detections,
        width: original.width,
        height: original.height,
        inferenceMs: watch.elapsedMilliseconds,
        modelVersion: modelVersion,
      );
    } catch (e, stack) {
      debugPrint('CitizenDefectDetector analyzeFile error: $e\n$stack');
      return PhotoDefectAnalysis(
        detections: const [],
        width: 0,
        height: 0,
        inferenceMs: 0,
        modelVersion: '$modelVersion-fallback',
        errorMessage: 'inference_failed',
      );
    }
  }

  void close() => _interpreter.close();

  /// Decodes raw YOLOv8 output in either [1, 4+C, N] or [1, N, 4+C] layout.
  /// Box coordinates may be normalized or pixels, depending on exporter.
  static List<DefectDetection> decodeYoloV8({
    required List<double> values,
    required List<int> shape,
    List<String> labels = labels,
    required int inputSize,
    double confidenceThreshold = 0.25,
    double iouThreshold = 0.45,
  }) {
    if (shape.length != 3 || shape[0] != 1 || labels.isEmpty) {
      throw FormatException('Unsupported YOLO output tensor shape: $shape');
    }
    final featureCount = labels.length + 4;
    final channelFirst = shape[1] == featureCount;
    final rowMajor = shape[2] == featureCount;
    if (!channelFirst && !rowMajor) {
      throw FormatException('Unsupported YOLO output layout: $shape');
    }
    final anchors = channelFirst ? shape[2] : shape[1];
    if (values.length < shape[1] * shape[2]) {
      throw FormatException(
        'YOLO output is incomplete: ${values.length} values for $shape.',
      );
    }

    double at(int feature, int anchor) => channelFirst
        ? values[feature * anchors + anchor]
        : values[anchor * featureCount + feature];

    final candidates = <DefectDetection>[];
    for (var anchor = 0; anchor < anchors; anchor++) {
      var bestClass = 0;
      var score = at(4, anchor);
      for (var classIndex = 1; classIndex < labels.length; classIndex++) {
        final candidate = at(4 + classIndex, anchor);
        if (candidate > score) {
          score = candidate;
          bestClass = classIndex;
        }
      }
      if (!score.isFinite || score < confidenceThreshold || score > 1.0) {
        continue;
      }
      var cx = at(0, anchor);
      var cy = at(1, anchor);
      var width = at(2, anchor);
      var height = at(3, anchor);
      if (![cx, cy, width, height].every((v) => v.isFinite)) continue;
      if ([cx, cy, width, height].any((v) => v.abs() > 2.0)) {
        cx /= inputSize;
        cy /= inputSize;
        width /= inputSize;
        height /= inputSize;
      }
      final left = (cx - width / 2).clamp(0.0, 1.0);
      final top = (cy - height / 2).clamp(0.0, 1.0);
      final right = (cx + width / 2).clamp(0.0, 1.0);
      final bottom = (cy + height / 2).clamp(0.0, 1.0);
      if (right <= left || bottom <= top) continue;
      candidates.add(DefectDetection(
        classId: bestClass,
        label: labels[bestClass],
        confidence: score.clamp(0.0, 1.0).toDouble(),
        left: left,
        top: top,
        right: right,
        bottom: bottom,
      ));
    }

    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
    final kept = <DefectDetection>[];
    for (final candidate in candidates) {
      if (kept.every((prior) =>
          prior.classId != candidate.classId ||
          _iou(prior, candidate) <= iouThreshold)) {
        kept.add(candidate);
      }
      if (kept.length >= 100) break;
    }
    return kept;
  }

  static double _iou(DefectDetection a, DefectDetection b) {
    final left = math.max(a.left, b.left);
    final top = math.max(a.top, b.top);
    final right = math.min(a.right, b.right);
    final bottom = math.min(a.bottom, b.bottom);
    final intersection =
        math.max(0.0, right - left) * math.max(0.0, bottom - top);
    final areaA = (a.right - a.left) * (a.bottom - a.top);
    final areaB = (b.right - b.left) * (b.bottom - b.top);
    final union = areaA + areaB - intersection;
    return union <= 0 ? 0 : intersection / union;
  }

  static dynamic _zeroBuffer(List<int> shape) {
    if (shape.isEmpty) return 0.0;
    if (shape.length == 1) return Float32List(shape.first);
    return List<dynamic>.generate(
        shape.first, (_) => _zeroBuffer(shape.sublist(1)));
  }

  static List<double> _flatten(dynamic value) {
    final result = <double>[];
    void visit(dynamic node) {
      if (node is num) {
        result.add(node.toDouble());
      } else if (node is List) {
        for (final child in node) {
          visit(child);
        }
      }
    }

    visit(value);
    return result;
  }

  static int _float32ToFloat16(double value) {
    final f32 = Float32List(1)..[0] = value;
    final u32 = f32.buffer.asUint32List()[0];
    final sign = (u32 >> 16) & 0x8000;
    var exp = (u32 >> 23) & 0xFF;
    final mant = u32 & 0x007FFFFF;

    if (exp == 0) return sign;
    if (exp == 255) return sign | 0x7C00;
    exp = exp - 127 + 15;
    if (exp >= 31) return sign | 0x7C00;
    if (exp <= 0) return sign;
    final roundMant = (mant >> 13) + ((mant >> 12) & 1);
    return sign | (exp << 10) | roundMant;
  }

  static double _float16ToFloat32(int value) {
    final sign = (value & 0x8000) << 16;
    final exp = (value & 0x7C00) >> 10;
    final mant = (value & 0x03FF) << 13;

    if (exp == 0) {
      if (mant == 0) return sign == 0 ? 0.0 : -0.0;
      var m = mant;
      var e = 1;
      while ((m & 0x00800000) == 0) {
        m <<= 1;
        e++;
      }
      m &= 0x007FFFFF;
      final u32 = sign | ((127 - 14 - e) << 23) | m;
      final buf = Uint32List(1)..[0] = u32;
      return buf.buffer.asFloat32List()[0];
    }
    if (exp == 31) {
      final u32 = sign | 0x7F800000 | (mant != 0 ? 0x00400000 : 0);
      final buf = Uint32List(1)..[0] = u32;
      return buf.buffer.asFloat32List()[0];
    }
    final u32 = sign | ((exp - 15 + 127) << 23) | mant;
    final buf = Uint32List(1)..[0] = u32;
    return buf.buffer.asFloat32List()[0];
  }
}
