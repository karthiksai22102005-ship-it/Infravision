/// MATCH RESULT MODEL + CONFIGURABLE THRESHOLDS for the IssueMatchingEngine.
/// No domain logic is hard-coded here — every factor weight and threshold is
/// tunable per domain via [MatchThresholds].
library;

enum MatchResultType { matched, newIssue, uncertain }

class MatchResult {
  const MatchResult({
    required this.resultType,
    this.physicalIssueId,
    required this.spatialScore,
    required this.temporalScore,
    required this.classificationScore,
    this.visualScore,
    this.contextScore = 0,
    required this.overallConfidence,
    this.reasons = const [],
  });

  final MatchResultType resultType;

  /// Set when resultType == matched or uncertain (best candidate).
  final String? physicalIssueId;

  final double spatialScore;
  final double temporalScore;
  final double classificationScore;

  /// Null when no visual-similarity provider is available — the engine never
  /// pretends a distance check is visual AI.
  final double? visualScore;
  final double contextScore;
  final double overallConfidence;
  final List<String> reasons;
}

class MatchThresholds {
  const MatchThresholds({
    this.autoMatchAbove = 0.78,
    this.uncertainAbove = 0.55,
    this.spatialRadiusMeters = 150,
    this.temporalWindowDays = 30,
    this.wSpatial = 0.40,
    this.wTemporal = 0.20,
    this.wClassification = 0.25,
    this.wVisual = 0.10,
    this.wContext = 0.05,
  });

  final double autoMatchAbove;
  final double uncertainAbove;
  final double spatialRadiusMeters;
  final double temporalWindowDays;

  // Correlation weights — must meaningfully sum to ~1.0.
  final double wSpatial;
  final double wTemporal;
  final double wClassification;
  final double wVisual;
  final double wContext;
}
