import '../models/analysis.dart';
import '../models/observation.dart';

/// Deterministic priority output (§39) — always kept separate from severity.
class PriorityAssessment {
  const PriorityAssessment({
    required this.level,
    required this.score,
    required this.reasons,
  });

  final PriorityLevel level;
  final double score; // 0..100
  final List<String> reasons;
}

/// Priority engine: how soon the defect must be handled (P0..P3).
///
/// Inputs: computed severity, whether the category can directly injure people,
/// and how much evidence supports the report. It never re-uses severity labels
/// so the two concepts stay independent (§38/§39).
class PriorityService {
  PriorityService._();

  static final PriorityService instance = PriorityService._();

  PriorityAssessment assess({
    required SeverityLevel severity,
    required double severityScore,
    required String categoryId,
    int evidenceCount = 1,
  }) {
    final DefectCategory category = DefectCategory.fromId(categoryId);
    final List<String> reasons = <String>[
      'Severity ${severity.label} (${(severityScore * 100).round()}%)',
    ];

    double score = severityScore * 62;

    if (category.safetyCritical) {
      score += 12;
      reasons.add('Direct public-safety relevance');
    }
    if (evidenceCount >= 2) {
      score += 4;
      reasons.add('$evidenceCount supporting evidence items');
    }
    if (severity == SeverityLevel.critical) {
      score += 8;
      reasons.add('Critical severity escalates urgency');
    }

    score = score.clamp(0.0, 100.0);
    return PriorityAssessment(
      level: PriorityLevel.fromScore(score),
      score: score,
      reasons: reasons,
    );
  }
}