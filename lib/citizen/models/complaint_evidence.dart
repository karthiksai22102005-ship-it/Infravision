import 'dart:convert';

enum EvidenceKind { image, video }

/// A media item attached to a complaint (photo, video, before/after proof).
class ComplaintEvidence {
  ComplaintEvidence({
    required this.id,
    required this.path,
    required this.kind,
    required this.timestamp,
    required this.addedBy,
    this.caption = '',
  });

  factory ComplaintEvidence.fromJson(Map<String, dynamic> json) {
    return ComplaintEvidence(
      id: json['id'] as String,
      path: json['path'] as String,
      kind: json['kind'] == 'video' ? EvidenceKind.video : EvidenceKind.image,
      timestamp: DateTime.parse(json['timestamp'] as String),
      addedBy: json['addedBy'] as String? ?? 'Citizen',
      caption: json['caption'] as String? ?? '',
    );
  }

  final String id;
  final String path;
  final EvidenceKind kind;
  final DateTime timestamp;
  final String addedBy;
  final String caption;

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'kind': kind == EvidenceKind.video ? 'video' : 'image',
        'timestamp': timestamp.toIso8601String(),
        'addedBy': addedBy,
        'caption': caption,
      };

  @override
  String toString() => jsonEncode(toJson());
}
