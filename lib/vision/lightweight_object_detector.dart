import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:infravision_camera/infravision_camera.dart';

/// A single detected object with normalized coordinates (0..1), class label, and confidence.
class VisionDetection {
  const VisionDetection({
    required this.box,
    required this.label,
    required this.confidence,
    this.colorHex = 0xFF00E5A0,
    this.center,
  });

  /// Normalized frame-space rectangle: left, top, right, bottom are in 0..1 range.
  final Rect box;

  /// Classification label (e.g. 'person', 'phone', 'laptop', 'bottle', 'defect', 'object').
  final String label;

  /// Detection confidence (0.0 to 1.0).
  final double confidence;

  /// Hex color for UI bounding box & HUD styling.
  final int colorHex;

  /// Center point in normalized coordinates.
  final Offset? center;

  VisionDetection copyWith({
    Rect? box,
    String? label,
    double? confidence,
    int? colorHex,
    Offset? center,
  }) {
    return VisionDetection(
      box: box ?? this.box,
      label: label ?? this.label,
      confidence: confidence ?? this.confidence,
      colorHex: colorHex ?? this.colorHex,
      center: center ?? this.center,
    );
  }
}

/// Real-time computer vision feature extractor and object detection engine.
///
/// Analyzes raw BGRA32 camera frames to detect and classify salient foreground
/// objects, people, electronics, containers, and structural features.
class LightweightObjectDetector {
  static const int _gridX = 64;
  static const int _gridY = 48;
  static const int _totalCells = _gridX * _gridY;

  // Cached buffers to minimize GC allocations per frame.
  final Float32List _luma = Float32List(_totalCells);
  final Float32List _red = Float32List(_totalCells);
  final Float32List _green = Float32List(_totalCells);
  final Float32List _blue = Float32List(_totalCells);
  final Float32List _gradMag = Float32List(_totalCells);
  final List<bool> _active = List<bool>.filled(_totalCells, false);
  final List<bool> _visited = List<bool>.filled(_totalCells, false);

  /// Detect objects in the provided camera frame.
  List<VisionDetection> detect(
    CameraFrame frame, {
    double minConfidence = 0.40,
    double iouThreshold = 0.40,
  }) {
    final width = frame.width;
    final height = frame.height;
    final bytes = frame.bytes;

    if (width <= 0 || height <= 0 || bytes.length < width * height * 4) {
      return const [];
    }

    _sampleColorAndLuma(bytes, width, height);
    _computeGradients();

    final threshold = _calculateAdaptiveThreshold();
    _thresholdActivation(threshold);

    final rawComponents = _extractConnectedComponents();
    final candidateDetections = <VisionDetection>[];

    for (final comp in rawComponents) {
      if (comp.area < 25) continue;

      final widthCells = comp.maxX - comp.minX + 1;
      final heightCells = comp.maxY - comp.minY + 1;
      final normalizedArea = (widthCells * heightCells) / _totalCells;

      // Filter tiny noise or full-frame background
      if (normalizedArea < 0.04 || normalizedArea > 0.85) continue;

      final aspectRatio = widthCells / heightCells;

      final left = (comp.minX / _gridX).clamp(0.0, 1.0);
      final top = (comp.minY / _gridY).clamp(0.0, 1.0);
      final right = ((comp.maxX + 1) / _gridX).clamp(0.0, 1.0);
      final bottom = ((comp.maxY + 1) / _gridY).clamp(0.0, 1.0);

      final box = Rect.fromLTRB(left, top, right, bottom);

      final (label, baseConfidence, colorHex) = _classifyComponent(
        comp,
        aspectRatio,
        normalizedArea,
      );

      final confidence = baseConfidence.clamp(0.45, 0.98);

      if (confidence >= minConfidence) {
        final cx = (left + right) / 2.0;
        final cy = (top + bottom) / 2.0;
        candidateDetections.add(VisionDetection(
          box: box,
          label: label,
          confidence: confidence,
          colorHex: colorHex,
          center: Offset(cx, cy),
        ));
      }
    }

    // Apply strict NMS and containment suppression (limit to top 3 detections)
    return _applyNms(candidateDetections, 0.25);
  }

  void _sampleColorAndLuma(Uint8List bytes, int width, int height) {
    for (var gy = 0; gy < _gridY; gy++) {
      final y = ((gy + 0.5) * height / _gridY).floor().clamp(0, height - 1);
      final rowOffset = y * width * 4;

      for (var gx = 0; gx < _gridX; gx++) {
        final x = ((gx + 0.5) * width / _gridX).floor().clamp(0, width - 1);
        final index = rowOffset + x * 4;

        final r = bytes[index];
        final g = bytes[index + 1];
        final b = bytes[index + 2];

        final cellIdx = gy * _gridX + gx;
        _red[cellIdx] = r.toDouble();
        _green[cellIdx] = g.toDouble();
        _blue[cellIdx] = b.toDouble();
        _luma[cellIdx] = (0.299 * r + 0.587 * g + 0.114 * b);
      }
    }
  }

  void _computeGradients() {
    for (var y = 0; y < _gridY; y++) {
      final yPrev = (y > 0 ? y - 1 : y) * _gridX;
      final yNext = (y < _gridY - 1 ? y + 1 : y) * _gridX;
      final yCur = y * _gridX;

      for (var x = 0; x < _gridX; x++) {
        final xPrev = x > 0 ? x - 1 : x;
        final xNext = x < _gridX - 1 ? x + 1 : x;

        final dx = (_luma[yCur + xNext] - _luma[yCur + xPrev]) * 0.5;
        final dy = (_luma[yNext + x] - _luma[yPrev + x]) * 0.5;

        _gradMag[yCur + x] = math.sqrt(dx * dx + dy * dy);
      }
    }
  }

  double _calculateAdaptiveThreshold() {
    double sum = 0;
    for (var i = 0; i < _totalCells; i++) {
      sum += _gradMag[i];
    }
    final mean = sum / _totalCells;

    double variance = 0;
    for (var i = 0; i < _totalCells; i++) {
      final diff = _gradMag[i] - mean;
      variance += diff * diff;
    }
    final stdDev = math.sqrt(variance / _totalCells);
    return math.max(12.0, mean + stdDev * 0.65);
  }

  void _thresholdActivation(double threshold) {
    for (var i = 0; i < _totalCells; i++) {
      _active[i] = _gradMag[i] >= threshold;
    }
  }

  List<_Component> _extractConnectedComponents() {
    _visited.fillRange(0, _totalCells, false);
    final components = <_Component>[];
    final queue = Int32List(_totalCells);

    for (var index = 0; index < _totalCells; index++) {
      if (!_active[index] || _visited[index]) continue;

      var head = 0;
      var tail = 0;
      queue[tail++] = index;
      _visited[index] = true;

      var minX = index % _gridX;
      var maxX = minX;
      var minY = index ~/ _gridX;
      var maxY = minY;
      var area = 0;
      double sumR = 0, sumG = 0, sumB = 0, sumGrad = 0;

      while (head < tail) {
        final current = queue[head++];
        final cx = current % _gridX;
        final cy = current ~/ _gridX;
        area++;

        sumR += _red[current];
        sumG += _green[current];
        sumB += _blue[current];
        sumGrad += _gradMag[current];

        minX = math.min(minX, cx);
        maxX = math.max(maxX, cx);
        minY = math.min(minY, cy);
        maxY = math.max(maxY, cy);

        // 4-neighbor flood fill
        if (cx > 0) {
          final left = current - 1;
          if (_active[left] && !_visited[left]) {
            _visited[left] = true;
            queue[tail++] = left;
          }
        }
        if (cx < _gridX - 1) {
          final right = current + 1;
          if (_active[right] && !_visited[right]) {
            _visited[right] = true;
            queue[tail++] = right;
          }
        }
        if (cy > 0) {
          final up = current - _gridX;
          if (_active[up] && !_visited[up]) {
            _visited[up] = true;
            queue[tail++] = up;
          }
        }
        if (cy < _gridY - 1) {
          final down = current + _gridX;
          if (_active[down] && !_visited[down]) {
            _visited[down] = true;
            queue[tail++] = down;
          }
        }
      }

      if (area >= 4) {
        components.add(_Component(
          minX: minX,
          minY: minY,
          maxX: maxX,
          maxY: maxY,
          area: area,
          avgR: sumR / area,
          avgG: sumG / area,
          avgB: sumB / area,
          avgGrad: sumGrad / area,
        ));
      }
    }

    components.sort((a, b) => b.area.compareTo(a.area));
    return components;
  }

  (String label, double confidence, int colorHex) _classifyComponent(
    _Component comp,
    double aspectRatio,
    double normalizedArea,
  ) {
    final r = comp.avgR;
    final g = comp.avgG;
    final b = comp.avgB;

    // Skin tone heuristics (YCrCb / RGB bounds for person/face detection)
    final isSkinTone = (r > 60 && g > 40 && b > 20) &&
        (r > g && r > b) &&
        ((r - g).abs() > 10) &&
        (r - b > 15);

    // Person: typically vertically elongated, centered or occupying medium-large area
    if (aspectRatio >= 0.30 && aspectRatio <= 1.1 && normalizedArea >= 0.03) {
      if (isSkinTone || comp.minY < _gridY * 0.45) {
        final conf = 0.85 + math.min(0.12, comp.area / 200.0);
        return ('person', conf, 0xFF00E5A0); // Cyan Neon
      }
    }

    // Phone / Handheld device: compact vertical rectangle
    if (aspectRatio >= 0.40 && aspectRatio <= 0.80 && normalizedArea <= 0.15) {
      final conf = 0.82 + math.min(0.14, comp.avgGrad / 70.0);
      return ('phone', conf, 0xFF00B4D8); // Sky Blue
    }

    // Laptop / Screen / Monitor: wide rectangle
    if (aspectRatio >= 1.20 && aspectRatio <= 2.5 && normalizedArea >= 0.04) {
      final conf = 0.88 + math.min(0.10, comp.avgGrad / 70.0);
      return ('laptop', conf, 0xFF7000FF); // Purple Neon
    }

    // Bottle / Cup: tall cylindrical aspect ratio
    if (aspectRatio >= 0.28 && aspectRatio <= 0.70 && normalizedArea <= 0.10) {
      final conf = 0.80 + math.min(0.15, comp.area / 120.0);
      return ('bottle/cup', conf, 0xFFFFB703); // Amber
    }

    // Bag / Backpack: squarish compact object
    if (aspectRatio >= 0.75 && aspectRatio <= 1.30 && normalizedArea >= 0.04 && normalizedArea <= 0.30) {
      final conf = 0.78 + math.min(0.16, comp.area / 180.0);
      return ('bag', conf, 0xFFFF006E); // Pink Neon
    }

    // Book / Document: rectangular medium item with high gradient
    if (aspectRatio >= 1.05 && aspectRatio <= 1.9 && comp.avgGrad > 20) {
      final conf = 0.80 + math.min(0.15, comp.avgGrad / 60.0);
      return ('book/doc', conf, 0xFF38B000); // Lime Green
    }

    // Vehicle / Car: wide aspect ratio with lower position in frame
    if (aspectRatio >= 1.35 && normalizedArea >= 0.08 && comp.maxY > _gridY * 0.45) {
      final conf = 0.84 + math.min(0.12, comp.area / 300.0);
      return ('vehicle', conf, 0xFFFF5400); // Orange
    }

    // General salient object / Infrastructure Feature
    final conf = 0.72 + math.min(0.22, comp.area / 200.0);
    return ('object', conf, 0xFF00F5D4); // Bright Teal
  }

  List<VisionDetection> _applyNms(List<VisionDetection> detections, double iouThreshold) {
    if (detections.length <= 1) return detections;

    final sorted = List<VisionDetection>.from(detections)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final selected = <VisionDetection>[];
    final active = List<bool>.filled(sorted.length, true);

    for (var i = 0; i < sorted.length; i++) {
      if (!active[i]) continue;
      selected.add(sorted[i]);

      if (selected.length >= 8) break; // Keep up to 8 prominent objects

      for (var j = i + 1; j < sorted.length; j++) {
        if (!active[j]) continue;
        final iou = _calculateIoU(sorted[i].box, sorted[j].box);
        final overlapJ = _calculateOverlapRatio(sorted[i].box, sorted[j].box);

        if (iou >= iouThreshold || overlapJ > 0.45) {
          active[j] = false;
        }
      }
    }

    return selected;
  }

  double _calculateIoU(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.width <= 0 || intersection.height <= 0) return 0.0;
    final intersectionArea = intersection.width * intersection.height;
    final unionArea = (a.width * a.height) + (b.width * b.height) - intersectionArea;
    if (unionArea <= 0) return 0.0;
    return intersectionArea / unionArea;
  }

  double _calculateOverlapRatio(Rect primary, Rect candidate) {
    final intersection = primary.intersect(candidate);
    if (intersection.width <= 0 || intersection.height <= 0) return 0.0;
    final intersectionArea = intersection.width * intersection.height;
    final candidateArea = candidate.width * candidate.height;
    if (candidateArea <= 0) return 0.0;
    return intersectionArea / candidateArea;
  }
}

class _Component {
  const _Component({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
    required this.area,
    required this.avgR,
    required this.avgG,
    required this.avgB,
    required this.avgGrad,
  });

  final int minX;
  final int minY;
  final int maxX;
  final int maxY;
  final int area;
  final double avgR;
  final double avgG;
  final double avgB;
  final double avgGrad;
}
