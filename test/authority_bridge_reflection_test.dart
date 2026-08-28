import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:infravision/citizen/models/complaint.dart' as citizen;
import 'package:infravision/citizen/repository/complaint_repository.dart';
import 'package:infravision/citizen/repository/local_complaint_data_source.dart';
import 'package:infravision/models/case_item.dart';
import 'package:infravision/models/complaint_item.dart' as legacy;
import 'package:infravision/repositories/app_storage.dart';
import 'package:infravision/repositories/authority_bridge_service.dart';

/// Proves the two-way AuthorityBridgeService really reflects authority-side
/// actions into the citizen lifecycle (My Reports / Nearby Issues / Community
/// Hub / notifications) and citizen uploads into the supervisor workspace.
///
/// Runs fully hermetic: both stores are redirected to a throw-away temp
/// directory so real user data and sibling test suites stay untouched.
Directory? sandbox;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sandbox = await Directory.systemTemp.createTemp('infravision_bridge_');
    AppStorage.baseDirectoryOverride = sandbox;
    LocalComplaintDataSource.baseDirectoryOverride = sandbox;
  });

  tearDownAll(() async {
    try {
      await sandbox?.delete(recursive: true);
    } catch (_) {}
    AppStorage.baseDirectoryOverride = null;
    LocalComplaintDataSource.baseDirectoryOverride = null;
  });

  test('inspector log + work-order stages reflect into citizen lifecycle',
      () async {
    // Real boot order: storage (bridge primed) -> citizen repository.
    await AppStorage.instance.initialize();
    await ComplaintRepository.instance.initialize(seed: false);
    final repo = ComplaintRepository.instance;

    final inspectorLog = legacy.ComplaintItem(
      id: 'CMP-TEST-777',
      title: 'Broken streetlight at junction',
      category: 'Street Lighting',
      zone: 'Zone 9, Test City',
      severity: legacy.ComplaintSeverity.high,
      severityScore: 0.8,
      status: legacy.ComplaintStatus.submitted,
      createdAt: DateTime.now(),
      slaDeadline: DateTime.now().add(const Duration(days: 2)),
      gpsCoordinates: '17.4321\u00B0 N, 78.5210\u00B0 E',
      inspectorNotes: 'Pole dark since Monday.',
    );

    AuthorityBridgeService.instance.mirrorInspectorLog(inspectorLog);

    final twin = repo.complaints
        .firstWhere((c) => c.sourceRef == 'CMP-TEST-777');
    expect(twin.status, citizen.ComplaintStatus.departmentAssigned);
    expect(twin.timeline.length, 4);
    expect(twin.timeline.first.title, 'Report Submitted');
    // Legacy model resolves the owning department via its own router, so we
    // only assert that a concrete department reached the citizen twin.
    expect(twin.assignedDepartment, isNotEmpty);

    // Supervisor dispatches through the REAL portal path — dispatchWorkOrder
    // creates the CaseItem, links it, and mirrors the assignment to the twin.
    final workOrder = await AppStorage.instance.dispatchWorkOrder(
      complaint: inspectorLog,
      assignedTeam: 'Crew-12',
      assignedEngineer: 'Duty Engineer',
    );
    expect(twin.assignedCrewId, 'Crew-12');
    expect(twin.status.order,
        greaterThanOrEqualTo(citizen.ComplaintStatus.repairTeamAssigned.order));

    // Crew reports stage progression via AppStorage.updateCaseStatus.
    await AppStorage.instance
        .updateCaseStatus(workOrder.id, CaseStatus.repairCompleted);
    expect(twin.status, citizen.ComplaintStatus.repairCompleted);

    // Inspector closes/verifies: resolution proof reaches the citizen.
    AuthorityBridgeService.instance.reflectClosure(
      workOrder,
      verificationPassed: true,
      afterEvidencePath: '/evidence/images/after.png',
    );
    expect(twin.status, citizen.ComplaintStatus.citizenConfirmation);
    expect(twin.resolutionEvidence.any((e) => e.path.contains('after.png')),
        isTrue);
    expect(twin.timeline.last.title, contains('Confirmation'));
  });

  test('synced citizen case is absorbed into the supervisor workspace',
      () async {
    await AppStorage.instance.initialize();

    // Real reverse path: bridge sink -> AppStorage endpoint.
    AppStorage.instance.absorbCitizenUpload(MirrorPayload(
      id: 'REP-SYNC-42',
      caseId: 'IRV-000042',
      title: 'Pothole on main road',
      category: 'Roads & Potholes',
      description: 'Deep pothole near bus stop',
      severityName: 'high',
      severityScore: 0.8,
      latitude: 17.41,
      longitude: 78.49,
      address: 'Zone 3, Main Road',
      images: const [],
      createdAtIso: DateTime.now().toIso8601String(),
    ));

    final absorbed = AppStorage.instance.complaintsList
        .firstWhere((c) => c.linkedCaseId == 'IRV-000042');
    expect(absorbed.category, 'Roads & Potholes');
    expect(absorbed.severity, legacy.ComplaintSeverity.high);

    // Idempotent: re-delivery must not duplicate.
    AppStorage.instance.absorbCitizenUpload(MirrorPayload(
      id: 'REP-SYNC-42',
      caseId: 'IRV-000042',
      title: 'Pothole on main road',
      category: 'Roads & Potholes',
      description: 'Deep pothole near bus stop',
      severityName: 'high',
      severityScore: 0.8,
      latitude: 17.41,
      longitude: 78.49,
      address: 'Zone 3, Main Road',
      images: const [],
      createdAtIso: DateTime.now().toIso8601String(),
    ));
    expect(
      AppStorage.instance.complaintsList
          .where((c) => c.linkedCaseId == 'IRV-000042')
          .length,
      1,
    );
  });
}
