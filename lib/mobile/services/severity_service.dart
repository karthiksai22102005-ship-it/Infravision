import '../models/analysis.dart';
import '../models/observation.dart';

/// Deterministic severity output (§38).
class SeverityAssessment {
  const SeverityAssessment({
    required this.level,
    required this.score,
    required this.reasons,
  });

  final SeverityLevel level;
  final double score; // 0..1
  final List<String> reasons;
}

/// Rule-based severity engine.
///
/// Deliberately separated from priority (§39). Inputs are real and only real:
/// the defect category's safety weight, the measured surface-anomaly index
/// from the image screening, and the on-device model confidence when (and only
/// when) the model actually produced an infrastructure prediction.
class SeverityService {
  SeverityService._();

  static final SeverityService instance = SeverityService._();

  SeverityAssessment assess({
    required String categoryId,
    double? aiConfidence,
    VisualScreening screening = VisualScreening.empty,
    bool userConfirmedCategory = false,
  }) {
    final DefectCategory category = DefectCategory.fromId(categoryId);
    final List<String> reasons = <String>[
      '${category.label} safety weight ${category.safetyWeight.toStringAsFixed(2)}',
    ];

    double score = category.safetyWeight;

    final double anomaly = screening.surfaceAnomalyIndex;
    if (screening.sampledWidth > 0) {
      score += (anomaly - 0.5) * 0.20;
      reasons.add(
        'Measured surface anomaly ${(anomaly * 100).round()}%',
      );
    }

    if (aiConfidence != null) {
      score += (aiConfidence - 0.5) * 0.15;
      reasons.add('Model confidence ${(aiConfidence * 100).round()}%');
    } else {
      reasons.add('No model prediction — category set manually');
    }

    if (userConfirmedCategory) {
      reasons.add('Category confirmed by observer');
    }

    score = score.clamp(0.0, 1.0);
    return SeverityAssessment(
      level: SeverityLevel.fromScore(score),
      score: score,
      reasons: reasons,
    );
  }
}