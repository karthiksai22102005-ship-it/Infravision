import '../models/complaint.dart';
import '../models/timeline_event.dart';
import 'department_router.dart';
import 'duplicate_detection_engine.dart';
import 'priority_engine.dart';
import 'sla_engine.dart';

/// Result of the autonomous report orchestration.
class OrchestratorOutcome {
  const OrchestratorOutcome({
    this.created,
    this.joinedExisting,
    this.duplicate,
  });

  /// Newly built complaint (already fully analyzed/routed) — null if joined.
  final Complaint? created;

  /// The existing issue the citizen chose to join/confirm instead.
  final Complaint? joinedExisting;

  /// A potential duplicate detected during the check phase.
  final DuplicateMatch? duplicate;

  bool get isDuplicateFound => duplicate != null && created == null;
  bool get didJoin => joinedExisting != null;
}

/// Autonomous complaint orchestration pipeline.
///
/// Citizen reports issue -> AI analysis (done upstream) -> GPS verified ->
/// duplicate check -> priority score -> correct department -> SLA deadline ->
/// timeline created. Whether the citizen confirms/joins an existing issue or
/// creates a new case is decided here.
class ComplaintOrchestrator {
  ComplaintOrchestrator._();

  static final ComplaintOrchestrator instance = ComplaintOrchestrator._();

  OrchestratorOutcome orchestrate({
    required List<Complaint> existingOpen,
    required String citizenId,
    required String category,
    required SeverityLevel severity,
    required double? aiConfidence,
    required String aiDiagnosis,
    required String description,
    required double latitude,
    required double longitude,
    required String address,
    List<String> images = const [],
    List<String> videos = const [],
    bool joinExisting = false,
  }) {
    // 1. Duplicate detection (location + category + AI similarity).
    final dup = DuplicateDetectionEngine.instance.findDuplicate(
      openCandidates: existingOpen,
      category: category,
      latitude: latitude,
      longitude: longitude,
      aiConfidence: aiConfidence,
    );

    if (dup != null) {
      if (joinExisting || dup.isStrong) {
        return OrchestratorOutcome(joinedExisting: dup.existing);
      }
      return OrchestratorOutcome(duplicate: dup);
    }

    // 2. Priority calculation.
    final priorityScore = PriorityEngine.instance
        .computeScore(severity: severity, confirmationCount: 1);
    final priority =
        PriorityEngine.instance.levelFor(priorityScore);

    // 3. Department routing.
    final department = DepartmentRouter.instance.departmentFor(category);
    final officerId = DepartmentRouter.instance.officerIdFor(department);
    final crewId = DepartmentRouter.instance.crewIdFor(department, severity);

    // 4. SLA deadline.
    final slaDeadline = SLAEngine.instance.deadlineFor(severity);
    final eta = SLAEngine.instance.estimatedTimeFor(severity);

    final now = DateTime.now();
    final id =
        'CMP-${now.year}-${(now.millisecondsSinceEpoch % 100000).toString().padLeft(5, '0')}';

    final complaint = Complaint(
      id: id,
      caseId: id,
      citizenId: citizenId,
      category: category,
      description: description,
      latitude: latitude,
      longitude: longitude,
      address: address,
      severity: severity,
      priority: priority,
      priorityScore: priorityScore,
      status: ComplaintStatus.departmentAssigned,
      assignedDepartment: department,
      assignedOfficerId: officerId,
      assignedCrewId: crewId,
      createdAt: now,
      estimatedResolutionTime: eta,
      slaDeadline: slaDeadline,
      images: images,
      videos: videos,
      aiConfidence: aiConfidence,
      aiDiagnosis: aiDiagnosis,
      timeline: [
        TimelineEvent(
          id: 'TL-${now.microsecondsSinceEpoch}-1',
          complaintId: id,
          title: 'Report Submitted',
          description: 'Citizen filed the complaint with ${images.length} '
              'image(s)${videos.isNotEmpty ? ' and ${videos.length} video(s)' : ''}.',
          status: ComplaintStatus.submitted,
          timestamp: now,
          actor: 'You',
          actorType: 'citizen',
        ),
        TimelineEvent(
          id: 'TL-${now.microsecondsSinceEpoch}-2',
          complaintId: id,
          title: 'AI Analysis Completed',
          description: aiDiagnosis.isEmpty
              ? 'On-device AI assessed the defect.'
              : aiDiagnosis,
          status: ComplaintStatus.aiAnalysisCompleted,
          timestamp: now.add(const Duration(seconds: 1)),
          actor: 'AI Engine',
          actorType: 'system',
          metadata: {
            'category': category,
            'confidence': aiConfidence?.toStringAsFixed(2) ?? 'n/a',
            'severity': severity.label,
          },
        ),
        TimelineEvent(
          id: 'TL-${now.microsecondsSinceEpoch}-3',
          complaintId: id,
          title: 'Duplicate Check Completed',
          description: 'No existing duplicate found nearby. New case created.',
          status: ComplaintStatus.duplicateCheckCompleted,
          timestamp: now.add(const Duration(seconds: 2)),
          actor: 'Duplicate Detection Engine',
          actorType: 'system',
        ),
        TimelineEvent(
          id: 'TL-${now.microsecondsSinceEpoch}-4',
          complaintId: id,
          title: 'Department Assigned',
          description: 'Automatically routed to $department '
              '(officer $officerId, crew $crewId).',
          status: ComplaintStatus.departmentAssigned,
          timestamp: now.add(const Duration(seconds: 3)),
          actor: department,
          actorType: 'system',
        ),
      ],
    );

    return OrchestratorOutcome(created: complaint);
  }
}
