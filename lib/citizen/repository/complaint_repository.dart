import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/notification_service.dart';
import '../engines/complaint_orchestrator.dart';
import '../engines/escalation_engine.dart';
import '../engines/priority_engine.dart';
import '../engines/department_router.dart';
import '../engines/sla_engine.dart';
import '../models/complaint.dart';
import '../models/complaint_evidence.dart';
import '../models/timeline_event.dart';
import '../services/complaint_event_service.dart';
import '../services/complaint_sync_service.dart';
import '../services/real_time_complaint_service.dart';
import 'local_complaint_data_source.dart';
import 'remote_complaint_data_source.dart';

/// THE SHARED COMPLAINT REPOSITORY — the single source of truth connecting all
/// four Citizen sections through one complaint lifecycle.
///
/// Quick Report writes new cases here; My Reports, Nearby Issues and
/// Community Hub all read the same list; every status update flows through
/// the real-time + event services so all sections and notifications update
/// together from one data source.
class ComplaintRepository extends ChangeNotifier {
  ComplaintRepository._();

  static final ComplaintRepository instance = ComplaintRepository._();

  final List<Complaint> _complaints = [];
  final Set<String> _followedIds = {};
  bool _online = true;
  final String _citizenId = 'CIT-1001';

  late final LocalComplaintDataSource _local;
  late final RemoteComplaintDataSource _remote;
  late final ComplaintSyncService _sync;
  late final RealTimeComplaintService _realtime;
  Timer? _slaTimer;
  bool _ready = false;

  bool get isInitialized => _ready;

  // -------------------------------------------------------------------------
  // Public accessors
  // -------------------------------------------------------------------------
  List<Complaint> get complaints => List.unmodifiable(_complaints);
  bool get isOnline => _online;
  String get citizenId => _citizenId;

  /// Reports authored by the current citizen (My Reports).
  List<Complaint> get myReports =>
      _complaints.where((c) => c.citizenId == _citizenId).toList();

  /// All public, location-based issues (Nearby + Community).
  List<Complaint> get publicIssues =>
      _complaints.where((c) => c.parentComplaintId == null).toList();

  /// High-impact / trending issues for the Community Hub.
  List<Complaint> get communityTrending {
    final list = List<Complaint>.from(publicIssues)
      ..sort((a, b) => b.priorityScore.compareTo(a.priorityScore));
    return list;
  }

  List<Complaint> get resolvedIssues =>
      publicIssues.where((c) => c.status == ComplaintStatus.closed).toList();

  NotificationService get notifications => _realtime.notifications;
  int get pendingSyncCount => _sync.pendingCount;
  bool get isSyncing => _sync.isSyncing;
  Set<String> get followedIds => Set.unmodifiable(_followedIds);

  Complaint? byId(String id) {
    for (final c in _complaints) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> initialize({bool seed = true}) async {
    if (_ready) return;
    _local = LocalComplaintDataSource();
    _remote = RemoteComplaintDataSource();
    _sync = ComplaintSyncService(local: _local, remote: _remote);
    _realtime = RealTimeComplaintService()..start();

    await _local.prepare();
    final loaded = await _local.loadComplaints();
    if (loaded.isNotEmpty) {
      _complaints.addAll(loaded);
    } else if (seed) {
      _seedSampleData();
      await _persist();
    }

    _realtime.externalUpdates.listen((status) {
      // Simulated backend push — advance the newest open case.
      for (final c in _complaints.where((c) => c.isOpen).toList().reversed) {
        if (c.status.order < status.order) {
          _applyStatus(c, status, actor: 'Authority', description: 'Live update received.');
          return;
        }
      }
    });

    // Authority portals may have queued mirrors while this stack slept —
    // announce readiness so the bridge can replay them into the lists above.
    _ready = true;
    ComplaintEventService.instance.publish(ComplaintDomainEvent(
        type: ComplaintEventType.repositoryReady, complaint: _sentinel));
    notifyListeners();
  }

  /// Placeholder complaint used solely to satisfy the domain-event shape for
  /// the repository-ready broadcast (never exposed to any section).
  static final Complaint _sentinel = Complaint(
      id: '__ready__',
      caseId: '__ready__',
      citizenId: 'system',
      category: 'system',
      description: '',
      latitude: 0,
      longitude: 0,
      address: '',
      severity: SeverityLevel.low,
      priorityScore: 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      estimatedResolutionTime: '0',
      slaDeadline: DateTime.fromMillisecondsSinceEpoch(0));

  void setOnline(bool value) {
    _online = value;
    _remote.online = value;
    if (value) {
      _sync.syncAll(_complaints);
    }
    notifyListeners();
  }

  /// Periodic automatic SLA monitoring + escalation (started from main.dart).
  void startSlaMonitor({Duration interval = const Duration(seconds: 30)}) {
    _slaTimer?.cancel();
    _slaTimer = Timer.periodic(interval, (_) => _enforceSla());
  }

  void _enforceSla() {
    for (final c in _complaints.toList()) {
      if (!c.isOpen) continue;
      if (SLAEngine.instance.isBreached(c)) {
        _handleDelay(c);
      }
    }
  }

  void _handleDelay(Complaint c) {
    final (nextLevel, authority) =
        EscalationEngine.instance.nextEscalation(c);
    c.escalationLevel = nextLevel;
    c.delayReason = 'SLA breached; escalated to $authority';
    _addTimeline(
      c,
      'Delay Detected — Escalated',
      'Expected resolution time passed. Automatically escalated to $authority.',
      c.status,
      actor: authority,
      actorType: 'system',
    );
    ComplaintEventService.instance.publish(ComplaintDomainEvent(
      type: ComplaintEventType.delayDetected,
      complaint: c,
      meta: authority,
    ));
    _persist();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // QUICK REPORT entry point
  // -------------------------------------------------------------------------
  /// Runs the autonomous pipeline. Returns the citizen-facing outcome.
  ///
  /// * `isDuplicateFound == true` -> show existing issue, let citizen confirm.
  /// * `didJoin == true` -> confirmed an existing issue.
  /// * `created != null` -> a new case was created and routed.
  OrchestratorOutcome fileCitizenReport({
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
    final openNow = _complaints.where((c) => c.isOpen).toList();
    final outcome = ComplaintOrchestrator.instance.orchestrate(
      existingOpen: openNow,
      citizenId: _citizenId,
      category: category,
      severity: severity,
      aiConfidence: aiConfidence,
      aiDiagnosis: aiDiagnosis,
      description: description,
      latitude: latitude,
      longitude: longitude,
      address: address,
      images: images,
      videos: videos,
      joinExisting: joinExisting,
    );

    if (outcome.didJoin && outcome.joinedExisting != null) {
      _confirm(existing: outcome.joinedExisting!, images: images, videos: videos);
      notifyListeners();
      return outcome;
    }

    if (outcome.created != null) {
      _adoptCreated(outcome.created!);
      notifyListeners();
    }

    return outcome;
  }

  Future<OrchestratorOutcome> fileCitizenReportAsync({
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
  }) async {
    final result = fileCitizenReport(
      category: category,
      severity: severity,
      aiConfidence: aiConfidence,
      aiDiagnosis: aiDiagnosis,
      description: description,
      latitude: latitude,
      longitude: longitude,
      address: address,
      images: images,
      videos: videos,
      joinExisting: joinExisting,
    );
    if (result.created != null) {
      _sync.enqueue(result.created!.id);
      await _sync.syncAll(_complaints);
    }
    return result;
  }

  // -------------------------------------------------------------------------
  // Internal lifecycle helpers
  // -------------------------------------------------------------------------
  void _adoptCreated(Complaint c) {
    _complaints.insert(0, c);
    _followedIds.add(c.id);
    _persist();
    ComplaintEventService.instance.publish(ComplaintDomainEvent(
        type: ComplaintEventType.created, complaint: c));
  }

  TimelineEvent _addTimeline(
    Complaint c,
    String title,
    String description,
    ComplaintStatus status, {
    required String actor,
    required String actorType,
    Map<String, dynamic> metadata = const {},
  }) {
    final ev = TimelineEvent(
      id: 'TL-${DateTime.now().microsecondsSinceEpoch}',
      complaintId: c.id,
      title: title,
      description: description,
      status: status,
      timestamp: DateTime.now(),
      actor: actor,
      actorType: actorType,
      metadata: metadata,
    );
    c.timeline = [...c.timeline, ev];
    return ev;
  }

  void _applyStatus(
    Complaint c,
    ComplaintStatus newStatus, {
    required String actor,
    required String description,
  }) {
    if (c.status.order >= newStatus.order &&
        c.status != ComplaintStatus.closed) {
      return; // ignore backwards/duplicate moves
    }
    c.status = newStatus;
    c.updatedAt = DateTime.now();
    switch (newStatus) {
      case ComplaintStatus.workStarted:
        c.workStartedAt ??= DateTime.now();
      case ComplaintStatus.qualityVerification:
        c.verifiedAt ??= DateTime.now();
      case ComplaintStatus.closed:
        c.resolvedAt ??= DateTime.now();
      default:
        break;
    }
    _addTimeline(c, newStatus.label, description, newStatus,
        actor: actor, actorType: 'system');
    _persist();
    ComplaintEventService.instance.publish(ComplaintDomainEvent(
        type: ComplaintEventType.statusChanged, complaint: c));
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Citizen actions on shared issues
  // -------------------------------------------------------------------------
  void confirmIssue(
    String id, {
    List<String> images = const [],
    List<String> videos = const [],
  }) {
    final existing = byId(id);
    if (existing == null) return;
    _confirm(existing: existing, images: images, videos: videos);
    _sync.enqueue(id);
    notifyListeners();
  }

  void _confirm({
    required Complaint existing,
    List<String> images = const [],
    List<String> videos = const [],
  }) {
    existing.confirmationCount += 1;
    existing.duplicateDetected = true;
    existing.images = {...existing.images, ...images}.toList();
    existing.videos = {...existing.videos, ...videos}.toList();
    // Recompute priority from new impact level (community confirmation is a
    // factor in priority, but never builds a personal citizen score).
    existing.priorityScore = PriorityEngine.instance.computeScore(
      severity: existing.severity,
      confirmationCount: existing.confirmationCount,
      duplicateDetected: true,
    );
    existing.priority = PriorityEngine.instance.levelFor(existing.priorityScore);
    existing.citizenConfirmed = true;
    _followedIds.add(existing.id);
    _addTimeline(
      existing,
      'Citizen Confirmed Same Issue',
      'Another citizen confirmed this issue. Affected count now ${existing.confirmationCount}. Impact score increased.',
      existing.status,
      actor: 'You',
      actorType: 'citizen',
    );
    _persist();
    ComplaintEventService.instance.publish(ComplaintDomainEvent(
        type: ComplaintEventType.confirmed, complaint: existing));
  }

  void followIssue(String id, {bool follow = true}) {
    final c = byId(id);
    if (c == null) return;
    if (follow && !_followedIds.contains(id)) {
      _followedIds.add(id);
      c.followerCount += 1;
    } else if (!follow && _followedIds.contains(id)) {
      _followedIds.remove(id);
      if (c.followerCount > 0) c.followerCount -= 1;
    }
    _persist();
    ComplaintEventService.instance.publish(ComplaintDomainEvent(
        type: ComplaintEventType.followed, complaint: c));
    notifyListeners();
  }

  void addEvidence(
    String id, {
    required String path,
    required EvidenceKind kind,
    String caption = '',
    bool resolution = false,
  }) {
    final c = byId(id);
    if (c == null) return;
    final evidence = ComplaintEvidence(
      id: 'EVD-${DateTime.now().millisecondsSinceEpoch}',
      path: path,
      kind: kind,
      timestamp: DateTime.now(),
      addedBy: 'You',
      caption: caption,
    );
    if (resolution) {
      c.resolutionEvidence = [...c.resolutionEvidence, evidence];
    } else {
      c.evidence = [...c.evidence, evidence];
    }
    _addTimeline(
      c,
      resolution ? 'Resolution Evidence Added' : 'Evidence Added',
      '${caption.isEmpty ? 'Supporting evidence' : caption} '
      '${kind == EvidenceKind.video ? '(video)' : '(photo)'} added by citizen.',
      c.status,
      actor: 'You',
      actorType: 'citizen',
    );
    _persist();
    ComplaintEventService.instance.publish(ComplaintDomainEvent(
        type: ComplaintEventType.evidenceAdded, complaint: c));
    notifyListeners();
  }

  void addComment(String id, String text) {
    final c = byId(id);
    if (c == null || text.trim().isEmpty) return;
    _addTimeline(c, 'Comment', text.trim(), c.status,
        actor: 'You', actorType: 'citizen');
    _persist();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Inspectors / crews / supervisors advance the case (shared lifecycle)
  // -------------------------------------------------------------------------
  void advanceStatus(String id, ComplaintStatus newStatus,
      {String actor = 'Authority', String description = 'Status update.'}) {
    final c = byId(id);
    if (c == null) return;
    _applyStatus(c, newStatus, actor: actor, description: description);
    _sync.enqueue(id);
  }

  /// One-stop entry point used by the authority bridge (inspector / crew /
  /// supervisor portals): optionally attaches crew/officer/evidence info,
  /// advances the lifecycle stage, records the timeline event, and broadcasts.
  void applyAuthorityEvent(
    String id, {
    required String title,
    required String description,
    required ComplaintStatus stage,
    String actor = 'Inspector',
    String actorType = 'inspector',
    Map<String, dynamic> metadata = const {},
    List<ComplaintEvidence> evidence = const [],
    String? crewId,
    String? officerId,
    bool markVerified = false,
    DateTime? slaDeadline,
  }) {
    final c = byId(id);
    if (c == null) return;
    if (crewId != null) c.assignedCrewId = crewId;
    if (officerId != null) c.assignedOfficerId = officerId;
    if (slaDeadline != null) c.slaDeadline = slaDeadline;
    for (final ev in evidence) {
      c.resolutionEvidence = [...c.resolutionEvidence, ev];
    }
    c.updatedAt = DateTime.now();
    if (stage != c.status || metadata.isNotEmpty || evidence.isNotEmpty) {
      _addTimeline(c, title, description, stage,
          actor: actor, actorType: actorType, metadata: metadata);
      if (stage.order > c.status.order) c.status = stage;
      switch (stage) {
        case ComplaintStatus.workStarted:
          c.workStartedAt ??= DateTime.now();
        case ComplaintStatus.qualityVerification:
          c.verifiedAt ??= DateTime.now();
          if (markVerified == false) c.verifiedAt = DateTime.now();
        default:
          break;
      }
      _persist();
      ComplaintEventService.instance.publish(ComplaintDomainEvent(
          type: ComplaintEventType.statusChanged, complaint: c));
      notifyListeners();
    } else if (markVerified) {
      c.verifiedAt ??= DateTime.now();
      _persist();
      notifyListeners();
    }
  }

  /// Registers an authority-created complaint (inspector log / mirrored
  /// citizen report arriving from the backend simulation) into the shared
  /// store so every section sees it immediately.
  void ingestExternal(Complaint c) {
    _complaints.insert(0, c);
    _followedIds.add(c.id);
    _persist();
    ComplaintEventService.instance.publish(
        ComplaintDomainEvent(type: ComplaintEventType.created, complaint: c));
    notifyListeners();
  }

  /// Attaches a supervisor-issued work order (crew/team assignment) to a case.
  void applyWorkOrder(
    String id, {
    required String workOrderId,
    required String team,
    String? officer,
    DateTime? slaDeadline,
  }) {
    applyAuthorityEvent(
      id,
      title: 'Repair Team Assigned',
      description:
          'Work order $workOrderId issued to $team. Team mobilisation in progress.',
      stage: ComplaintStatus.repairTeamAssigned,
      actor: officer ?? 'Supervisor',
      actorType: 'supervisor',
      crewId: team,
      officerId: officer,
      slaDeadline: slaDeadline,
      metadata: {'workOrderId': workOrderId},
    );
  }

  // -------------------------------------------------------------------------
  // Citizen resolution response (confirm / reject / reopen / poor quality)
  // -------------------------------------------------------------------------
  void resolveConfirm(String id, {required bool satisfied, int? rating}) {
    final c = byId(id);
    if (c == null) return;

    c.citizenRating = rating;
    if (!satisfied) {
      // Citizen rejects the resolution -> case reopens automatically.
      _setStatus(c, ComplaintStatus.submitted,
          title: 'Resolution Rejected',
          description: 'Citizen reported the resolution was not satisfactory. '
              'Case reopened for re-verification.');
      c.resolvedAt = null;
      c.citizenConfirmed = false;
      _persist();
      ComplaintEventService.instance.publish(ComplaintDomainEvent(
          type: ComplaintEventType.citizenResponded, complaint: c));
      notifyListeners();
      return;
    }

    // Satisfied -> Citizen Confirmation then Closed.
    if (c.status != ComplaintStatus.closed) {
      _setStatus(c, ComplaintStatus.citizenConfirmation,
          title: 'Citizen Confirmation',
          description: rating != null
              ? 'Citizen confirmed resolution and rated service $rating/5.'
              : 'Citizen confirmed the resolution.');
      _setStatus(c, ComplaintStatus.closed,
          title: 'Case Closed',
          description: 'Case closed after quality verification and citizen confirmation.',
          hideIfBehind: true);
    }
    c.citizenConfirmed = true;
    c.resolvedAt ??= DateTime.now();
    c.verifiedAt ??= DateTime.now();
    _persist();
    ComplaintEventService.instance.publish(ComplaintDomainEvent(
        type: ComplaintEventType.resolved, complaint: c));
    notifyListeners();
  }

  void reopen(String id, String reason) {
    final c = byId(id);
    if (c == null) return;
    _setStatus(c, ComplaintStatus.submitted,
        title: 'Citizen Reopened Case',
        description: reason.isEmpty ? 'Case reopened by citizen.' : reason);
    c.resolvedAt = null;
    c.citizenConfirmed = false;
    _persist();
    notifyListeners();
  }

  void reportPoorQuality(String id, String note) {
    final c = byId(id);
    if (c == null) return;
    _setStatus(c, ComplaintStatus.submitted,
        title: 'Poor Repair Quality Reported',
        description: note.isEmpty
            ? 'Citizen reported poor repair quality. Case re-opened for quality review.'
            : note);
    c.resolvedAt = null;
    _persist();
    notifyListeners();
  }

  void _setStatus(Complaint c, ComplaintStatus newStatus,
      {required String title, required String description,
      bool hideIfBehind = false}) {
    c.status = newStatus;
    c.updatedAt = DateTime.now();
    _addTimeline(c, title, description, newStatus,
        actor: 'Citizen', actorType: 'citizen');
  }

  Future<void> _persist() => _local.saveComplaints(_complaints);

  // -------------------------------------------------------------------------
  // Seed data (community / nearby demo content for a non-empty canvas)
  // -------------------------------------------------------------------------
  Complaint _seedSkeleton({
    required String id,
    required String owner,
    required String category,
    required SeverityLevel severity,
    required ComplaintStatus status,
    required double lat,
    required double lng,
    required String address,
    String desc = '',
    int confirmations = 1,
    int priority = 0,
    bool resolved = false,
    int? rating,
    List<String> images = const [],
    List<String> resolution = const [],
    Duration age = const Duration(hours: 2),
  }) {
    final now = DateTime.now();
    final score = priority > 0
        ? priority.toDouble()
        : PriorityEngine.instance.computeScore(
            severity: severity, confirmationCount: confirmations);
    final dept = DepartmentRouter.instance.departmentFor(category);
    return Complaint(
      id: id,
      caseId: resolved ? 'IV-2026-0$id' : id,
      citizenId: owner,
      category: category,
      description: desc.isEmpty ? 'Citizen-reported $category issue.' : desc,
      latitude: lat,
      longitude: lng,
      address: address,
      severity: severity,
      priority: PriorityEngine.instance.levelFor(score),
      priorityScore: score,
      status: status,
      assignedDepartment: dept,
      assignedOfficerId: DepartmentRouter.instance.officerIdFor(dept),
      createdAt: now.subtract(age),
      estimatedResolutionTime: SLAEngine.instance.estimatedTimeFor(severity),
      slaDeadline:
          SLAEngine.instance.deadlineFor(severity, from: now.subtract(age)),
      images: images,
      confirmationCount: confirmations,
      followerCount: confirmations + 2,
      citizenConfirmed: true,
      citizenRating: rating,
      resolvedAt: resolved ? now.subtract(const Duration(days: 1)) : null,
      verifiedAt: resolved ? now.subtract(const Duration(days: 1)) : null,
      timeline: [
        TimelineEvent(
          id: 'TL-$id-1',
          complaintId: id,
          title: 'Report Submitted',
          description: 'Issue reported by a citizen.',
          status: ComplaintStatus.submitted,
          timestamp: now.subtract(age),
          actor: owner == _citizenId ? 'You' : 'Citizen',
          actorType: 'citizen',
        ),
        TimelineEvent(
          id: 'TL-$id-2',
          complaintId: id,
          title: status.label,
          description: 'Current lifecycle stage.',
          status: status,
          timestamp: now.subtract(const Duration(minutes: 30)),
          actor: dept,
          actorType: 'system',
        ),
      ],
      resolutionEvidence: resolution
          .map((p) => ComplaintEvidence(
                id: 'REV-$id-${p.hashCode}',
                path: p,
                kind: EvidenceKind.image,
                timestamp: now.subtract(const Duration(days: 1)),
                addedBy: 'Inspector',
                caption: 'Repair evidence',
              ))
          .toList(),
    );
  }

  void _seedSampleData() {
    // ---- My Reports (current citizen) ----
    _complaints.add(_seedSkeleton(
      id: 'S1',
      owner: _citizenId,
      category: 'Pothole & Asphalt Degradation',
      severity: SeverityLevel.high,
      status: ComplaintStatus.workStarted,
      lat: 17.3821,
      lng: 78.4859,
      address: 'Outer Ring Road, Sector B',
      desc: 'Deep pothole on the left lane causing vehicles to swerve.',
      confirmations: 2,
      images: ['assets/sample_before.jpg'],
      age: const Duration(hours: 30),
    ));
    _complaints.add(_seedSkeleton(
      id: 'S2',
      owner: _citizenId,
      category: 'Streetlight & Traffic Signal',
      severity: SeverityLevel.moderate,
      status: ComplaintStatus.closed,
      lat: 17.3844,
      lng: 78.4877,
      address: 'Junction 4, Main Avenue',
      desc: 'Streetlight not working for a week.',
      confirmations: 3,
      resolved: true,
      rating: 4,
      resolution: ['assets/sample_after.jpg'],
      age: const Duration(days: 5),
    ));
    // ---- Nearby / community issues from other citizens ----
    _complaints.add(_seedSkeleton(
      id: 'N1',
      owner: 'CIT-2001',
      category: 'Pothole & Asphalt Degradation',
      severity: SeverityLevel.critical,
      status: ComplaintStatus.inspectorVerification,
      lat: 17.3810,
      lng: 78.4833,
      address: 'Sector A Ring Service Lane',
      confirmations: 5,
      images: ['assets/sample_before.jpg'],
      age: const Duration(hours: 8),
    ));
    _complaints.add(_seedSkeleton(
      id: 'N2',
      owner: 'CIT-2002',
      category: 'Drainage & Public Health',
      severity: SeverityLevel.high,
      status: ComplaintStatus.repairTeamAssigned,
      lat: 17.3860,
      lng: 78.4890,
      address: 'Stormwater sump, Sector D',
      confirmations: 4,
      age: const Duration(hours: 20),
    ));
    _complaints.add(_seedSkeleton(
      id: 'N3',
      owner: 'CIT-2003',
      category: 'Concrete & Structural',
      severity: SeverityLevel.moderate,
      status: ComplaintStatus.submitted,
      lat: 17.3835,
      lng: 78.4885,
      address: 'Footpath near Metro Exit 3',
      confirmations: 1,
      age: const Duration(hours: 3),
    ));
    _complaints.add(_seedSkeleton(
      id: 'N4',
      owner: 'CIT-2004',
      category: 'Manhole / Drainage',
      severity: SeverityLevel.critical,
      status: ComplaintStatus.workStarted,
      lat: 17.3875,
      lng: 78.4842,
      address: 'Crossing of Avenue 2',
      confirmations: 3,
      age: const Duration(hours: 12),
    ));
    _complaints.add(_seedSkeleton(
      id: 'R1',
      owner: 'CIT-3001',
      category: 'Pothole & Asphalt Degradation',
      severity: SeverityLevel.moderate,
      status: ComplaintStatus.closed,
      lat: 17.3855,
      lng: 78.4860,
      address: 'Quarter service lane',
      confirmations: 4,
      resolved: true,
      rating: 5,
      resolution: ['assets/sample_after.jpg'],
      age: const Duration(days: 3),
    ));
  }
}





