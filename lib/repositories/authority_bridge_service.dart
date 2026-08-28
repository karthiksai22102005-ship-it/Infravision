import '../citizen/models/complaint.dart';
import '../citizen/models/complaint_evidence.dart';
import '../citizen/models/timeline_event.dart';
import '../citizen/repository/complaint_repository.dart';
import '../citizen/services/complaint_event_service.dart';
import '../citizen/engines/priority_engine.dart';
import '../citizen/engines/sla_engine.dart';
import '../models/case_item.dart';
import '../models/complaint_item.dart' hide ComplaintStatus;

/// Payload describing a citizen-side complaint published toward the
/// authority portals (the supervisor workspace sees it as a normal complaint).
class MirrorPayload {
  MirrorPayload({
    required this.id,
    required this.caseId,
    required this.title,
    required this.category,
    required this.description,
    required this.severityName,
    required this.severityScore,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.images,
    required this.createdAtIso,
  });

  final String id;
  final String caseId;
  final String title;
  final String category;
  final String description;
  final String severityName;
  final double severityScore;
  final double latitude;
  final double longitude;
  final String address;
  final List<String> images;
  final String createdAtIso;
}

/// THE TWO-WAY AUTHORITY BRIDGE.
///
/// * Forward: every mutating action performed inside the Inspector /
///   Supervisor / Crew portals through [AppStorage] is replayed into the
///   shared citizen [ComplaintRepository] lifecycle (timeline events,
///   real-time updates, notifications) so My Reports / Nearby Issues /
///   Community Hub react live.
/// * Reverse: when a citizen report receives its official Case ID during
///   sync it is mirrored into the authority side so supervisors can triage
///   and dispatch it — closing the full shared-architecture loop.
///
/// Buffered replay makes ordering irrelevant: either side may act while the
/// other sleeps; actions replay as soon as both ends announce readiness.
class AuthorityBridgeService {
  AuthorityBridgeService._() {
    ComplaintEventService.instance.events.listen((event) {
      if (event.type == ComplaintEventType.repositoryReady &&
          !_repoReady &&
          _portalLive) {
        _repoReady = true;
        _drainForwardQueue();
      }
    });
  }

  static final AuthorityBridgeService instance = AuthorityBridgeService._();

  bool _portalLive = false;
  bool _repoReady = false;
  void Function(MirrorPayload payload)? _portalSink;
  final List<MirrorPayload> _pendingPublishes = [];
  final Set<String> _publishedIds = {};
  final List<void Function()> _queuedForward = [];

  void registerPortalSink(void Function(MirrorPayload payload) sink) {
    _portalSink = sink;
    // The reverse channel only needs the sink. Forward actions additionally
    // wait for the citizen repository to announce itself ready, so portals
    // can never crash it while it is still asleep.
    _portalLive = true;
    _drainPendingPublishes();
  }

  // -------------------------------------------------------------------------
  // FORWARD: portals -> citizen lifecycle
  // -------------------------------------------------------------------------
  void _runOrQueue(void Function() action) {
    final repo = ComplaintRepository.instance;
    if (!repo.isInitialized) {
      _queuedForward.add(action);
      return;
    }
    // Event-based readiness is asynchronous (broadcast stream); do not race
    // it — synchronise off the repository's own initialization state.
    if (!_repoReady) {
      _repoReady = true;
      _drainForwardQueue();
    }
    action();
  }

  void _drainForwardQueue() {
    for (final action in List.of(_queuedForward)) {
      action();
    }
    _queuedForward.clear();
  }

  Complaint? _findBySourceRef(String legacyId) {
    for (final c in ComplaintRepository.instance.complaints) {
      if (c.sourceRef == legacyId) return c;
    }
    return null;
  }

  /// Creates (or returns) the citizen-lifecycle twin of a portal complaint.
  Complaint ensureMirrorFromLegacy(ComplaintItem item) {
    final existing = _findBySourceRef(item.id);
    if (existing != null) return existing;

    final repo = ComplaintRepository.instance;
    final severity = SeverityLevel.fromName(item.severity.name);
    final gps = _parseGps(item.gpsCoordinates);
    final score = PriorityEngine.instance.computeScore(
        severity: severity, confirmationCount: 1, duplicateDetected: false);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final id = 'AUT-$stamp';
    final created = item.createdAt;

    TimelineEvent ev(String title, ComplaintStatus stage, String desc,
            String actor) =>
        TimelineEvent(
          id: 'TL-$id-${stage.index}-$stamp',
          complaintId: id,
          title: title,
          description: desc,
          status: stage,
          timestamp: created,
          actor: actor,
          actorType: 'inspector',
        );

    final complaint = Complaint(
      id: id,
      caseId: 'IRV-${item.id.replaceFirst('CMP-', '')}',
      citizenId: 'FIELD-INSPECTOR',
      category: item.category,
      description:
          item.inspectorNotes.isEmpty ? item.title : item.inspectorNotes,
      latitude: gps.$1,
      longitude: gps.$2,
      address: item.zone,
      severity: severity,
      priorityScore: score,
      priority: PriorityEngine.instance.levelFor(score),
      status: ComplaintStatus.departmentAssigned,
      assignedDepartment: item.department,
      createdAt: created,
      estimatedResolutionTime: SLAEngine.instance.estimatedTimeFor(severity),
      slaDeadline: item.slaDeadline,
      images: item.evidencePaths,
      confirmationCount: 1,
      sourceRef: item.id,
      timeline: [
        ev('Report Submitted', ComplaintStatus.submitted,
            'Defect logged by field inspection unit (${item.id}) at ${item.zone}.',
            'Field Inspector'),
        ev('AI Analysis Completed', ComplaintStatus.aiAnalysisCompleted,
            'Severity ${item.severity.displayName} (${(item.severityScore * 100).round()}% defect confidence).',
            'Vision AI'),
        ev('Duplicate Check Completed', ComplaintStatus.duplicateCheckCompleted,
            'No stronger existing open issue within the check radius.',
            'DuplicateDetectionEngine'),
        ev('Department Assigned', ComplaintStatus.departmentAssigned,
            'Routed to ${item.department}.', item.department),
      ],
    );
    _runOrQueue(() => repo.ingestExternal(complaint));
    return complaint;
  }

  /// Hooked into [AppStorage.logComplaint].
  void mirrorInspectorLog(ComplaintItem item) {
    _runOrQueue(() => ensureMirrorFromLegacy(item));
  }

  /// Hooked into [AppStorage.dispatchWorkOrder].
  void reflectWorkOrderDispatch(ComplaintItem complaint, CaseItem workOrder) {
    _runOrQueue(() {
      final c = ensureMirrorFromLegacy(complaint);
      ComplaintRepository.instance.applyWorkOrder(c.id,
          workOrderId: workOrder.id,
          team: workOrder.assignedTeam,
          officer: workOrder.assignedEngineer,
          slaDeadline: workOrder.slaDeadline);
    });
  }

  /// Hooked into [AppStorage.updateCaseStatus] — crew/supervisor stage moves.
  void reflectCaseStage(CaseItem workOrder, CaseStatus newStatus) {
    _runOrQueue(() {
      final c = _findBySourceRef(workOrder.complaintId);
      if (c == null) return;
      final (stage, desc, markVerified) = switch (newStatus) {
        CaseStatus.inProgress => (
            ComplaintStatus.workStarted,
            'Crew ${workOrder.assignedTeam} started on-site repairs.',
            false,
          ),
        CaseStatus.repairCompleted => (
            ComplaintStatus.repairCompleted,
            'Repair reported complete; queued for post-repair verification.',
            false,
          ),
        CaseStatus.awaitingVerification => (
            ComplaintStatus.qualityVerification,
            'Post-repair evidence inspection queued for quality check.',
            false,
          ),
        CaseStatus.resolved => (
            ComplaintStatus.citizenConfirmation,
            'Quality verification passed. Please confirm the resolution.',
            true,
          ),
        CaseStatus.assigned => (
            ComplaintStatus.repairTeamAssigned,
            workOrder.status.description,
            false,
          ),
      };
      ComplaintRepository.instance.applyAuthorityEvent(
        c.id,
        title: stage.label,
        description: desc,
        stage: stage,
        actor: workOrder.assignedTeam,
        actorType: 'crew',
        metadata: {'workOrderId': workOrder.id},
        markVerified: markVerified,
      );
    });
  }

  /// Hooked into [AppStorage.verifyAndCloseCase] — attaches the after-repair
  /// proof and hands the case to the citizen for confirmation / rating.
  void reflectClosure(
    CaseItem workOrder, {
    required bool verificationPassed,
    required String afterEvidencePath,
  }) {
    _runOrQueue(() {
      final repo = ComplaintRepository.instance;
      final c = _findBySourceRef(workOrder.complaintId);
      if (c == null) return;

      if (!verificationPassed) {
        repo.applyAuthorityEvent(
          c.id,
          title: 'Quality Verification Failed',
          description:
              'Post-repair inspection rejected the work — rework requested.'
                  '${workOrder.verificationNotes.isEmpty ? '' : ' ${workOrder.verificationNotes}'}',
          stage: ComplaintStatus.qualityVerification,
          actor: 'Inspector',
          actorType: 'inspector',
          metadata: {'workOrderId': workOrder.id},
        );
        return;
      }

      final evidence = <ComplaintEvidence>[
        if (afterEvidencePath.isNotEmpty)
          ComplaintEvidence(
            id: 'REV-${DateTime.now().millisecondsSinceEpoch}',
            path: afterEvidencePath,
            kind: EvidenceKind.image,
            timestamp: DateTime.now(),
            addedBy: workOrder.assignedTeam,
            caption: 'After-repair proof (verified)',
          ),
      ];
      repo.applyAuthorityEvent(
        c.id,
        title: 'Resolution Ready for Your Confirmation',
        description:
            'Quality verification passed'
            '${workOrder.verificationNotes.isEmpty ? '' : ': ${workOrder.verificationNotes}'}. '
            'Confirm the fix, reject it, rate the service, or reopen if it persists.',
        stage: ComplaintStatus.citizenConfirmation,
        actor: workOrder.assignedEngineer,
        actorType: 'inspector',
        evidence: evidence,
        markVerified: true,
        metadata: {'workOrderId': workOrder.id},
      );
    });
  }

  // -------------------------------------------------------------------------
  // REVERSE: citizen upload -> authority portals
  // -------------------------------------------------------------------------
  /// Called by [ComplaintSyncService] right after a citizen complaint receives
  /// its official Case ID so supervisor workflows can triage/dispatch it.
  void publishCitizenUpload(Complaint c, String officialCaseId) {
    if (!_publishedIds.add(c.id)) return;
    final payload = MirrorPayload(
      id: c.id,
      caseId: officialCaseId,
      title: c.category,
      category: c.category,
      description: c.description,
      severityName: c.severity.name,
      severityScore: (c.priorityScore / 100).clamp(0.0, 1.0),
      latitude: c.latitude,
      longitude: c.longitude,
      address: c.address,
      images: c.images,
      createdAtIso: c.createdAt.toIso8601String(),
    );
    if (_portalSink == null) {
      _pendingPublishes.add(payload);
    } else {
      _portalSink!(payload);
    }
  }

  void _drainPendingPublishes() {
    final sink = _portalSink;
    if (sink == null) return;
    for (final p in List.of(_pendingPublishes)) {
      sink(p);
    }
    _pendingPublishes.clear();
  }

  static (double, double) _parseGps(String? text) {
    const fallback = (17.3850, 78.4867);
    if (text == null) return fallback;
    final nums = RegExp(r'-?\d+(?:\.\d+)?')
        .allMatches(text)
        .map((m) => double.tryParse(m.group(0)!))
        .whereType<double>()
        .toList();
    if (nums.length >= 2) return (nums[0], nums[1]);
    return fallback;
  }
}

