import 'package:flutter_test/flutter_test.dart';
import 'package:infravision/models/case_item.dart';
import 'package:infravision/models/complaint_item.dart';
import 'package:infravision/repositories/app_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Complaint & Storage Repository Tests', () {
    test('AppStorage initializes with sample complaints and work orders', () async {
      final storage = AppStorage.instance;
      await storage.initialize();

      expect(storage.complaintsList.isNotEmpty, isTrue);
      expect(storage.casesList.isNotEmpty, isTrue);
      expect(storage.eventsList.isNotEmpty, isTrue);
    });

    test('Logs a new complaint and registers a Defect Entity', () async {
      final storage = AppStorage.instance;
      await storage.initialize();

      final complaint = await storage.logComplaint(
        title: 'Road Pothole Fracture Test',
        category: 'Road & Pavement Hazards',
        zone: 'Campus Sector A',
        severity: ComplaintSeverity.critical,
        severityScore: 0.95,
        evidencePaths: ['test_evidence.jpg'],
        inspectorNotes: 'High priority road hazard.',
      );

      expect(complaint.id.startsWith('CMP-'), isTrue);
      expect(complaint.status, ComplaintStatus.submitted);
      expect(storage.complaintsList.any((c) => c.id == complaint.id), isTrue);
      expect(storage.defectsList.any((d) => d.name == complaint.title), isTrue);
    });

    test('Dispatches work order and links complaint', () async {
      final storage = AppStorage.instance;
      await storage.initialize();

      final complaint = storage.complaintsList.first;
      final workOrder = await storage.dispatchWorkOrder(
        complaint: complaint,
        assignedTeam: 'Civil Strike Team 1',
        assignedEngineer: 'Er. Test Engineer',
      );

      expect(workOrder.id.startsWith('CASE-'), isTrue);
      expect(complaint.status, ComplaintStatus.dispatched);
      expect(complaint.linkedCaseId, workOrder.id);
    });

    test('Verifies repair with Before vs After photo and closes case', () async {
      final storage = AppStorage.instance;
      await storage.initialize();

      final workOrder = storage.casesList.first;
      await storage.verifyAndCloseCase(
        workOrder: workOrder,
        afterEvidencePath: 'post_repair_photo.jpg',
        verificationNotes: 'Site clear and road resurfaced.',
      );

      expect(workOrder.status, CaseStatus.resolved);
      expect(workOrder.verificationPassed, isTrue);
    });
  });
}
