/// THE ISSUE INTELLIGENCE ENGINE — central correlation + lifecycle spine.
///
/// Every input from the four portals funnels into Observations; Observations
/// are correlated into persistent PhysicalIssues; the lifecycle state machine
/// drives issue state from real events. The engine ingests the WHOLE existing
/// system passively by subscribing to ComplaintEventService — the citizen
/// stack and the AuthorityBridge already push every mutation there.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../citizen/models/complaint.dart';
import '../citizen/services/complaint_event_service.dart';
import 'domain/domain_config.dart';
import 'engine/issue_lifecycle_engine.dart';
import 'engine/issue_matching_engine.dart';
import 'engine/visual_similarity_provider.dart';
import 'models/issue_event.dart';
import 'models/match_result.dart';
import 'models/observation.dart';
import 'models/physical_issue.dart';
import 'observation_adapters.dart';

class IntelligenceOutcome {
  const IntelligenceOutcome({
    required this.matchResult,
    required this.physicalIssue,
    required this.createdNew,
    required this.observation,
  });

  final MatchResult matchResult;
  final PhysicalIssue physicalIssue;
  final bool createdNew;
  final Observation observation;
}

class IssueIntelligenceEngine extends ChangeNotifier {
  IssueIntelligenceEngine._() {
    _matching = IssueMatchingEngine();
  }

  static final IssueIntelligenceEngine instance = IssueIntelligenceEngine._();

  late IssueMatchingEngine _matching;
  StreamSubscription? _eventSub;

  final List<PhysicalIssue> _issues = [];
  final List<Observation> _observations = [];
  final List<IssueEvent> _events = [];
  int _piSeq = 0;
  bool _ready = false;

  /// Test-only redirection of the persistence directory.
  @visibleForTesting
  static Directory? baseDirectoryOverride;

  VisualSimilarityProvider get visualProvider => _matching.visualProvider;
  set visualProvider(VisualSimilarityProvider p) =>
      _matching.visualProvider = p;

  MatchThresholds get thresholds => _matching.thresholds;
  set thresholds(MatchThresholds t) => _matching.thresholds = t;

  bool get isReady => _ready;
  DomainConfig get domain => DomainRegistry.instance.active;

  List<PhysicalIssue> get issues => List.unmodifiable(_issues);
  List<Observation> get observations => List.unmodifiable(_observations);
  List<IssueEvent> get events => List.unmodifiable(_events);

  List<IssueEvent> timelineOf(String physicalIssueId) => _events
      .where((e) => e.physicalIssueId == physicalIssueId)
      .toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  // ── Supervisor queues ──
  List<Observation> get uncertainMatchQueue => _observations
      .where((o) => o.status == ObservationStatus.reviewRequired)
      .toList();
  List<PhysicalIssue> get verificationQueue => _issues
      .where((i) =>
          i.status == IssueLifecycleState.reverificationRequired ||
          i.status == IssueLifecycleState.verificationRequired)
      .toList();
  List<PhysicalIssue> get persistentIssues => _issues
      .where((i) => i.status == IssueLifecycleState.persistent)
      .toList();
  List<PhysicalIssue> get openIssues =>
      _issues.where((i) => i.status.isOpen).toList();

  // -------------------------------------------------------------------------
  // Engine lifecycle + passive ingestion
  // -------------------------------------------------------------------------
  Directory get _storeDir {
    final override = baseDirectoryOverride;
    if (override != null) return override;
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['APPDATA'] ??
          'C:/Users/Dell/AppData/Local';
      return Directory('$localAppData/InfraVision/intelligence');
    }
    return Directory('${Directory.systemTemp.path}/infravision_intelligence');
  }

  File get _storeFile => File('${_storeDir.path}/intelligence.json');

  Future<void> initialize({bool subscribeToEvents = true}) async {
    if (_ready) return;
    try {
      if (_storeFile.existsSync()) {
        _loadStore(_storeFile.readAsStringSync());
      }
    } catch (e) {
      debugPrint('Intelligence store load error: $e');
    }
    if (subscribeToEvents) {
      _eventSub = ComplaintEventService.instance.events.listen(_onDomainEvent);
    }
    _ready = true;
    notifyListeners();
  }

  void _onDomainEvent(ComplaintDomainEvent event) {
    switch (event.type) {
      case ComplaintEventType.created:
        _ingestCreatedComplaint(event.complaint,
            fromFieldAgent: event.complaint.citizenId == 'FIELD-INSPECTOR');
      case ComplaintEventType.statusChanged:
        _onComplaintStatusChanged(event.complaint);
      case ComplaintEventType.confirmed:
        _ingestCreatedComplaint(event.complaint,
            fromFieldAgent: false, isConfirmation: true);
      case ComplaintEventType.resolved:
      case ComplaintEventType.citizenResponded:
      case ComplaintEventType.evidenceAdded:
      case ComplaintEventType.escalated:
      case ComplaintEventType.delayDetected:
      case ComplaintEventType.followed:
      case ComplaintEventType.synced:
      case ComplaintEventType.repositoryReady:
        break;
    }
  }

  // -------------------------------------------------------------------------
  // CORE: submit an Observation through the matching pipeline
  // -------------------------------------------------------------------------
  IntelligenceOutcome submitObservation(Observation obs) {
    // Pass all domain issues (matching engine uses candidate pre-filtering)
    final domainIssues =
        _issues.where((i) => i.domain == domain.domainId).toList();
    final result = _matching.evaluate(obs, domainIssues);

    late final PhysicalIssue issue;
    var createdNew = false;

    switch (result.resultType) {
      case MatchResultType.matched:
        issue =
            _issues.firstWhere((i) => i.physicalIssueId == result.physicalIssueId!);
        
        // If the issue was already resolved or closed, a new defect observation
        // means the physical issue was not actually resolved (PERSISTENT / REOPENED).
        final isPostResolution = issue.status == IssueLifecycleState.resolved ||
            issue.status == IssueLifecycleState.closed;

        _link(obs, issue,
            confidence: result.overallConfidence,
            eventType: isPostResolution
                ? IssueEventType.reopened
                : IssueEventType.matchedExisting,
            status: ObservationStatus.linked);

        if (isPostResolution) {
          _forceState(issue, IssueLifecycleState.persistent,
              sourceReference: obs.observationId);
        }
      case MatchResultType.uncertain:
        issue =
            _issues.firstWhere((i) => i.physicalIssueId == result.physicalIssueId!);
        obs.relatedPhysicalIssueId = issue.physicalIssueId;
        obs.status = ObservationStatus.reviewRequired;
        if (!_observations.contains(obs)) _observations.add(obs);
        _appendEvent(
          issue.physicalIssueId,
          IssueEventType.matchUncertain,
          'operationsManager',
          'unassigned',
          sourceReference: obs.observationId,
          description:
              'Uncertain match (${(result.overallConfidence * 100).round()}%): '
              'needs field-agent or manager verification.',
        );
        _driveLifecycle(issue, IssueEventType.matchUncertain);
      case MatchResultType.newIssue:
        issue = _createIssue(obs);
        createdNew = true;
    }

    _saveStore();
    notifyListeners();
    return IntelligenceOutcome(
        matchResult: result,
        physicalIssue: issue,
        createdNew: createdNew,
        observation: obs);
  }

  /// Manager/field-agent decision on an uncertain match.
  bool resolveUncertainMatch({
    required String observationId,
    String? physicalIssueId,
    required bool accept,
    bool createNewIfRejected = false,
    String actorId = 'supervisor',
  }) {
    final obs =
        _observations.firstWhere((o) => o.observationId == observationId);
    if (!accept) {
      if (createNewIfRejected) {
        obs.status = ObservationStatus.received;
        obs.relatedPhysicalIssueId = null;
        _createIssue(obs);
      } else {
        obs.status = ObservationStatus.rejected;
      }
      _saveStore();
      notifyListeners();
      return false;
    }
    final issue = physicalIssueId != null
        ? _issues.firstWhere((i) => i.physicalIssueId == physicalIssueId)
        : _issues
            .firstWhere((i) => i.physicalIssueId == obs.relatedPhysicalIssueId!);
    _link(obs, issue,
        confidence: 0.85,
        eventType: IssueEventType.fieldVerified,
        status: ObservationStatus.linked,
        actorType: 'operationsManager',
        actorId: actorId);
    return true;
  }

  /// Explicit Human-in-the-Loop Action: Reject uncertain match and create a new PhysicalIssue.
  PhysicalIssue rejectMatchAndCreateNew({
    required String observationId,
    String actorId = 'supervisor',
  }) {
    final obs =
        _observations.firstWhere((o) => o.observationId == observationId);
    obs.status = ObservationStatus.received;
    obs.relatedPhysicalIssueId = null;
    final newIssue = _createIssue(obs);
    _appendEvent(newIssue.physicalIssueId, IssueEventType.noteAdded,
        'operationsManager', actorId,
        description: 'Separated from candidate match into distinct physical issue.');
    _saveStore();
    notifyListeners();
    return newIssue;
  }

  /// Explicit Human-in-the-Loop Action: Merge a duplicate physical issue into a target issue.
  bool mergeIssues({
    required String targetPhysicalIssueId,
    required String sourcePhysicalIssueId,
    String actorId = 'supervisor',
  }) {
    if (targetPhysicalIssueId == sourcePhysicalIssueId) return false;
    final target = issueById(targetPhysicalIssueId);
    final source = issueById(sourcePhysicalIssueId);

    for (final obsId in source.observationIds) {
      if (!target.observationIds.contains(obsId)) {
        target.observationIds.add(obsId);
        final obs = observationById(obsId);
        if (obs != null) {
          obs.relatedPhysicalIssueId = target.physicalIssueId;
          obs.status = ObservationStatus.linked;
        }
      }
    }

    target.taskRefs.addAll(source.taskRefs.where((t) => !target.taskRefs.contains(t)));
    target.verificationHistory.addAll(source.verificationHistory);
    target.resolutionAttempts.addAll(source.resolutionAttempts);
    target.updatedAt = DateTime.now();

    _driveLifecycle(source, IssueEventType.closed, actorType: 'operationsManager');
    _appendEvent(source.physicalIssueId, IssueEventType.closed,
        'operationsManager', actorId,
        description: 'Merged into duplicate physical issue ${target.physicalIssueId}');

    _appendEvent(target.physicalIssueId, IssueEventType.matchedExisting,
        'operationsManager', actorId,
        description: 'Merged observations from duplicate physical issue ${source.physicalIssueId}');

    _saveStore();
    notifyListeners();
    return true;
  }

  /// Explicit Human-in-the-Loop Action: Mark an observation as invalid/rejected.
  void markInvalid({
    required String observationId,
    String actorId = 'supervisor',
    String reason = 'Marked invalid by operations manager',
  }) {
    final obs =
        _observations.firstWhere((o) => o.observationId == observationId);
    obs.status = ObservationStatus.rejected;
    if (obs.relatedPhysicalIssueId != null) {
      _appendEvent(obs.relatedPhysicalIssueId!, IssueEventType.noteAdded,
          'operationsManager', actorId,
          description: 'Observation ${obs.observationId} rejected: $reason');
    }
    _saveStore();
    notifyListeners();
  }

  PhysicalIssue issueById(String id) =>
      _issues.firstWhere((i) => i.physicalIssueId == id);

  Observation? observationById(String id) {
    for (final o in _observations) {
      if (o.observationId == id) return o;
    }
    return null;
  }

  // ── Internal pipeline ──
  void _ingestCreatedComplaint(Complaint c,
      {required bool fromFieldAgent, bool isConfirmation = false}) {
    final obs = fromFieldAgent
        ? ObservationAdapters.fromAgentMirror(c)
        : ObservationAdapters.fromComplaint(c);
    if (isConfirmation) {
      // A citizen confirmation correlates into the SAME physical issue.
      final existing = _findBySourceId(c.id);
      if (existing != null) {
        _link(obs, existing,
            confidence: 0.9,
            eventType: IssueEventType.matchedExisting,
            status: ObservationStatus.linked,
            actorType: 'reporter',
            actorId: c.citizenId);
        _saveStore();
        notifyListeners();
        return;
      }
    }
    submitObservation(obs);
  }

  void _onComplaintStatusChanged(Complaint c) {
    final issue = _findBySourceId(c.id);
    if (issue == null) return;
    final event = switch (c.status) {
      ComplaintStatus.inspectorVerification ||
      ComplaintStatus.departmentAssigned ||
      ComplaintStatus.submitted ||
      ComplaintStatus.aiAnalysisCompleted ||
      ComplaintStatus.duplicateCheckCompleted => null,
      ComplaintStatus.repairTeamAssigned => IssueEventType.taskAssigned,
      ComplaintStatus.workStarted => IssueEventType.workStarted,
      ComplaintStatus.repairCompleted ||
      ComplaintStatus.qualityVerification => IssueEventType.resolutionSubmitted,
      ComplaintStatus.citizenConfirmation => null, // handled below
      ComplaintStatus.closed => IssueEventType.verificationPassed,
    };
    // Citizen-confirmation stage == REVERIFICATION_REQUIRED by definition.
    if (c.status == ComplaintStatus.citizenConfirmation) {
      _forceState(issue, IssueLifecycleState.reverificationRequired,
          sourceReference: c.id);
      _saveStore();
      notifyListeners();
      return;
    }
    if (event == null) return;
    _driveLifecycle(issue, event, sourceReference: c.id);
    if (event == IssueEventType.resolutionSubmitted) {
      final obs = ObservationAdapters.fromResolutionEvidence(
          c,
          c.resolutionEvidence.isNotEmpty
              ? c.resolutionEvidence.last.path
              : '');
      obs.relatedPhysicalIssueId = issue.physicalIssueId;
      obs.status = ObservationStatus.linked;
      _observations.add(obs);
      issue.observationIds.add(obs.observationId);
      _appendEvent(issue.physicalIssueId, IssueEventType.resolutionSubmitted,
          'resolutionTeam', c.assignedCrewId ?? 'crew',
          sourceReference: c.id,
          description: 'Resolution evidence submitted for verification.');
    }
    _saveStore();
    notifyListeners();
  }

  void _link(
    Observation obs,
    PhysicalIssue issue, {
    required double confidence,
    required IssueEventType eventType,
    required ObservationStatus status,
    String actorType = 'ai',
    String actorId = 'matching-engine',
  }) {
    obs.relatedPhysicalIssueId = issue.physicalIssueId;
    obs.status = status;
    if (!issue.observationIds.contains(obs.observationId)) {
      issue.observationIds.add(obs.observationId);
    }
    issue.updatedAt = DateTime.now();
    issue.identityConfidence =
        ((issue.identityConfidence + confidence) / 2).clamp(0.0, 1.0);
    if (!_observations.contains(obs)) _observations.add(obs);
    _appendEvent(issue.physicalIssueId, eventType, actorType, actorId,
        sourceReference: obs.observationId,
        description:
            '${obs.sourceType.label} correlated at ${(confidence * 100).round()}% confidence.');
    _driveLifecycle(issue, eventType);
  }

  PhysicalIssue _createIssue(Observation obs) {
    final id =
        'PI-${((DateTime.now().microsecondsSinceEpoch + (_piSeq++) * 7919) & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    final issue = PhysicalIssue(
      physicalIssueId: id,
      domain: domain.domainId,
      issueType:
          domain.canonicalIssueType(obs.detectedIssueType ?? obs.classification),
      primaryLat: obs.latitude,
      primaryLng: obs.longitude,
      createdAt: DateTime.now(),
      identityConfidence: (obs.aiConfidence ?? 0.5).clamp(0.3, 0.95).toDouble(),
      title: obs.detectedIssueType ?? obs.classification ?? 'Physical Issue',
      address: (obs.contextData['address'] as String?) ?? '',
    );
    issue.observationIds.add(obs.observationId);
    obs.relatedPhysicalIssueId = id;
    obs.status = ObservationStatus.correlated;
    _issues.insert(0, issue);
    _observations.add(obs);
    _appendEvent(id, IssueEventType.newIssueCreated, 'system',
        'matching-engine',
        sourceReference: obs.observationId,
        description: 'New physical issue created from ${obs.sourceType.label}.');
    _driveLifecycle(issue, IssueEventType.newIssueCreated);
    return issue;
  }

  void _driveLifecycle(PhysicalIssue issue, IssueEventType event,
      {String? sourceReference, String actorType = 'system'}) {
    final next =
        IssueLifecycleEngine.instance.transitionForEvent(issue.status, event);
    if (next == null || next == issue.status) return;
    final from = issue.status;
    issue.status = next;
    issue.updatedAt = DateTime.now();
    _appendEvent(issue.physicalIssueId, IssueEventType.lifecycleChanged,
        actorType, 'lifecycle-engine',
        sourceReference: sourceReference,
        description: '${from.label} → ${next.label}',
        metadata: {'from': from.name, 'to': next.name});
  }

  /// Direct state push for stage semantics that have no 1:1 event mapping.
  void _forceState(PhysicalIssue issue, IssueLifecycleState target,
      {String? sourceReference}) {
    if (issue.status == target) return;
    final from = issue.status;
    issue.status = target;
    issue.updatedAt = DateTime.now();
    _appendEvent(issue.physicalIssueId, IssueEventType.lifecycleChanged,
        'system', 'lifecycle-engine',
        sourceReference: sourceReference,
        description: '${from.label} → ${target.label}',
        metadata: {'from': from.name, 'to': target.name});
  }

  void _appendEvent(String issueId, IssueEventType type, String actorType,
      String actorId,
      {String? sourceReference,
      String description = '',
      Map<String, dynamic> metadata = const {}}) {
    _events.add(IssueEvent(
      eventId: 'EVT-${DateTime.now().microsecondsSinceEpoch}-${_events.length}',
      physicalIssueId: issueId,
      eventType: type,
      actorType: actorType,
      actorId: actorId,
      sourceReference: sourceReference,
      timestamp: DateTime.now(),
      description: description,
      metadata: metadata,
    ));
  }

  PhysicalIssue? _findBySourceId(String sourceId) {
    for (final obs in _observations) {
      if (obs.sourceId == sourceId && obs.relatedPhysicalIssueId != null) {
        try {
          return issueById(obs.relatedPhysicalIssueId!);
        } catch (_) {}
      }
    }
    return null;
  }

  /// Manager / field-agent verdict on a submitted resolution.
  /// passed → RESOLVED → CLOSED; failed → PERSISTENT (re-inspection path).
  void verifyResolution(
    String physicalIssueId, {
    required bool passed,
    String actorId = 'supervisor',
    String notes = '',
    List<String> evidencePaths = const [],
  }) {
    final issue = issueById(physicalIssueId);
    issue.verificationHistory.add(VerificationRecord(
      verificationId:
          'VER-${DateTime.now().millisecondsSinceEpoch}',
      physicalIssueId: physicalIssueId,
      verdict: passed ? 'passed' : 'failed',
      verifiedByActorType: 'operationsManager',
      verifiedByActorId: actorId,
      timestamp: DateTime.now(),
      notes: notes,
      evidencePaths: evidencePaths,
    ));
    _driveLifecycle(
        issue,
        passed
            ? IssueEventType.verificationPassed
            : IssueEventType.verificationFailed,
        actorType: 'operationsManager');
    if (passed) {
      _driveLifecycle(issue, IssueEventType.closed,
          actorType: 'operationsManager');
    }
    _saveStore();
    notifyListeners();
  }

  /// Manually escalate a stuck issue.
  void escalate(String physicalIssueId, {String reason = ''}) {
    final issue = issueById(physicalIssueId);
    _driveLifecycle(issue, IssueEventType.escalated);
    _appendEvent(issue.physicalIssueId, IssueEventType.escalated,
        'operationsManager', 'supervisor',
        description: reason.isEmpty ? 'Escalated by operations manager.' : reason);
    _saveStore();
    notifyListeners();
  }

  /// Wipes in-memory state between tests (sandbox directory is overridden
  /// separately via [baseDirectoryOverride]).
  @visibleForTesting
  void resetForTesting() {
    _issues.clear();
    _observations.clear();
    _events.clear();
    _piSeq = 0;
    _ready = false;
    _eventSub?.cancel();
    _eventSub = null;
  }

  // ── Persistence ──
  void _saveStore() {
    try {
      _storeDir.createSync(recursive: true);
      _storeFile.writeAsStringSync(jsonEncode({
        'piSeq': _piSeq,
        'issues': _issues.map((i) => i.toJson()).toList(),
        'observations': _observations.map((o) => o.toJson()).toList(),
        'events': _events.map((e) => e.toJson()).toList(),
      }));
    } catch (e) {
      debugPrint('Intelligence store save error: $e');
    }
  }

  void _loadStore(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    _piSeq = (map['piSeq'] as num?)?.toInt() ?? 0;
    _issues.addAll(((map['issues'] as List<dynamic>?) ?? const [])
        .map((e) => PhysicalIssue.fromJson(e as Map<String, dynamic>)));
    _observations.addAll(((map['observations'] as List<dynamic>?) ?? const [])
        .map((e) => Observation.fromJson(e as Map<String, dynamic>)));
    _events.addAll(((map['events'] as List<dynamic>?) ?? const [])
        .map((e) => IssueEvent.fromJson(e as Map<String, dynamic>)));
  }
}


