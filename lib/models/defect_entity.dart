import 'dart:convert';

class DefectEntity {
  DefectEntity({
    required this.defectId,
    required this.name,
    required this.domain,
    required this.defectType,
    required this.severity,
    required this.severityScore,
    required this.firstSeen,
    required this.lastSeen,
    required this.observationCount,
    required this.location,
    required this.status,
    required this.primaryEvidencePath,
    this.gpsCoordinates,
    this.linkedComplaintId,
  });

  factory DefectEntity.fromJson(Map<String, dynamic> json) {
    return DefectEntity(
      defectId: json['defectId'] as String,
      name: json['name'] as String,
      domain: json['domain'] as String,
      defectType: json['defectType'] as String,
      severity: json['severity'] as String,
      severityScore: (json['severityScore'] as num?)?.toDouble() ?? 0.5,
      firstSeen: DateTime.parse(json['firstSeen'] as String),
      lastSeen: DateTime.parse(json['lastSeen'] as String),
      observationCount: json['observationCount'] as int? ?? 1,
      location: json['location'] as String,
      status: json['status'] as String? ?? 'Active',
      primaryEvidencePath: json['primaryEvidencePath'] as String,
      gpsCoordinates: json['gpsCoordinates'] as String?,
      linkedComplaintId: json['linkedComplaintId'] as String?,
    );
  }

  final String defectId;
  final String name;
  final String domain;
  final String defectType;
  final String severity;
  final double severityScore;
  final DateTime firstSeen;
  DateTime lastSeen;
  int observationCount;
  final String location;
  String status;
  final String primaryEvidencePath;
  final String? gpsCoordinates;
  String? linkedComplaintId;

  Map<String, dynamic> toJson() => {
        'defectId': defectId,
        'name': name,
        'domain': domain,
        'defectType': defectType,
        'severity': severity,
        'severityScore': severityScore,
        'firstSeen': firstSeen.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
        'observationCount': observationCount,
        'location': location,
        'status': status,
        'primaryEvidencePath': primaryEvidencePath,
        'gpsCoordinates': gpsCoordinates,
        'linkedComplaintId': linkedComplaintId,
      };

  @override
  String toString() => jsonEncode(toJson());
}
