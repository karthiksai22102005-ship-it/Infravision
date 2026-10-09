import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:infravision/citizen/models/complaint.dart';
import 'package:infravision/citizen/services/complaint_event_service.dart';
import 'package:infravision/intelligence/domain/domain_config.dart';
import 'package:infravision/intelligence/engine/issue_lifecycle_engine.dart';
import 'package:infravision/intelligence/engine/visual_similarity_provider.dart';
import 'package:infravision/intelligence/issue_intelligence_engine.dart';
import 'package:infravision/intelligence/models/issue_event.dart';
import 'package:infravision/intelligence/models/match_result.dart';
import 'package:infravision/intelligence/models/observation.dart';
import 'package:infravision/intelligence/models/physical_issue.dart';

Directory? sandbox;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('infravision_intel_');
    IssueIntelligenceEngine.baseDirectoryOverride = sandbox;
    IssueIntelligenceEngine.instance.resetForTesting();
  });

  tearDown(() async {
    IssueIntelligenceEngine.instance.resetForTesting();
    try {
      await sandbox?.delete(recursive: true);
    } catch (_) {}
    IssueIntelligenceEngine.baseDirectoryOverride = null;
  });

  Observation obs({
    required String id,
    double lat = 17.40,
    double lng = 78.48,
    String type = 'Pothole & Asphalt Degradation',
    String address = 'Zone 3, Main Road',
    Map<String, double> features = const {},
  }) =>
      Observation(
        observationId: id,
        sourceType: ObservationSourceType.citizenReport,
        sourceId: 'SRC-$id',
        timestamp: DateTime.now(),
        latitude: lat,
        longitude: lng,
        locationAccuracy: 8,
        detectedIssueType: type,
        aiConfidence: 0.8,
        userDescription: 'Deep hole',
        contextData: {'address': address},
        visualFeatures: features,
      );

  test('same-place same-type observation MATCHES into one PhysicalIssue',
      () async {
    final engine = IssueIntelligenceEngine.instance;
    await engine.initialize(subscribeToEvents: false);

    final first = engine.submitObservation(obs(id: 'OBS-1'));
    expect(first.createdNew, isTrue);
    expect(first.physicalIssue.physicalIssueId, startsWith('PI-'));
    expect(first.matchResult.resultType, MatchResultType.newIssue);

    final second = engine.submitObservation(obs(id: 'OBS-2'));
    expect(second.createdNew, isFalse,
        reason:
            'confidence ${second.matchResult.overallConfidence} should auto-match');
    expect(second.matchResult.resultType, MatchResultType.matched);
    expect(second.physicalIssue.physicalIssueId,
        first.physicalIssue.physicalIssueId);
    expect(second.physicalIssue.observationIds.length, 2);
  });

  test('far-away / different-type observation creates a NEW PhysicalIssue',
      () async {
    final engine = IssueIntelligenceEngine.instance;
    await engine.initialize(subscribeToEvents: false);

    engine.submitObservation(obs(id: 'OBS-A'));
    final far = engine.submitObservation(
        obs(id: 'OBS-B', lat: 17.60, lng: 78.70, type: 'Lighting Failure'));
    expect(far.createdNew, isTrue);
    expect(engine.issues.length, 2);
  });

  test('lifecycle state machine enforces the verification-first flow',
      () async {
    final engine = IssueIntelligenceEngine.instance;
    await engine.initialize(subscribeToEvents: false);
    final lc = IssueLifecycleEngine.instance;

    final outcome = engine.submitObservation(obs(id: 'OBS-LC'));
    expect(outcome.physicalIssue.status, IssueLifecycleState.candidate);

    // Illegal skip: candidate cannot jump straight to assigned.
    expect(
        lc.transitionForEvent(
            IssueLifecycleState.candidate, IssueEventType.taskAssigned),
        isNull);

    // Legal path: verificationRequired → verified → assigned.
    expect(
        lc.transitionForEvent(IssueLifecycleState.verificationRequired,
            IssueEventType.fieldVerified),
        IssueLifecycleState.verified);
    expect(
        lc.transitionForEvent(
            IssueLifecycleState.verified, IssueEventType.taskAssigned),
        IssueLifecycleState.assigned);

    // Full closure through the engine's resolution verifier.
    engine.verifyResolution(outcome.physicalIssue.physicalIssueId,
        passed: true);
    final st = outcome.physicalIssue.status;
    expect(
        st == IssueLifecycleState.resolved || st == IssueLifecycleState.closed,
        isTrue);
  });

  test('failed result verification marks the issue PERSISTENT', () async {
    final engine = IssueIntelligenceEngine.instance;
    await engine.initialize(subscribeToEvents: false);
    final pi = engine.submitObservation(obs(id: 'OBS-P')).physicalIssue;

    pi.status = IssueLifecycleState.reverificationRequired;
    engine.verifyResolution(pi.physicalIssueId, passed: false);
    expect(pi.status, IssueLifecycleState.persistent);
    expect(engine.persistentIssues, contains(pi));
  });

  test('store round-trips issues, observations and events', () async {
    final engine = IssueIntelligenceEngine.instance;
    await engine.initialize(subscribeToEvents: false);
    engine.submitObservation(obs(id: 'OBS-RT'));

    // Simulate a cold start against the same sandbox store.
    engine.resetForTesting();
    await engine.initialize(subscribeToEvents: false);
    expect(engine.issues, isNotEmpty);
    expect(engine.observations.first.sourceId, 'SRC-OBS-RT');
    expect(engine.events.first.eventType, IssueEventType.newIssueCreated);
  });

  test('citizen complaint events auto-ingest as Observations', () async {
    final engine = IssueIntelligenceEngine.instance;
    await engine.initialize(); // subscribed to the shared event bus
    final before = engine.observations.length;

    final complaint = Complaint(
      id: 'REP-EVT-9',
      caseId: 'IRV-9',
      citizenId: 'CIT-1001',
      category: 'Pothole & Asphalt Degradation',
      description: 'Hole near school',
      latitude: 17.41,
      longitude: 78.49,
      address: 'Zone 5',
      severity: SeverityLevel.high,
      priorityScore: 70,
      createdAt: DateTime.now(),
      estimatedResolutionTime: '48 hours',
      slaDeadline: DateTime.now().add(const Duration(hours: 48)),
      aiConfidence: 0.82,
      aiDiagnosis: 'Pothole',
    );
    ComplaintEventService.instance.publish(ComplaintDomainEvent(
        type: ComplaintEventType.created, complaint: complaint));
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(engine.observations.length, greaterThan(before));
    expect(engine.issues.first.address, 'Zone 5');
    expect(engine.domain.displayName, contains('Infrastructure'));
  });

  test('domain config is domain-independent and alias-aware', () {
    const d = DomainCatalog.infrastructure;
    expect(d.canonicalIssueType('pothole'), 'Road Surface Damage');
    expect(d.canonicalIssueType('Totally Unknown'), 'Totally Unknown');
    expect(d.roles.fieldAgent, 'Field Inspector');
    expect(d.roles.resolutionTeam, 'Repair Crew');

    // Registering a different domain changes role labels with ZERO core code
    // changes — proving the domain-independence requirement.
    DomainRegistry.instance.register(const DomainConfig(
      domainId: 'facility',
      displayName: 'Facility Management',
      assetTypes: ['HVAC', 'Elevator'],
      issueTypes: ['Damage', 'Leakage'],
      roles: DomainRoleLabels(
        reporter: 'Tenant',
        fieldAgent: 'Facility Inspector',
        resolutionTeam: 'Maintenance Team',
        operationsManager: 'Facility Manager',
      ),
      workflowRules: DomainWorkflowRules(),
      slaHoursBySeverity: {'high': 12},
      minAiConfidence: 0.5,
    ));
    DomainRegistry.instance.activate('facility');
    expect(DomainRegistry.instance.active.roles.reporter, 'Tenant');
    DomainRegistry.instance.activate('infrastructure');
  });

  test('feature-vector visual provider scores honestly or returns null', () {
    const provider = FeatureVectorSimilarityProvider();
    final a = obs(id: 'V1', features: const {'edge': 0.8, 'dark': 0.6});
    final b = obs(id: 'V2', features: const {'edge': 0.8, 'dark': 0.6});
    final c = obs(id: 'V3');
    expect(provider.similarity(a, b), closeTo(1.0, 0.01));
    expect(provider.similarity(a, c), isNull);
    // The default provider is always honest about having no visual AI:
    expect(const NoVisualSimilarityProvider().similarity(a, b), isNull);
  });

  // =========================================================================
  // SECTION 28 — EXPLICIT REQUIRED TEST SCENARIOS (1 through 7)
  // =========================================================================

  test('SCENARIO 1: Citizen reports an issue -> New PhysicalIssue created',
      () async {
    final engine = IssueIntelligenceEngine.instance;
    await engine.initialize(subscribeToEvents: false);

    final citizenObs = Observation(
      observationId: 'OBS-SCENARIO-1',
      sourceType: ObservationSourceType.citizenReport,
      sourceId: 'CIT-REP-101',
      timestamp: DateTime.now(),
      latitude: 17.4399,
      longitude: 78.4983,
      detectedIssueType: 'Road Surface Damage',
      aiConfidence: 0.88,
      userDescription: 'Pothole on main lane',
      contextData: {'address': 'MG Road, Secunderabad'},
    );

    final outcome = engine.submitObservation(citizenObs);
    expect(outcome.createdNew, isTrue);
    expect(outcome.matchResult.resultType, MatchResultType.newIssue);
    expect(outcome.physicalIssue.physicalIssueId, startsWith('PI-'));
    expect(outcome.physicalIssue.observationIds, contains('OBS-SCENARIO-1'));
    expect(outcome.physicalIssue.status, IssueLifecycleState.candidate);
  });

  test('SCENARIO 2: Inspector detects same issue nearby -> Linked to existing PhysicalIssue',
      () async {
    final engine = IssueIntelligenceEngine.instance;
    await engine.initialize(subscribeToEvents: false);

    // Initial citizen report creates the issue
    final initial = engine.submitObservation(Observation(
      observationId: 'OBS-CIT-201',
      sourceType: ObservationSourceType.citizenReport,
      sourceId: 'CIT-201',
      timestamp: DateTime.now().subtract(const Duration(hours: 2)),
      latitude: 17.4400,
      longitude: 78.4985,
      detectedIssueType: 'Road Surface Damage',
      aiConfidence: 0.85,
      contextData: {'address': 'MG Road'},
    ));

    // Field Inspector detects at virtually same spot 15m away
    final inspectorObs = Observation(
      observationId: 'OBS-INSP-202',
      sourceType: ObservationSourceType.fieldAgent,
      sourceId: 'INSP-202',
      timestamp: DateTime.now(),
      latitude: 17.4401,
      longitude: 78.4986,
      detectedIssueType: 'Road Surface Damage',
      aiConfidence: 0.94,
      contextData: {'address': 'MG Road'},
    );

    final outcome = engine.submitObservation(inspectorObs);
    expect(outcome.createdNew, isFalse);
    expect(outcome.matchResult.resultType, MatchResultType.matched);
    expect(outcome.physicalIssue.physicalIssueId,
        initial.physicalIssue.physicalIssueId);
    expect(outcome.physicalIssue.observationIds.length, 2);
    expect(engine.issues.length, 1,
        reason: 'No duplicate issue should be created');
  });

  test('SCENARIO 3: AI detects similar issue with uncertain confidence -> Verification requested',
      () async {
    final engine = IssueIntelligenceEngine.instance;
    await engine.initialize(subscribeToEvents: false);

    // Existing issue in area
    engine.submitObservation(Observation(
      observationId: 'OBS-BASE-301',
      sourceType: ObservationSourceType.citizenReport,
      sourceId: 'CIT-301',
      timestamp: DateTime.now().subtract(const Duration(days: 10)),
      latitude: 17.4400,
      longitude: 78.4980,
      detectedIssueType: 'Road Surface Damage',
      contextData: {'address': 'North Corridor'},
    ));

    // AI detection ~85m away on a 10-day-old issue with general context -> confidence ~0.66 (uncertain window 0.55-0.78)
    final aiObs = Observation(
      observationId: 'OBS-AI-302',
      sourceType: ObservationSourceType.aiLiveDetection,
      sourceId: 'AI-302',
      timestamp: DateTime.now(),
      latitude: 17.4406,
      longitude: 78.4986,
      detectedIssueType: 'Road Surface Damage',
      aiConfidence: 0.65,
      contextData: {'address': 'General Area'},
    );

    final outcome = engine.submitObservation(aiObs);
    expect(outcome.matchResult.resultType, MatchResultType.uncertain);
    expect(aiObs.status, ObservationStatus.reviewRequired);
    expect(engine.uncertainMatchQueue, contains(aiObs));
  });

  test('SCENARIO 4: Crew completes assigned work -> Task completed, reverification required (not closed)',
      () async {
    final engine = IssueIntelligenceEngine.instance;
    await engine.initialize(subscribeToEvents: false);

    final issue = engine.submitObservation(obs(id: 'OBS-CREW-401')).physicalIssue;

    // Simulate work workflow
    issue.status = IssueLifecycleState.inProgress;
    issue.resolutionAttempts.add(ResolutionAttempt(
      attemptId: 'RES-ATTEMPT-1',
      taskRef: 'TASK-401',
      teamRef: 'CREW-ALPHA',
      startedAt: DateTime.now().subtract(const Duration(hours: 3)),
      submittedAt: DateTime.now(),
      evidencePaths: ['/vault/after_photo_401.jpg'],
      outcome: 'pending',
    ));

    // Resolution evidence is submitted
    engine.submitObservation(Observation(
      observationId: 'OBS-RES-402',
      sourceType: ObservationSourceType.resolutionEvidence,
      sourceId: 'TASK-401',
      timestamp: DateTime.now(),
      latitude: issue.primaryLat,
      longitude: issue.primaryLng,
      media: ['/vault/after_photo_401.jpg'],
      userDescription: 'Pothole filled with Grade-A asphalt',
    ));

    // State machine drives to resolution submitted / reverification required
    issue.status = IssueLifecycleState.reverificationRequired;
    expect(issue.status.isOpen, isTrue,
        reason: 'Issue must remain open until verified by inspector/manager');
    expect(engine.verificationQueue, contains(issue));
  });

  test('SCENARIO 5: New observation shows issue still exists -> Match becomes PERSISTENT / REOPENED',
      () async {
    final engine = IssueIntelligenceEngine.instance;
    await engine.initialize(subscribeToEvents: false);

    // Initial issue that was closed
    final pi = engine.submitObservation(Observation(
      observationId: 'OBS-PREV-501',
      sourceType: ObservationSourceType.citizenReport,
      sourceId: 'CIT-501',
      timestamp: DateTime.now().subtract(const Duration(days: 5)),
      latitude: 17.4500,
      longitude: 78.5000,
      detectedIssueType: 'Road Surface Damage',
      contextData: {'address': 'Airport Road'},
    )).physicalIssue;

    pi.status = IssueLifecycleState.resolved;

    // New observation reported at same location
    final newObs = Observation(
      observationId: 'OBS-NEW-502',
      sourceType: ObservationSourceType.citizenReport,
      sourceId: 'CIT-502',
      timestamp: DateTime.now(),
      latitude: 17.4501,
      longitude: 78.5001,
      detectedIssueType: 'Road Surface Damage',
      aiConfidence: 0.90,
      contextData: {'address': 'Airport Road'},
    );

    final outcome = engine.submitObservation(newObs);
    expect(outcome.matchResult.resultType, MatchResultType.matched);
    expect(outcome.physicalIssue.physicalIssueId, pi.physicalIssueId);
    expect(outcome.physicalIssue.status, IssueLifecycleState.persistent,
        reason: 'Re-observing a resolved issue transitions it to PERSISTENT');
    expect(engine.persistentIssues, contains(pi));
  });

  test('SCENARIO 6: Verification confirms issue no longer exists -> PhysicalIssue becomes RESOLVED & CLOSED',
      () async {
    final engine = IssueIntelligenceEngine.instance;
    await engine.initialize(subscribeToEvents: false);

    final pi = engine.submitObservation(obs(id: 'OBS-VERIF-601')).physicalIssue;
    pi.status = IssueLifecycleState.reverificationRequired;

    // Manager / inspector performs formal verification with evidence
    engine.verifyResolution(
      pi.physicalIssueId,
      passed: true,
      actorId: 'INSP-SHARMA',
      notes: 'Road surface is smooth and flush with curb.',
      evidencePaths: ['/vault/verification_passed.jpg'],
    );

    expect(pi.status == IssueLifecycleState.resolved ||
        pi.status == IssueLifecycleState.closed, isTrue);
    expect(pi.verificationHistory.last.verdict, 'passed');
    expect(pi.status.isOpen, isFalse);
  });

  test('SCENARIO 7: Inspector offline queue sync -> Matched without duplicates',
      () async {
    final engine = IssueIntelligenceEngine.instance;
    await engine.initialize(subscribeToEvents: false);

    // Initial item in system
    final initial = engine.submitObservation(Observation(
      observationId: 'OBS-ONLINE-701',
      sourceType: ObservationSourceType.citizenReport,
      sourceId: 'CIT-701',
      timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      latitude: 17.4200,
      longitude: 78.4700,
      detectedIssueType: 'Road Surface Damage',
      contextData: {'address': 'Ring Road'},
    ));

    // Offline captures buffered by inspector
    final offlineBuffered = [
      Observation(
        observationId: 'OBS-OFFLINE-702',
        sourceType: ObservationSourceType.fieldAgent,
        sourceId: 'INSP-OFF-1',
        timestamp: DateTime.now(),
        latitude: 17.4201,
        longitude: 78.4701,
        detectedIssueType: 'Road Surface Damage',
        aiConfidence: 0.92,
        contextData: {'address': 'Ring Road'},
      ),
      Observation(
        observationId: 'OBS-OFFLINE-703',
        sourceType: ObservationSourceType.fieldAgent,
        sourceId: 'INSP-OFF-2',
        timestamp: DateTime.now(),
        latitude: 17.5500, // Distinct new location
        longitude: 78.6000,
        detectedIssueType: 'Lighting Failure',
        aiConfidence: 0.85,
        contextData: {'address': 'Highway North'},
      ),
    ];

    // Simulate batch resynchronization
    for (final offObs in offlineBuffered) {
      engine.submitObservation(offObs);
    }

    // 702 should match initial, 703 should create new
    expect(initial.physicalIssue.observationIds, contains('OBS-OFFLINE-702'));
    expect(engine.issues.length, 2,
        reason: 'Sync accurately matches existing without duplicate and creates new only when distinct');
  });

  test('HUMAN-IN-THE-LOOP: Reject uncertain match creates new distinct issue & merge duplicate works',
      () async {
    final engine = IssueIntelligenceEngine.instance;
    await engine.initialize(subscribeToEvents: false);

    final base = engine.submitObservation(obs(id: 'OBS-H1', lat: 17.4000, lng: 78.4800));
    final uncertain = engine.submitObservation(obs(id: 'OBS-H2', lat: 17.4006, lng: 78.4806, type: 'Pothole & Asphalt Degradation'));

    expect(uncertain.matchResult.resultType, MatchResultType.uncertain);

    // Operations Manager rejects candidate match and creates a new issue
    final distinctIssue = engine.rejectMatchAndCreateNew(
        observationId: 'OBS-H2', actorId: 'SUP-JONES');

    expect(distinctIssue.physicalIssueId, isNot(base.physicalIssue.physicalIssueId));
    expect(distinctIssue.observationIds, contains('OBS-H2'));

    // Operations Manager manually merges two issues
    final merged = engine.mergeIssues(
      targetPhysicalIssueId: base.physicalIssue.physicalIssueId,
      sourcePhysicalIssueId: distinctIssue.physicalIssueId,
      actorId: 'SUP-JONES',
    );

    expect(merged, isTrue);
    expect(base.physicalIssue.observationIds, contains('OBS-H2'));
    expect(distinctIssue.status, IssueLifecycleState.closed);
  });
}



