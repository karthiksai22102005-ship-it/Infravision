import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:infravision_camera/infravision_camera.dart';

import 'model_metadata.dart';
import 'vision_model.dart';

/// Model B: Complementary Structural & Chromatic Edge Saliency Model.
///
/// Executes an independent high-speed gradient-tensor analysis to cross-verify
/// physical object presence, boundary contrast, and morphological structure.
class FeatureModelB implements VisionModel {
  FeatureModelB({ModelMetadata? metadata})
      : _metadata = metadata ??
            const ModelMetadata(
              id: 'model_b_feature',
              name: 'Model B (Structural Saliency)',
              description: 'Independent edge gradient & morphological contour detector',
              version: 'v1.0-spatial',
              weight: 0.9,
              enabled: true,
              inputWidth: 64,
              inputHeight: 48,
            );

  ModelMetadata _metadata;
  ModelStatus _status = ModelStatus.loading;
  String? _errorMessage;

  static const int _gridX = 64;
  static const int _gridY = 48;
  static const int _total = _gridX * _gridY;

  final Float64List _luma = Float64List(_total);
  final Float64List _grad = Float64List(_total);
  final Uint8List _visited = Uint8List(_total);

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
    _status = ModelStatus.ready;
    _errorMessage = null;
  }

  @override
  List<RawModelDetection> infer(CameraFrame frame, {double minConfidence = 0.40}) {
    if (_status != ModelStatus.ready || !_metadata.enabled) {
      return const [];
    }

    final width = frame.width;
    final height = frame.height;
    final bytes = frame.bytes;

    if (width <= 0 || height <= 0 || bytes.length < width * height * 4) {
      return const [];
    }

    // 1. Sample downsampled luma
    for (var gy = 0; gy < _gridY; gy++) {
      final y = ((gy + 0.5) * height / _gridY).floor().clamp(0, height - 1);
      final rowOffset = y * width * 4;

      for (var gx = 0; gx < _gridX; gx++) {
        final x = ((gx + 0.5) * width / _gridX).floor().clamp(0, width - 1);
        final idx = rowOffset + x * 4;

        final r = bytes[idx];
        final g = bytes[idx + 1];
        final b = bytes[idx + 2];

        _luma[gy * _gridX + gx] = (0.299 * r + 0.587 * g + 0.114 * b);
      }
    }

    // 2. Compute 2D Sobel gradient energy
    double sumGrad = 0.0;
    for (var y = 1; y < _gridY - 1; y++) {
      final yPrev = (y - 1) * _gridX;
      final yNext = (y + 1) * _gridX;
      final yCur = y * _gridX;

      for (var x = 1; x < _gridX - 1; x++) {
        final dx = (_luma[yPrev + x + 1] + 2 * _luma[yCur + x + 1] + _luma[yNext + x + 1]) -
            (_luma[yPrev + x - 1] + 2 * _luma[yCur + x - 1] + _luma[yNext + x - 1]);
        final dy = (_luma[yNext + x - 1] + 2 * _luma[yNext + x] + _luma[yNext + x + 1]) -
            (_luma[yPrev + x - 1] + 2 * _luma[yPrev + x] + _luma[yPrev + x + 1]);

        final mag = math.sqrt(dx * dx + dy * dy);
        _grad[yCur + x] = mag;
        sumGrad += mag;
      }
    }

    final avgGrad = sumGrad / _total;
    final threshold = avgGrad * 1.6;

    // 3. Extract connected saliency clusters
    _visited.fillRange(0, _total, 0);
    final results = <RawModelDetection>[];

    for (var y = 2; y < _gridY - 2; y += 2) {
      for (var x = 2; x < _gridX - 2; x += 2) {
        final idx = y * _gridX + x;
        if (_visited[idx] == 1 || _grad[idx] < threshold) continue;

        // Bounding box flood search
        var minX = x, maxX = x, minY = y, maxY = y;
        var count = 0;
        double clusterEnergy = 0.0;

        for (var ny = math.max(0, y - 6); ny <= math.min(_gridY - 1, y + 6); ny++) {
          for (var nx = math.max(0, x - 6); nx <= math.min(_gridX - 1, x + 6); nx++) {
            final nIdx = ny * _gridX + nx;
            if (_grad[nIdx] >= threshold) {
              _visited[nIdx] = 1;
              count++;
              clusterEnergy += _grad[nIdx];
              minX = math.min(minX, nx);
              maxX = math.max(maxX, nx);
              minY = math.min(minY, ny);
              maxY = math.max(maxY, ny);
            }
          }
        }

        if (count >= 45) {
          final boxW = maxX - minX + 1;
          final boxH = maxY - minY + 1;
          final normArea = (boxW * boxH) / _total;

          if (normArea >= 0.08 && normArea <= 0.80) {
            final left = (minX / _gridX).clamp(0.0, 1.0);
            final top = (minY / _gridY).clamp(0.0, 1.0);
            final right = ((maxX + 1) / _gridX).clamp(0.0, 1.0);
            final bottom = ((maxY + 1) / _gridY).clamp(0.0, 1.0);

            final energyConfidence = (clusterEnergy / (count * 255.0 * 2.0)).clamp(0.50, 0.94);
            if (energyConfidence >= minConfidence) {
              final aspect = boxW / boxH;
              final label = (aspect >= 0.4 && aspect <= 1.4 && top < 0.55) ? 'person' : 'object';

              results.add(RawModelDetection(
                modelId: _metadata.id,
                classId: label == 'person' ? 0 : 1,
                className: label,
                confidence: energyConfidence,
                box: Rect.fromLTRB(left, top, right, bottom),
                timestamp: frame.timestamp,
                colorHex: label == 'person' ? 0xFF00E5A0 : 0xFF00B4D8,
              ));

              if (results.length >= 2) break;
            }
          }
        }
      }
      if (results.length >= 2) break;
    }

    return results;
  }

  @override
  void dispose() {}
}
