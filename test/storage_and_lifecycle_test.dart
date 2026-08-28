import 'package:flutter_test/flutter_test.dart';
import 'package:infravision/models/complaint_item.dart';
import 'package:infravision/models/case_item.dart';
import 'package:infravision/models/evidence_item.dart';
import 'package:infravision/repositories/app_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AppStorage.instance.initialize();
  });

  group('Infrastructure Defect Lifecycle & Storage Tests', () {
    test('AppStorage initializes with seed data and reactive streams', () {
      final storage = AppStorage.instance;
      expect(storage.complaintsList.isNotEmpty, isTrue);
      expect(storage.casesList.isNotEmpty, isTrue);
      expect(storage.evidenceList.isNotEmpty, isTrue);
      expect(storage.eventsList.isNotEmpty, isTrue);
    });

    test('Complaint logging lifecycle updates reactive complaints list', () async {
      final storage = AppStorage.instance;
      final initialCount = storage.complaintsList.length;

      final newComplaint = await storage.logComplaint(
        title: 'Deep Transverse Crack on Ring Road Junction',
        category: 'Cracks',
        zone: 'Zone 1 - East Corridor',
        severity: ComplaintSeverity.high,
        severityScore: 0.82,
        inspectorNotes: 'Observed during routine mobile LIDAR/camera sweep.',
        gpsCoordinates: '12.9734° N, 77.5982° E',
        department: 'Highways & Pavement Wing',
      );

      expect(storage.complaintsList.length, equals(initialCount + 1));
      expect(newComplaint.id.startsWith('CMP-'), isTrue);
      expect(newComplaint.status, equals(ComplaintStatus.submitted));
      expect(newComplaint.department, equals('Highways & Pavement Wing'));
    });

    test('Work Order dispatching converts complaint to dispatched and creates CaseItem', () async {
      final storage = AppStorage.instance;

      final complaint = await storage.logComplaint(
        title: 'Manhole Cover Displacement on Main Avenue',
        category: 'Manhole / Drainage',
        zone: 'Zone 3 - Metro Sector',
        severity: ComplaintSeverity.critical,
        severityScore: 0.95,
        inspectorNotes: 'Dislodged cover posing immediate road hazard.',
        gpsCoordinates: '12.9810° N, 77.6045° E',
      );

      final initialCaseCount = storage.casesList.length;

      final workOrder = await storage.dispatchWorkOrder(
        complaint: complaint,
        assignedEngineer: 'Er. Rajesh Varma (PWD Grade-1)',
        assignedTeam: 'Rapid Response Unit 04',
      );

      expect(storage.casesList.length, equals(initialCaseCount + 1));
      expect(workOrder.complaintId, equals(complaint.id));
      expect(workOrder.assignedEngineer, equals('Er. Rajesh Varma (PWD Grade-1)'));

      // Check complaint status update
      final updatedComplaint = storage.complaintsList.firstWhere((c) => c.id == complaint.id);
      expect(updatedComplaint.status, equals(ComplaintStatus.dispatched));
      expect(updatedComplaint.linkedCaseId, equals(workOrder.id));
    });

    test('Forensic Verification and Case Closure marks status as resolved', () async {
      final storage = AppStorage.instance;

      final complaint = await storage.logComplaint(
        title: 'Damaged Guardrail on Overpass 4',
        category: 'Guardrails',
        zone: 'Zone 4 - Flyover Corridor',
        severity: ComplaintSeverity.moderate,
        severityScore: 0.60,
      );

      final workOrder = await storage.dispatchWorkOrder(
        complaint: complaint,
        assignedEngineer: 'Er. Anita Rao',
        assignedTeam: 'Overpass Maintenance Div',
      );

      await storage.verifyAndCloseCase(
        workOrder: workOrder,
        afterEvidencePath: 'evidence/images/after_repair_01.jpg',
        verificationPassed: true,
        verificationNotes: 'Double-checked anchor bolts and tensile strength. Fully compliant with IRC:SP:84.',
      );

      final closedCase = storage.casesList.firstWhere((c) => c.id == workOrder.id);
      expect(closedCase.status, equals(CaseStatus.resolved));
      expect(closedCase.verificationPassed, isTrue);

      final closedComplaint = storage.complaintsList.firstWhere((c) => c.id == complaint.id);
      expect(closedComplaint.status, equals(ComplaintStatus.resolved));
    });

    test('Evidence item JSON serializes and deserializes cleanly with SHA-256 hash', () {
      final evidence = EvidenceItem(
        id: 'EVD-2026-TEST01',
        filePath: 'evidence/images/test_capture.jpg',
        timestamp: DateTime(2026, 8, 21, 14, 0, 0),
        source: 'Edge Front Camera (4K Sensor)',
        resolution: '3840x2160',
        qualityGrade: 'A (High Clarity)',
        sha256Hash: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        gpsLocation: '12.9716° N, 77.5946° E',
      );

      final json = evidence.toJson();
      final revived = EvidenceItem.fromJson(json);

      expect(revived.id, equals(evidence.id));
      expect(revived.sha256Hash, equals(evidence.sha256Hash));
      expect(revived.qualityGrade, equals('A (High Clarity)'));
      expect(revived.gpsLocation, equals('12.9716° N, 77.5946° E'));
    });
  });
}
