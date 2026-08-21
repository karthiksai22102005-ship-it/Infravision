import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/model_metadata.dart';
import '../models/vision_model.dart';
import 'unified_detection.dart';

/// Strategy used by the EnsembleEngine to fuse candidate boxes and confidences.
enum FusionStrategy {
  weightedBoxFusion,
  maxConfidence,
  averageConfidence,
}

/// EnsembleEngine merges multi-model candidate detections using spatial IoU
/// clustering, class compatibility verification, Weighted Box Fusion, and
/// agreement scoring.
class EnsembleEngine {
  EnsembleEngine({
    this.iouThreshold = 0.45,
    this.fusionStrategy = FusionStrategy.weightedBoxFusion,
  });

  double iouThreshold;
  FusionStrategy fusionStrategy;

  /// Fuse detection lists from multiple models into unified detections.
  List<UnifiedDetection> fuse({
    required List<List<RawModelDetection>> modelDetections,
    required List<ModelMetadata> activeModels,
    required int timestamp,
    double minUnifiedConfidence = 0.40,
  }) {
    final activeCount = activeModels.where((m) => m.enabled).length;
    if (activeCount == 0) return const [];

    // 1. Flatten all candidate detections
    final allCandidates = <RawModelDetection>[];
    final modelWeights = <String, double>{};
    for (final model in activeModels) {
      if (model.enabled) {
        modelWeights[model.id] = model.weight;
      }
    }

    for (final detections in modelDetections) {
      allCandidates.addAll(detections);
    }

    if (allCandidates.isEmpty) return const [];

    // 2. Group candidates by semantic class
    final classGroups = <String, List<RawModelDetection>>{};
    for (final candidate in allCandidates) {
      final normalizedClass = _normalizeClassName(candidate.className);
      classGroups.putIfAbsent(normalizedClass, () => []).add(candidate);
    }

    final unifiedResults = <UnifiedDetection>[];

    // 3. Cluster and fuse overlapping bounding boxes per class
    for (final entry in classGroups.entries) {
      final className = entry.key;
      final candidates = entry.value;

      final clusters = _clusterByIou(candidates, iouThreshold);

      for (final cluster in clusters) {
        final fused = _fuseCluster(
          className: className,
          cluster: cluster,
          modelWeights: modelWeights,
          activeModelCount: activeCount,
          timestamp: timestamp,
        );

        if (fused.confidence >= minUnifiedConfidence) {
          unifiedResults.add(fused);
        }
      }
    }

    // Sort descending by confidence
    unifiedResults.sort((a, b) => b.confidence.compareTo(a.confidence));
    return unifiedResults;
  }

  List<List<RawModelDetection>> _clusterByIou(
    List<RawModelDetection> candidates,
    double threshold,
  ) {
    final remaining = List<RawModelDetection>.from(candidates)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final clusters = <List<RawModelDetection>>[];

    while (remaining.isNotEmpty) {
      final primary = remaining.removeAt(0);
      final cluster = <RawModelDetection>[primary];

      final toRemove = <RawModelDetection>[];
      for (final other in remaining) {
        final iou = computeIoU(primary.box, other.box);
        if (iou >= threshold) {
          cluster.add(other);
          toRemove.add(other);
        }
      }

      for (final r in toRemove) {
        remaining.remove(r);
      }

      clusters.add(cluster);
    }

    return clusters;
  }

  UnifiedDetection _fuseCluster({
    required String className,
    required List<RawModelDetection> cluster,
    required Map<String, double> modelWeights,
    required int activeModelCount,
    required int timestamp,
  }) {
    final contributingModels = <String>{};
    for (final c in cluster) {
      contributingModels.add(c.modelId);
    }

    final agreementCount = contributingModels.length;

    // Weighted Box Fusion (WBF)
    double totalWeight = 0.0;
    double weightedLeft = 0.0;
    double weightedTop = 0.0;
    double weightedRight = 0.0;
    double weightedBottom = 0.0;
    double maxConf = 0.0;
    double sumConf = 0.0;
    int colorHex = 0xFF5EF2A6;

    for (final candidate in cluster) {
      final w = modelWeights[candidate.modelId] ?? 1.0;
      final conf = candidate.confidence;
      final effectiveWeight = w * conf;

      weightedLeft += candidate.box.left * effectiveWeight;
      weightedTop += candidate.box.top * effectiveWeight;
      weightedRight += candidate.box.right * effectiveWeight;
      weightedBottom += candidate.box.bottom * effectiveWeight;

      totalWeight += effectiveWeight;
      maxConf = math.max(maxConf, conf);
      sumConf += conf;
      colorHex = candidate.colorHex;
    }

    final fusedBox = totalWeight > 0
        ? Rect.fromLTRB(
            (weightedLeft / totalWeight).clamp(0.0, 1.0),
            (weightedTop / totalWeight).clamp(0.0, 1.0),
            (weightedRight / totalWeight).clamp(0.0, 1.0),
            (weightedBottom / totalWeight).clamp(0.0, 1.0),
          )
        : cluster.first.box;

    // Fused confidence calculation
    final double fusedConfidence;
    switch (fusionStrategy) {
      case FusionStrategy.weightedBoxFusion:
        // Agreement bonus: higher agreement slightly boosts confidence
        final agreementBonus = agreementCount > 1 ? 0.05 * (agreementCount - 1) : 0.0;
        final avgConf = sumConf / cluster.length;
        fusedConfidence = (avgConf + agreementBonus).clamp(0.0, 0.99);
        break;
      case FusionStrategy.maxConfidence:
        fusedConfidence = maxConf;
        break;
      case FusionStrategy.averageConfidence:
        fusedConfidence = (sumConf / cluster.length).clamp(0.0, 1.0);
        break;
    }

    return UnifiedDetection(
      className: className,
      box: fusedBox,
      confidence: fusedConfidence,
      contributingModelIds: contributingModels.toList(),
      agreementCount: agreementCount,
      activeModelCount: activeModelCount,
      timestamp: timestamp,
      colorHex: colorHex,
    );
  }

  /// Calculates the Intersection-over-Union (IoU) of two bounding boxes.
  static double computeIoU(Rect a, Rect b) {
    final intersectionLeft = math.max(a.left, b.left);
    final intersectionTop = math.max(a.top, b.top);
    final intersectionRight = math.min(a.right, b.right);
    final intersectionBottom = math.min(a.bottom, b.bottom);

    if (intersectionRight <= intersectionLeft ||
        intersectionBottom <= intersectionTop) {
      return 0.0;
    }

    final intersectionArea =
        (intersectionRight - intersectionLeft) *
        (intersectionBottom - intersectionTop);

    final areaA = a.width * a.height;
    final areaB = b.width * b.height;
    final unionArea = areaA + areaB - intersectionArea;

    if (unionArea <= 0) return 0.0;
    return (intersectionArea / unionArea).clamp(0.0, 1.0);
  }

  String _normalizeClassName(String name) {
    final lower = name.toLowerCase().trim();
    if (lower == 'cell phone' || lower == 'phone' || lower == 'mobile') {
      return 'phone';
    }
    if (lower == 'car' || lower == 'truck' || lower == 'bus') {
      return 'vehicle';
    }
    if (lower == 'human' || lower == 'face') {
      return 'person';
    }
    return lower;
  }
}
