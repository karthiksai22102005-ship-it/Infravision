import 'package:flutter/material.dart';

/// Represents a single fused detection produced by the multi-model EnsembleEngine.
class UnifiedDetection {
  const UnifiedDetection({
    required this.className,
    required this.box,
    required this.confidence,
    required this.contributingModelIds,
    required this.agreementCount,
    required this.activeModelCount,
    required this.timestamp,
    required this.colorHex,
  });

  final String className;
  final Rect box;
  final double confidence;
  final List<String> contributingModelIds;
  final int agreementCount;
  final int activeModelCount;
  final int timestamp;
  final int colorHex;

  double get agreementRatio =>
      activeModelCount > 0 ? (agreementCount / activeModelCount).clamp(0.0, 1.0) : 1.0;

  String get agreementBadge => '$agreementCount/$activeModelCount';

  Offset get center => Offset(
        (box.left + box.right) / 2.0,
        (box.top + box.bottom) / 2.0,
      );
}
