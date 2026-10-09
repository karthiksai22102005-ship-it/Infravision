import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/app_logger.dart';
import '../models/analysis.dart';

/// Label -> infrastructure category mapping, used only when a model actually
/// contains such classes (the bundled COCO detector does not, §35/§37).
const Map<String, String> infrastructureLabelToCategory = <String, String>{
  'pothole': 'pothole',
  'potholes': 'pothole',
  'road crack': 'road_crack',
  'crack': 'road_crack',
  'cracks': 'road_crack',
  'damaged road surface': 'damaged_road_surface',
  'road damage': 'damaged_road_surface',
  'damaged road sign': 'damaged_road_sign',
  'road sign': 'damaged_road_sign',
  'traffic sign': 'damaged_road_sign',
  'damaged road marking': 'damaged_road_marking',
  'road marking': 'damaged_road_marking',
  'lane marking': 'damaged_road_marking',
  'drainage': 'drainage_issue',
  'drain': 'drainage_issue',
  'gully': 'drainage_issue',
  'sidewalk': 'sidewalk_damage',
  'pavement': 'sidewalk_damage',
  'structural defect': 'structural_defect',
  'concrete crack': 'structural_defect',
  'bridge damage': 'structural_defect',
  'obstruction': 'obstruction',
  'debris': 'obstruction',
  'encroachment': 'obstruction',
};

/// On-device AI analysis (§35, §36, §37).
///
/// Rules enforced:
/// - inference runs in a background isolate so camera/UI never stalls;
/// - results are only reported when the model really produced them;
/// - when the bundled model cannot classify infrastructure defects the result
///   says so instead of inventing a prediction;
/// - the model file is fingerprinted before use (§78).
class AnalysisService {
  AnalysisService({
    this.modelAssetPath = 'assets/models/yolov5n.tflite',
    this.labelsAssetPath = 'assets/models/labels.txt',
  });

  final String modelAssetPath;
  final String labelsAssetPath;

  String? _modelVersion;
  bool _prepared = false;
  String? _problem;
  int _lastInferenceMs = 0;

  bool get isPrepared => _prepared;
  String? get problem => _problem;
  String? get modelVersion => _modelVersion;
  int get lastInferenceMs => _lastInferenceMs;

  /// Copies the bundled model into app storage and fingerprints it.
  /// Returns true when a usable model file is available.
  Future<bool> prepare({required Directory workDirectory}) async {
    if (_prepared) return true;
    try {
      final File modelFile = await _ensureAsset(
        assetPath: modelAssetPath,
        workDirectory: workDirectory,
        fileName: 'defect_model.tflite',
      );
      final File labelsFile = await _ensureAsset(
        assetPath: labelsAssetPath,
        workDirectory: workDirectory,
        fileName: 'defect_labels.txt',
      );

      if (!modelFile.existsSync() || await modelFile.length() < 1024) {
        _problem = 'Bundled model file is missing or truncated.';
        return false;
      }

      final String fingerprint =
          '${await _fingerprint(modelFile)} / ${await _fingerprint(labelsFile)}';
      _modelVersion = fingerprint;
      _prepared = true;
      _problem = null;
      AppLog.i('AI', 'Model ready: $fingerprint');
      return true;
    } catch (e) {
      AppLog.e('AI', 'Model preparation failed: $e');
      _problem = 'Model could not be prepared on this device.';
      return false;
    }
  }

  Future<File> _ensureAsset({
    required String assetPath,
    required Directory workDirectory,
    required String fileName,
  }) async {
    final File target = File('${workDirectory.path}/models/$fileName');
    if (await target.exists() && await target.length() > 0) {
      return target;
    }
    await Directory('${workDirectory.path}/models').create(recursive: true);
    final ByteData data = await rootBundle.load(assetPath);
    await target.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return target;
  }

  Future<String> _fingerprint(File file) async {
    final String name = file.path.split(Platform.pathSeparator).last;
    try {
      final Digest digest = await sha256.bind(file.openRead()).first;
      return '$name#${digest.toString().substring(0, 12)}';
    } catch (_) {
      return '$name#${await file.length()}';
    }
  }
  /// Runs the full analysis for one still image (§36: one-shot, not per-frame).
  Future<AnalysisResult> analyze({
    required String imagePath,
    required Directory workDirectory,
    VisualScreening screening = VisualScreening.empty,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final bool ready = await prepare(workDirectory: workDirectory);
    if (!ready) {
      return AnalysisResult.unavailable(
        _problem ?? 'AI analysis unavailable.',
        screening,
      );
    }

    final File modelFile =
        File('${workDirectory.path}/models/defect_model.tflite');
    final File labelsFile =
        File('${workDirectory.path}/models/defect_labels.txt');
    if (!await modelFile.exists() || !await labelsFile.exists()) {
      return AnalysisResult.unavailable(
        'AI analysis unavailable — model files are missing.',
        screening,
      );
    }

    final Stopwatch watch = Stopwatch()..start();
    try {
      final Map<String, Object?> response = await compute(
        runModelJob,
        <String, Object?>{
          'modelPath': modelFile.path,
          'labelsPath': labelsFile.path,
          'imagePath': imagePath,
        },
      ).timeout(timeout);
      watch.stop();
      _lastInferenceMs = watch.elapsedMilliseconds;

      if (response['ok'] != true) {
        return AnalysisResult(
          availability: AnalysisAvailability.failed,
          screening: screening,
          objects: const <ModelObject>[],
          modelVersion: _modelVersion,
          failureReason: '${response['error'] ?? 'AI analysis failed.'}',
          inferenceMs: _lastInferenceMs,
        );
      }

      final List<ModelObject> objects = <ModelObject>[];
      final List<Object?> rawObjects =
          (response['objects'] as List<Object?>?) ?? const <Object?>[];
      for (final Object? raw in rawObjects) {
        if (raw is! Map) continue;
        objects.add(
          ModelObject(
            label: '${raw['label']}',
            confidence: (raw['score'] as num).toDouble(),
            left: (raw['left'] as num).toDouble(),
            top: (raw['top'] as num).toDouble(),
            right: (raw['right'] as num).toDouble(),
            bottom: (raw['bottom'] as num).toDouble(),
          ),
        );
      }

      final String? suggested = _infrastructureCategoryOf(objects);
      final bool headSupported = response['headSupported'] == true;

      if (suggested != null) {
        final ModelObject match = objects.firstWhere(
          (ModelObject o) =>
              infrastructureLabelToCategory[o.label.toLowerCase().trim()] ==
              suggested,
        );
        return AnalysisResult(
          availability: AnalysisAvailability.modelPrediction,
          screening: screening,
          objects: objects,
          modelVersion: _modelVersion,
          inferenceMs: _lastInferenceMs,
          suggestedCategoryId: suggested,
          confidence: match.confidence,
          rawSummary: _summaryOf(objects),
        );
      }

      return AnalysisResult(
        availability: headSupported
            ? AnalysisAvailability.modelWithoutInfrastructureClasses
            : AnalysisAvailability.modelUnavailable,
        screening: screening,
        objects: objects,
        modelVersion: _modelVersion,
        inferenceMs: _lastInferenceMs,
        failureReason: headSupported
            ? 'The bundled model contains no infrastructure defect classes, '
                'so no defect category can be predicted on this device. '
                'Select the category manually.'
            : 'The bundled model output format is not supported by this app '
                'version.',
        rawSummary: _summaryOf(objects),
      );
    } on TimeoutException {
      return AnalysisResult.unavailable('AI analysis timed out.', screening);
    } catch (e) {
      AppLog.e('AI', 'Inference failed: $e');
      return AnalysisResult.unavailable('AI analysis failed.', screening);
    }
  }

  String? _infrastructureCategoryOf(List<ModelObject> objects) {
    for (final ModelObject object in objects) {
      final String? category =
          infrastructureLabelToCategory[object.label.toLowerCase().trim()];
      if (category != null && object.confidence >= 0.25) return category;
    }
    return null;
  }

  String _summaryOf(List<ModelObject> objects) {
    if (objects.isEmpty) return 'No objects detected.';
    final List<ModelObject> sorted = List<ModelObject>.from(objects)
      ..sort(
        (ModelObject a, ModelObject b) => b.confidence.compareTo(a.confidence),
      );
    return sorted
        .take(3)
        .map((ModelObject o) => '${o.label} ${(o.confidence * 100).round()}%')
        .join(', ');
  }
}
/// Background-isolate inference (§36/§56): never runs on the UI thread.
@pragma('vm:entry-point')
Future<Map<String, Object?>> runModelJob(Map<String, Object?> request) async {
  Interpreter? interpreter;
  try {
    final String modelPath = '${request['modelPath']}';
    final String labelsPath = '${request['labelsPath']}';
    final String imagePath = '${request['imagePath']}';

    final List<String> labels = File(labelsPath)
        .readAsLinesSync()
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty && line != '???')
        .toList();

    final Uint8List imageBytes = File(imagePath).readAsBytesSync();
    final img.Image? decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      return <String, Object?>{'ok': false, 'error': 'Image decode failed.'};
    }

    final InterpreterOptions options = InterpreterOptions()
      ..threads = Platform.numberOfProcessors.clamp(1, 4);
    interpreter = Interpreter.fromFile(File(modelPath), options: options);

    final Tensor inputTensor = interpreter.getInputTensor(0);
    final List<int> inputShape = inputTensor.shape;
    if (inputShape.length != 4) {
      return <String, Object?>{
        'ok': false,
        'error': 'Unsupported model input shape.',
      };
    }

    final bool channelsFirst =
        inputShape[1] == 3 && inputShape[3] != 3;
    final int size = channelsFirst ? inputShape[2] : inputShape[1];
    final bool isFloat = '${inputTensor.type}'.toLowerCase().contains('float');

    final img.Image resized =
        img.copyResize(decoded, width: size, height: size);

    final Object input = channelsFirst
        ? _buildNchwInput(resized, size, isFloat)
        : _buildNhwcInput(resized, size, isFloat);

    final Map<int, Object> outputs = <int, Object>{};
    final int outputCount = interpreter.getOutputTensors().length;
    for (int i = 0; i < outputCount; i++) {
      final Tensor tensor = interpreter.getOutputTensor(i);
      outputs[i] = _allocate(tensor.shape, '${tensor.type}');
    }

    final Stopwatch watch = Stopwatch()..start();
    interpreter.runForMultipleInputs(<Object>[input], outputs);
    watch.stop();

    final List<Map<String, Object?>> detections = _parseOutputs(
      outputs: outputs,
      labels: labels,
    );

    return <String, Object?>{
      'ok': true,
      'headSupported': true,
      'inferenceMs': watch.elapsedMilliseconds,
      'objects': detections,
    };
  } catch (e) {
    return <String, Object?>{
      'ok': false,
      'error': 'Inference could not be executed on this device.',
      'detail': '$e',
    };
  } finally {
    try {
      interpreter?.close();
    } catch (_) {}
  }
}

Object _buildNhwcInput(img.Image source, int size, bool isFloat) {
  return List<Object>.generate(
    1,
    (_) => List<List<List<Object>>>.generate(
      size,
      (int y) => List<List<Object>>.generate(
        size,
        (int x) {
          final img.Pixel p = source.getPixel(x, y);
          if (isFloat) {
            return <Object>[p.r / 255.0, p.g / 255.0, p.b / 255.0];
          }
          return <Object>[p.r.toInt(), p.g.toInt(), p.b.toInt()];
        },
      ),
    ),
  );
}

Object _buildNchwInput(img.Image source, int size, bool isFloat) {
  final List<List<List<Object>>> channels = List<List<List<Object>>>.generate(
    3,
    (_) => List<List<Object>>.generate(size, (_) => List<Object>.filled(size, 0)),
  );
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final img.Pixel p = source.getPixel(x, y);
      if (isFloat) {
        channels[0][y][x] = p.r / 255.0;
        channels[1][y][x] = p.g / 255.0;
        channels[2][y][x] = p.b / 255.0;
      } else {
        channels[0][y][x] = p.r.toInt();
        channels[1][y][x] = p.g.toInt();
        channels[2][y][x] = p.b.toInt();
      }
    }
  }
  return List<Object>.generate(1, (_) => channels);
}

Object _allocate(List<int> shape, String type) {
  final bool isFloat = type.toLowerCase().contains('float');
  if (shape.length == 1) {
    return isFloat
        ? List<double>.filled(shape[0], 0.0)
        : List<double>.filled(shape[0], 0.0);
  }
  return List<Object>.generate(
    shape[0],
    (_) => _allocate(shape.sublist(1), type),
  );
}
/// Interprets YOLOv5/YOLOv8/SSD output tensors into normalised detections.
List<Map<String, Object?>> _parseOutputs({
  required Map<int, Object> outputs,
  required List<String> labels,
}) {
  final List<Map<String, Object?>> results = <Map<String, Object?>>[];

  // --- SSD style: [1,N,4] boxes + [1,N] scores/classes ------------------
  if (outputs.length >= 3) {
    List<double>? scores;
    List<double>? classes;
    List<dynamic>? boxes;
    for (final Object value in outputs.values) {
      final List<dynamic> flat = _asList(_asList(value).isEmpty ? null : _asList(value)[0]);
      if (flat.length >= 4 && flat[0] is List) {
        final List<dynamic> candidate = _asList(flat[0]);
        if (candidate.length == 4 && candidate[0] is num) {
          boxes = flat;
        }
      }
    }
    for (final Object value in outputs.values) {
      final List<dynamic> outer = _asList(value);
      if (outer.length != 1) continue;
      final List<dynamic> inner = _asList(outer[0]);
      if (inner.isEmpty || inner.first is! num) continue;
      final double first = (inner.first as num).toDouble();
      final List<double> values =
          inner.map((dynamic e) => (e as num).toDouble()).toList();
      if (first > 1.0) {
        classes = values;
      } else {
        scores = values;
      }
    }
    if (boxes != null && scores != null) {
      final List<double> cls = classes ?? List<double>.filled(scores.length, 0.0);
      for (int i = 0; i < scores.length && i < boxes.length; i++) {
        final double score = scores[i];
        if (score < 0.25) continue;
        final List<dynamic> b = _asList(boxes[i]);
        if (b.length < 4) continue;
        results.add(<String, Object?>{
          'label': _labelFor(labels, cls[i].round()),
          'score': score,
          'left': ((b[0] as num).toDouble()).clamp(0.0, 1.0),
          'top': ((b[1] as num).toDouble()).clamp(0.0, 1.0),
          'right': ((b[2] as num).toDouble()).clamp(0.0, 1.0),
          'bottom': ((b[3] as num).toDouble()).clamp(0.0, 1.0),
        });
      }
      if (results.isNotEmpty) return _nms(results);
    }
  }

  // --- YOLO style: [1,N,85] (v5) or [1,84,8400] (v8) --------------------
  for (final Object value in outputs.values) {
    final List<dynamic> dim0 = _asList(value);
    if (dim0.isEmpty) continue;
    final List<dynamic> dim1 = _asList(dim0[0]);
    if (dim1.isEmpty) continue;
    final List<dynamic> dim2 = _asList(dim1[0]);
    if (dim2.isEmpty) continue;

    if (dim2.length == 85 || dim2.length == 84) {
      // YOLOv5 layout: rows of [cx, cy, w, h, obj, cls...]
      for (final dynamic row in dim1) {
        final List<dynamic> r = _asList(row);
        if (r.length < 6) continue;
        final double obj = (r[4] as num).toDouble();
        if (obj <= 0) continue;
        double bestScore = 0;
        int bestClass = -1;
        for (int c = 5; c < r.length; c++) {
          final double s = (r[c] as num).toDouble();
          if (s > bestScore) {
            bestScore = s;
            bestClass = c - 5;
          }
        }
        final double score = obj * bestScore;
        if (score < 0.25 || bestClass < 0) continue;
        results.add(_box(labels, bestClass, score, r));
      }
      if (results.isNotEmpty) return _nms(results);
      continue;
    }

    if (dim1.length >= 80 && dim1.length <= 100 && dim2.length > 100) {
      // YOLOv8 layout: [1, 84, 8400] channel-major.
      final int anchors = dim2.length;
      for (int a = 0; a < anchors; a++) {
        double bestScore = 0;
        int bestClass = -1;
        for (int c = 4; c < dim1.length; c++) {
          final dynamic cell = _asList(dim1[c]);
          if (a >= cell.length) continue;
          final double s = (cell[a] as num).toDouble();
          if (s > bestScore) {
            bestScore = s;
            bestClass = c - 4;
          }
        }
        if (bestScore < 0.25 || bestClass < 0) continue;
        final double cx = (_asList(dim1[0])[a] as num).toDouble();
        final double cy = (_asList(dim1[1])[a] as num).toDouble();
        final double w = (_asList(dim1[2])[a] as num).toDouble();
        final double h = (_asList(dim1[3])[a] as num).toDouble();
        results.add(<String, Object?>{
          'label': _labelFor(labels, bestClass),
          'score': bestScore,
          'left': (cx - w / 2).clamp(0.0, 1.0),
          'top': (cy - h / 2).clamp(0.0, 1.0),
          'right': (cx + w / 2).clamp(0.0, 1.0),
          'bottom': (cy + h / 2).clamp(0.0, 1.0),
        });
      }
      if (results.isNotEmpty) return _nms(results);
    }
  }
  return results;
}

Map<String, Object?> _box(
  List<String> labels,
  int classId,
  double score,
  List<dynamic> r,
) {
  final double cx = (r[0] as num).toDouble();
  final double cy = (r[1] as num).toDouble();
  final double w = (r[2] as num).toDouble();
  final double h = (r[3] as num).toDouble();
  return <String, Object?>{
    'label': _labelFor(labels, classId),
    'score': score,
    'left': (cx - w / 2).clamp(0.0, 1.0),
    'top': (cy - h / 2).clamp(0.0, 1.0),
    'right': (cx + w / 2).clamp(0.0, 1.0),
    'bottom': (cy + h / 2).clamp(0.0, 1.0),
  };
}
String _labelFor(List<String> labels, int index) {
  if (index >= 0 && index < labels.length) return labels[index];
  if (index - 1 >= 0 && index - 1 < labels.length) return labels[index - 1];
  return 'object';
}

List<dynamic> _asList(Object? value) {
  if (value is List) return value;
  return const <dynamic>[];
}

List<Map<String, Object?>> _nms(
  List<Map<String, Object?>> detections, [
  double iouThreshold = 0.45,
]) {
  final List<Map<String, Object?>> sorted = List<Map<String, Object?>>.from(
    detections,
  )..sort(
      (Map<String, Object?> a, Map<String, Object?> b) =>
          (b['score']! as double).compareTo(a['score']! as double),
    );
  final List<Map<String, Object?>> kept = <Map<String, Object?>>[];
  for (final Map<String, Object?> candidate in sorted) {
    bool overlaps = false;
    for (final Map<String, Object?> existing in kept) {
      if (existing['label'] != candidate['label']) continue;
      if (_iou(candidate, existing) > iouThreshold) {
        overlaps = true;
        break;
      }
    }
    if (!overlaps) kept.add(candidate);
    if (kept.length >= 25) break;
  }
  return kept;
}

double _iou(Map<String, Object?> a, Map<String, Object?> b) {
  final double al = a['left']! as double;
  final double at = a['top']! as double;
  final double ar = a['right']! as double;
  final double ab = a['bottom']! as double;
  final double bl = b['left']! as double;
  final double bt = b['top']! as double;
  final double br = b['right']! as double;
  final double bb = b['bottom']! as double;
  final double w = (ar < br ? ar : br) - (al > bl ? al : bl);
  final double h = (ab < bb ? ab : bb) - (at > bt ? at : bt);
  if (w <= 0 || h <= 0) return 0;
  final double intersection = w * h;
  final double areaA = (ar - al) * (ab - at);
  final double areaB = (br - bl) * (bb - bt);
  final double union = areaA + areaB - intersection;
  return union <= 0 ? 0 : intersection / union;
}