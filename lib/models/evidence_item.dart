import 'dart:convert';

/// Represents a captured visual evidence item (image snapshot or video clip).
class EvidenceItem {
  EvidenceItem({
    required this.id,
    required this.filePath,
    required this.timestamp,
    required this.source,
    required this.resolution,
    required this.qualityGrade,
    required this.sha256Hash,
    this.gpsLocation,
    this.linkedComplaintId,
    this.linkedCaseId,
    this.linkedDetectionIds = const [],
  });

  factory EvidenceItem.fromJson(Map<String, dynamic> json) {
    return EvidenceItem(
      id: json['id'] as String,
      filePath: json['filePath'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      source: json['source'] as String,
      resolution: json['resolution'] as String,
      qualityGrade: json['qualityGrade'] as String,
      sha256Hash: json['sha256Hash'] as String,
      gpsLocation: json['gpsLocation'] as String?,
      linkedComplaintId: json['linkedComplaintId'] as String?,
      linkedCaseId: json['linkedCaseId'] as String?,
      linkedDetectionIds: (json['linkedDetectionIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }

  final String id;
  final String filePath;
  final DateTime timestamp;
  final String source;
  final String resolution;
  final String qualityGrade;
  final String sha256Hash;
  final String? gpsLocation;
  final String? linkedComplaintId;
  final String? linkedCaseId;
  final List<String> linkedDetectionIds;

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'timestamp': timestamp.toIso8601String(),
        'source': source,
        'resolution': resolution,
        'qualityGrade': qualityGrade,
        'sha256Hash': sha256Hash,
        'gpsLocation': gpsLocation,
        'linkedComplaintId': linkedComplaintId,
        'linkedCaseId': linkedCaseId,
        'linkedDetectionIds': linkedDetectionIds,
      };

  @override
  String toString() => jsonEncode(toJson());
}
