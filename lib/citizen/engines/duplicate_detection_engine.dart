import '../models/complaint.dart';

/// Result of a duplicate scan for a candidate report.
class DuplicateMatch {
  const DuplicateMatch({
    required this.existing,
    required this.similarityScore,
    required this.distanceMeters,
    required this.reason,
  });

  final Complaint existing;
  final double similarityScore; // 0..1
  final double distanceMeters;
  final String reason;

  bool get isStrong => similarityScore >= 0.6;
}

/// Detects an already-reported nearby issue so citizens can CONFIRM / JOIN it
/// instead of filing a fresh duplicate. Uses location proximity + category
/// (from the AI) + AI confidence similarity as the evidence of duplication.
class DuplicateDetectionEngine {
  DuplicateDetectionEngine._();

  static final DuplicateDetectionEngine instance = DuplicateDetectionEngine._();

  /// Radius (meters) inside which two same-category reports are candidates.
  static const double _radiusMeters = 150.0;
  static const double _categoryWeight = 0.55;
  static const double _proximityWeight = 0.35;
  static const double _aiSimilarityWeight = 0.10;

  /// Returns the best potential duplicate, if one exists close enough.
  DuplicateMatch? findDuplicate({
    required List<Complaint> openCandidates,
    required String category,
    required double latitude,
    required double longitude,
    double? aiConfidence,
  }) {
    DuplicateMatch? best;
    for (final c in openCandidates) {
      if (!c.isOpen) continue;
      final dist = c.distanceTo(latitude, longitude);
      if (dist > _radiusMeters) continue;

      final sameCategory = _normalize(c.category) == _normalize(category);
      if (!sameCategory) continue; // different issue types -> not a duplicate

      final proxScore = (1 - (dist / _radiusMeters)).clamp(0.0, 1.0);
      final aiScore = (aiConfidence == null || c.aiConfidence == null)
          ? 0.5
          : (1 - (aiConfidence - c.aiConfidence!).abs()).clamp(0.0, 1.0);
      final similarity = (proxScore * _proximityWeight) +
          (1.0 * _categoryWeight) +
          (aiScore * _aiSimilarityWeight);

      if (best == null || similarity > best.similarityScore) {
        best = DuplicateMatch(
          existing: c,
          similarityScore: similarity,
          distanceMeters: dist,
          reason: sameCategory
              ? 'Same issue type detected within ${dist.round()}m'
              : 'Nearby report found',
        );
      }
    }
    return best;
  }

  String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
