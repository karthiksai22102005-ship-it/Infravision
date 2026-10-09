/// Analysis / assessment models for the Observation Portal.
///
/// Nothing in this file invents AI output: every value is either measured from
/// the real image bytes or explicitly marked as unavailable.
library;

/// Infrastructure defect catalogue (§35).
class DefectCategory {
  const DefectCategory({
    required this.id,
    required this.label,
    required this.description,
    required this.safetyWeight,
    this.safetyCritical = false,
  });

  final String id;
  final String label;
  final String description;

  /// 0..1 weight used by the severity engine — how safety-relevant this defect
  /// class is when it appears on a public right of way.
  final double safetyWeight;

  /// Defects that can directly injure people (used by the priority engine).
  final bool safetyCritical;

  static DefectCategory fromId(String? id) =>
      DefectCategoryCatalog.byId(id) ?? DefectCategoryCatalog.other;
}

/// The ten infrastructure categories supported by the portal.
class DefectCategoryCatalog {
  DefectCategoryCatalog._();

  static const DefectCategory pothole = DefectCategory(
    id: 'pothole',
    label: 'Pothole',
    description: 'Cavity or collapsed pavement area on a carriageway.',
    safetyWeight: 0.78,
    safetyCritical: true,
  );
  static const DefectCategory roadCrack = DefectCategory(
    id: 'road_crack',
    label: 'Road crack',
    description: 'Linear cracking of the asphalt or concrete surface.',
    safetyWeight: 0.60,
  );
  static const DefectCategory damagedRoadSurface = DefectCategory(
    id: 'damaged_road_surface',
    label: 'Damaged road surface',
    description: 'Ravelling, rutting or delamination of the road surface.',
    safetyWeight: 0.66,
    safetyCritical: true,
  );
  static const DefectCategory damagedRoadSign = DefectCategory(
    id: 'damaged_road_sign',
    label: 'Damaged road sign',
    description: 'Missing, bent, faded or illegible traffic signage.',
    safetyWeight: 0.52,
  );
  static const DefectCategory damagedRoadMarking = DefectCategory(
    id: 'damaged_road_marking',
    label: 'Damaged road marking',
    description: 'Faded or missing lane / stop / zebra markings.',
    safetyWeight: 0.38,
  );
  static const DefectCategory drainageIssue = DefectCategory(
    id: 'drainage_issue',
    label: 'Drainage issue',
    description: 'Blocked or collapsed drain, gully or storm-water inlet.',
    safetyWeight: 0.70,
    safetyCritical: true,
  );
  static const DefectCategory sidewalkDamage = DefectCategory(
    id: 'sidewalk_damage',
    label: 'Sidewalk damage',
    description: 'Broken, lifted or missing footpath / kerb section.',
    safetyWeight: 0.48,
  );
  static const DefectCategory structuralDefect = DefectCategory(
    id: 'structural_defect',
    label: 'Structural defect',
    description: 'Bridge, culvert, retaining wall or column damage.',
    safetyWeight: 0.92,
    safetyCritical: true,
  );
  static const DefectCategory obstruction = DefectCategory(
    id: 'obstruction',
    label: 'Obstruction / encroachment',
    description: 'Debris, material or vegetation blocking the right of way.',
    safetyWeight: 0.74,
    safetyCritical: true,
  );
  static const DefectCategory other = DefectCategory(
    id: 'other',
    label: 'Other infrastructure defect',
    description: 'Any defect that does not fit the listed categories.',
    safetyWeight: 0.42,
  );

  static const List<DefectCategory> all = <DefectCategory>[
    pothole,
    roadCrack,
    damagedRoadSurface,
    damagedRoadSign,
    damagedRoadMarking,
    drainageIssue,
    sidewalkDamage,
    structuralDefect,
    obstruction,
    other,
  ];

  static DefectCategory? byId(String? id) {
    if (id == null) return null;
    for (final DefectCategory c in all) {
      if (c.id == id) return c;
    }
    return null;
  }
}
/// Why an on-device analysis result is (or is not) available (§37).
enum AnalysisAvailability {
  /// A model that contains infrastructure classes produced a prediction.
  modelPrediction,
  /// The bundled model loaded and ran, but has no infrastructure classes.
  modelWithoutInfrastructureClasses,
  /// No usable model on the device (missing, corrupted or not loadable).
  modelUnavailable,
  /// Inference threw — reported as unavailable instead of being faked.
  failed,
}

/// Real, measured image statistics computed from the captured pixels.
class VisualScreening {
  const VisualScreening({
    required this.meanLuminance,
    required this.luminanceStdDev,
    required this.laplacianVariance,
    required this.edgeDensity,
    required this.darkRegionRatio,
    required this.sampledWidth,
    required this.sampledHeight,
  });

  static const VisualScreening empty = VisualScreening(
    meanLuminance: 0,
    luminanceStdDev: 0,
    laplacianVariance: 0,
    edgeDensity: 0,
    darkRegionRatio: 0,
    sampledWidth: 0,
    sampledHeight: 0,
  );

  final double meanLuminance;
  final double luminanceStdDev;

  /// Focus/blur measure: variance of the discrete Laplacian.
  final double laplacianVariance;

  /// Share of pixels classified as strong edges (0..1).
  final double edgeDensity;

  /// Share of very dark pixels (0..1) — voids/potholes are typically dark.
  final double darkRegionRatio;

  final int sampledWidth;
  final int sampledHeight;

  /// Advisory only: measured surface-anomaly indicator combining dark void
  /// coverage and edge structure. This is NOT a defect classification.
  double get surfaceAnomalyIndex {
    final double dark = (darkRegionRatio * 1.6).clamp(0.0, 1.0);
    final double edges = (edgeDensity * 2.2).clamp(0.0, 1.0);
    final double focus = (laplacianVariance / 400.0).clamp(0.0, 1.0);
    return ((dark * 0.55) + (edges * 0.25) + (focus * 0.20)).clamp(0.0, 1.0);
  }
}

/// One real object detection produced by the on-device model.
class ModelObject {
  const ModelObject({
    required this.label,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String label;
  final double confidence;

  /// Normalised 0..1 coordinates of the detected box.
  final double left;
  final double top;
  final double right;
  final double bottom;
}
/// Full result of the on-device analysis step (§35/§37).
class AnalysisResult {
  const AnalysisResult({
    required this.availability,
    required this.screening,
    required this.objects,
    this.modelVersion,
    this.failureReason,
    this.inferenceMs,
    this.suggestedCategoryId,
    this.confidence,
    this.rawSummary,
  });

  factory AnalysisResult.unavailable(String reason, VisualScreening screening) =>
      AnalysisResult(
        availability: AnalysisAvailability.modelUnavailable,
        screening: screening,
        objects: const <ModelObject>[],
        failureReason: reason,
      );

  final AnalysisAvailability availability;
  final VisualScreening screening;
  final List<ModelObject> objects;

  /// Real model identity (file name + SHA-256 prefix), never a marketing name.
  final String? modelVersion;
  final String? failureReason;
  final int? inferenceMs;

  /// Only set when a genuine infrastructure class was predicted.
  final String? suggestedCategoryId;
  final double? confidence;

  /// Human-readable summary of the real model output.
  final String? rawSummary;

  bool get hasInfrastructurePrediction =>
      availability == AnalysisAvailability.modelPrediction &&
      suggestedCategoryId != null;

  String get availabilityLabel {
    switch (availability) {
      case AnalysisAvailability.modelPrediction:
        return 'AI analysis complete';
      case AnalysisAvailability.modelWithoutInfrastructureClasses:
        return 'AI defect model unavailable';
      case AnalysisAvailability.modelUnavailable:
        return 'AI analysis unavailable';
      case AnalysisAvailability.failed:
        return 'AI analysis failed';
    }
  }
}

/// Quality verdict of the pre-analysis gate (§18).
enum QualityGrade { excellent, acceptable, poor, unavailable }

class QualityFinding {
  const QualityFinding(this.code, this.message);

  final String code;
  final String message;
}

class QualityReport {
  const QualityReport({
    required this.grade,
    required this.findings,
    required this.screening,
    required this.width,
    required this.height,
  });

  factory QualityReport.analysisUnavailable() => const QualityReport(
        grade: QualityGrade.unavailable,
        findings: <QualityFinding>[
          QualityFinding(
            'check_failed',
            'Automatic quality check could not run for this file.',
          ),
        ],
        screening: VisualScreening.empty,
        width: 0,
        height: 0,
      );

  final QualityGrade grade;
  final List<QualityFinding> findings;
  final VisualScreening screening;
  final int width;
  final int height;

  bool get isPass =>
      grade == QualityGrade.acceptable || grade == QualityGrade.excellent;
  bool get failedChecks => grade == QualityGrade.poor;
}

/// A local, advisory duplicate candidate (§40).
class DuplicateMatch {
  const DuplicateMatch({
    required this.observationId,
    required this.category,
    required this.distanceMeters,
    required this.createdAt,
    required this.reasons,
    this.hashDistance,
  });

  final String observationId;
  final String category;
  final double distanceMeters;
  final DateTime createdAt;
  final List<String> reasons;

  /// Hamming distance between perceptual hashes (null when not comparable).
  final int? hashDistance;

  String get summary {
    final String distance = distanceMeters < 1000
        ? '${distanceMeters.round()} m'
        : '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    final Duration age = DateTime.now().difference(createdAt);
    final String when = age.inHours < 1
        ? '${age.inMinutes} min ago'
        : age.inDays < 1
            ? '${age.inHours} h ago'
            : '${age.inDays} d ago';
    return 'Similar ${category.replaceAll('_', ' ')} reported $distance away, $when.';
  }
}
