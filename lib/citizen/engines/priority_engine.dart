import '../models/complaint.dart';

/// Computes an autonomous 0-100 priority score for a complaint.
///
/// Factors: AI / severity weight, citizen impact (number of independent
/// confirmations of the same issue), and duplicate linkage. It deliberately
/// does NOT build a personal citizen "score" — only issue impact.
class PriorityEngine {
  PriorityEngine._();

  static final PriorityEngine instance = PriorityEngine._();

  // Weights (sum ~= 1.0)
  static const double _severityWeight = 0.55;
  static const double _impactWeight = 0.30;
  static const double _duplicateWeight = 0.15;

  double computeScore({
    required SeverityLevel severity,
    required int confirmationCount,
    bool duplicateDetected = false,
  }) {
    final severityFactor = severity.weight; // 0.25 .. 0.95
    // Impact ramps quickly with 1-5 confirmations then plateaus.
    final impactFactor = (confirmationCount <= 0)
        ? 0.2
        : (0.2 + 0.8 * (1 - 1 / (1 + confirmationCount * 0.8)));
    // Duplicate linkage raises the perceived public impact.
    final duplicateFactor = duplicateDetected ? 0.85 : 0.5;

    final score = ((severityFactor * _severityWeight) +
            (impactFactor * _impactWeight) +
            (duplicateFactor * _duplicateWeight)) *
        100;
    return score.clamp(0, 100).toDouble();
  }

  ComplaintPriorityLevel levelFor(double score) =>
      ComplaintPriorityLevel.fromScore(score);
}
