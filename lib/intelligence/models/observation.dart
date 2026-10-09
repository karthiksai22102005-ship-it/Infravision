/// DOMAIN-INDEPENDENT OBSERVATION MODEL.
///
/// An Observation is any single piece of evidence about the physical world:
/// a citizen report, a field-agent capture, a live AI detection, a batch
/// video finding, or resolution evidence. Observations never become cases
/// directly — they are correlated by the IssueMatchingEngine into a
/// persistent [PhysicalIssue].
library;

enum ObservationSourceType {
  citizenReport('Citizen Report'),
  citizenMedia('Citizen Media'),
  fieldAgent('Field Agent'),
  aiLiveDetection('Live AI Detection'),
  aiBatchAnalysis('Batch Video Analysis'),
  resolutionEvidence('Resolution Evidence'),
  externalSystem('External System');

  const ObservationSourceType(this.label);
  final String label;

  static ObservationSourceType fromName(Object? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return ObservationSourceType.externalSystem;
  }
}

enum ObservationStatus {
  received('Received'),
  correlated('Correlated'),
  linked('Linked to Physical Issue'),
  reviewRequired('Match Review Required'),
  rejected('Rejected');

  const ObservationStatus(this.label);
  final String label;
}

class Observation {
  Observation({
    required this.observationId,
    required this.sourceType,
    required this.sourceId,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.locationAccuracy,
    this.media = const [],
    this.visualFeatures = const {},
    this.detectedIssueType,
    this.classification,
    this.aiConfidence,
    this.userDescription = '',
    this.contextData = const {},
    this.direction,
    this.deviceInformation,
    this.relatedPhysicalIssueId,
    this.status = ObservationStatus.received,
  });

  factory Observation.fromJson(Map<String, dynamic> json) => Observation(
        observationId: json['observationId'] as String,
        sourceType: ObservationSourceType.fromName(json['sourceType']),
        sourceId: json['sourceId'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        locationAccuracy: (json['locationAccuracy'] as num?)?.toDouble(),
        media: (json['media'] as List<dynamic>?)?.cast<String>() ?? const [],
        visualFeatures:
            (json['visualFeatures'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(k, (v as num).toDouble())) ??
            const {},
        detectedIssueType: json['detectedIssueType'] as String?,
        classification: json['classification'] as String?,
        aiConfidence: (json['aiConfidence'] as num?)?.toDouble(),
        userDescription: json['userDescription'] as String? ?? '',
        contextData: (json['contextData'] as Map<String, dynamic>?) ?? const {},
        direction: json['direction'] as String?,
        deviceInformation: json['deviceInformation'] as String?,
        relatedPhysicalIssueId: json['relatedPhysicalIssueId'] as String?,
        status: ObservationStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => ObservationStatus.received,
        ),
      );

  final String observationId;

  /// Who/what produced this observation (reporter, agent, AI…).
  final ObservationSourceType sourceType;

  /// Cross-reference into the producing subsystem (complaint id, defect id,
  /// detection-history id, evidence id…). Keeps every existing model intact.
  final String sourceId;
  final DateTime timestamp;

  final double latitude;
  final double longitude;
  final double? locationAccuracy;

  final List<String> media;

  /// Optional embedding/feature vector hook for future visual AI correlation.
  final Map<String, double> visualFeatures;

  final String? detectedIssueType;
  final String? classification;
  final double? aiConfidence;
  final String userDescription;
  final Map<String, dynamic> contextData;
  final String? direction;
  final String? deviceInformation;
  String? relatedPhysicalIssueId;
  ObservationStatus status;

  Map<String, dynamic> toJson() => {
        'observationId': observationId,
        'sourceType': sourceType.name,
        'sourceId': sourceId,
        'timestamp': timestamp.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'locationAccuracy': locationAccuracy,
        'media': media,
        'visualFeatures': visualFeatures,
        'detectedIssueType': detectedIssueType,
        'classification': classification,
        'aiConfidence': aiConfidence,
        'userDescription': userDescription,
        'contextData': contextData,
        'direction': direction,
        'deviceInformation': deviceInformation,
        'relatedPhysicalIssueId': relatedPhysicalIssueId,
        'status': status.name,
      };
}
