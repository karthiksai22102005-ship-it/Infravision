import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../models/case_item.dart';
import '../models/complaint_item.dart';
import '../models/defect_entity.dart';
import '../models/evidence_item.dart';
import '../models/monitoring_event.dart';

/// Central Local-First Storage & Repository Manager for InfraVision.
class AppStorage extends ChangeNotifier {
  AppStorage._();
  static final AppStorage instance = AppStorage._();

  bool _isInitialized = false;
  late final Directory _evidenceImagesDir;
  late final Directory _evidenceVideosDir;
  late final Directory _metadataDir;

  final List<EvidenceItem> _evidenceList = [];
  final List<ComplaintItem> _complaintsList = [];
  final List<CaseItem> _casesList = [];
  final List<DefectEntity> _defectsList = [];
  final List<MonitoringEvent> _eventsList = [];

  List<EvidenceItem> get evidenceList => List.unmodifiable(_evidenceList);
  List<ComplaintItem> get complaintsList => List.unmodifiable(_complaintsList);
  List<CaseItem> get casesList => List.unmodifiable(_casesList);
  List<DefectEntity> get defectsList => List.unmodifiable(_defectsList);
  List<MonitoringEvent> get eventsList => List.unmodifiable(_eventsList);

  int get openComplaintsCount =>
      _complaintsList.where((c) => c.status != ComplaintStatus.resolved).length;
  int get activeCasesCount =>
      _casesList.where((c) => c.status != CaseStatus.resolved).length;
  int get overdueSlaCount =>
      _casesList.where((c) => c.isOverdue).length +
      _complaintsList.where((c) => c.isOverdue).length;
  int get resolvedRepairsCount =>
      _casesList.where((c) => c.status == CaseStatus.resolved).length;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final baseDir = _getBaseDirectory();
      _evidenceImagesDir = Directory('${baseDir.path}/evidence/images');
      _evidenceVideosDir = Directory('${baseDir.path}/evidence/videos');
      _metadataDir = Directory('${baseDir.path}/metadata');

      await _evidenceImagesDir.create(recursive: true);
      await _evidenceVideosDir.create(recursive: true);
      await _metadataDir.create(recursive: true);

      await _loadPersistedData();
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('AppStorage init error: $e');
      _bootstrapDefaultSampleData();
      _isInitialized = true;
    }
  }

  Directory _getBaseDirectory() {
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['APPDATA'] ??
          'C:/Users/Dell/AppData/Local';
      return Directory('$localAppData/InfraVision');
    }
    return Directory.systemTemp.createTempSync('infravision_');
  }

  Future<void> _loadPersistedData() async {
    final compFile = File('${_metadataDir.path}/complaints.json');
    if (await compFile.exists()) {
      final content = await compFile.readAsString();
      final List<dynamic> list = jsonDecode(content) as List<dynamic>;
      _complaintsList.clear();
      _complaintsList.addAll(list.map((e) => ComplaintItem.fromJson(e as Map<String, dynamic>)));
    }

    final caseFile = File('${_metadataDir.path}/cases.json');
    if (await caseFile.exists()) {
      final content = await caseFile.readAsString();
      final List<dynamic> list = jsonDecode(content) as List<dynamic>;
      _casesList.clear();
      _casesList.addAll(list.map((e) => CaseItem.fromJson(e as Map<String, dynamic>)));
    }

    final evFile = File('${_metadataDir.path}/evidence.json');
    if (await evFile.exists()) {
      final content = await evFile.readAsString();
      final List<dynamic> list = jsonDecode(content) as List<dynamic>;
      _evidenceList.clear();
      _evidenceList.addAll(list.map((e) => EvidenceItem.fromJson(e as Map<String, dynamic>)));
    }

    final defFile = File('${_metadataDir.path}/defects.json');
    if (await defFile.exists()) {
      final content = await defFile.readAsString();
      final List<dynamic> list = jsonDecode(content) as List<dynamic>;
      _defectsList.clear();
      _defectsList.addAll(list.map((e) => DefectEntity.fromJson(e as Map<String, dynamic>)));
    }

    final evtFile = File('${_metadataDir.path}/events.json');
    if (await evtFile.exists()) {
      final content = await evtFile.readAsString();
      final List<dynamic> list = jsonDecode(content) as List<dynamic>;
      _eventsList.clear();
      _eventsList.addAll(list.map((e) => MonitoringEvent.fromJson(e as Map<String, dynamic>)));
    }

    if (_complaintsList.isEmpty && _casesList.isEmpty) {
      _bootstrapDefaultSampleData();
    } else if (_eventsList.isEmpty) {
      _eventsList.add(
        MonitoringEvent(
          id: 'EVT-INIT',
          timestamp: DateTime.now(),
          title: 'System Initialized',
          subtitle: 'InfraVision monitoring engine ready.',
          category: 'camera',
          colorHex: 0xFF10B981,
          iconCode: 0xe6a5,
        ),
      );
    }
  }

  void _bootstrapDefaultSampleData() {
    final now = DateTime.now();

    final c1 = ComplaintItem(
      id: 'CMP-2026-0842',
      title: 'Glass Panel Structural Shatter / Fracture',
      category: 'Glass & Solar Assets',
      zone: 'Campus Solar Array Block D - Row 4',
      severity: ComplaintSeverity.critical,
      severityScore: 0.94,
      status: ComplaintStatus.dispatched,
      createdAt: now.subtract(const Duration(hours: 4)),
      slaDeadline: now.add(const Duration(hours: 20)),
      inspectorNotes: 'Impact fracture spreading across PV matrix. Immediate replacement required.',
      department: 'Electrical & Solar Wing',
    );

    final c2 = ComplaintItem(
      id: 'CMP-2026-0839',
      title: 'Structural Concrete Crack & Rebar Exposure',
      category: 'Concrete & Structural',
      zone: 'North Wing Overpass Pillar #12',
      severity: ComplaintSeverity.high,
      severityScore: 0.86,
      status: ComplaintStatus.dispatched,
      createdAt: now.subtract(const Duration(hours: 14)),
      slaDeadline: now.add(const Duration(hours: 34)),
      inspectorNotes: 'Diagonal shear crack > 4mm with water seepage. PWD structural epoxy injection recommended.',
      department: 'Civil Maintenance Wing',
    );

    final c3 = ComplaintItem(
      id: 'CMP-2026-0835',
      title: 'Deep Asphalt Pothole Displacement (D40)',
      category: 'Road & Pavement Hazards',
      zone: 'West Perimeter Access Road KM 2.4',
      severity: ComplaintSeverity.high,
      severityScore: 0.82,
      status: ComplaintStatus.submitted,
      createdAt: now.subtract(const Duration(hours: 2)),
      slaDeadline: now.add(const Duration(hours: 46)),
      inspectorNotes: 'Cavity depth > 60mm causing vehicle tire impact hazard.',
      department: 'Public Works Department (PWD)',
    );

    _complaintsList.addAll([c1, c2, c3]);

    final case1 = CaseItem(
      id: 'CASE-2026-1044',
      complaintId: c1.id,
      title: 'Emergency Solar Module Replacement - Block D',
      department: 'Electrical & Solar Wing',
      assignedTeam: 'Solar Maintenance Team Alpha',
      status: CaseStatus.inProgress,
      priority: 'Critical (24h)',
      beforeEvidencePath: '',
      createdAt: now.subtract(const Duration(hours: 3)),
      slaDeadline: now.add(const Duration(hours: 21)),
      assignedEngineer: 'Er. Sandeep Verma',
    );

    final case2 = CaseItem(
      id: 'CASE-2026-1041',
      complaintId: c2.id,
      title: 'Overpass Pillar #12 Epoxy Pressure Grouting',
      department: 'Civil Maintenance Wing',
      assignedTeam: 'Heavy Structural Crew #3',
      status: CaseStatus.assigned,
      priority: 'High (48h)',
      beforeEvidencePath: '',
      createdAt: now.subtract(const Duration(hours: 12)),
      slaDeadline: now.add(const Duration(hours: 36)),
      assignedEngineer: 'Er. R. K. Nair',
    );

    _casesList.addAll([case1, case2]);

    _eventsList.addAll([
      MonitoringEvent(
        id: 'EVT-1001',
        timestamp: now.subtract(const Duration(minutes: 5)),
        title: 'Real-time Camera Initialized',
        subtitle: 'Standby mode verified. DirectShow DirectML capture ready.',
        category: 'camera',
        colorHex: 0xFF10B981,
        iconCode: 0xe6a5, // videocam
      ),
      MonitoringEvent(
        id: 'EVT-1002',
        timestamp: now.subtract(const Duration(hours: 3)),
        title: 'Work Order Dispatched: CASE-1044',
        subtitle: 'Solar Maintenance Team Alpha dispatched to Block D.',
        category: 'case',
        colorHex: 0xFF4F46E5,
        iconCode: 0xe0cd, // assignment
      ),
      MonitoringEvent(
        id: 'EVT-1003',
        timestamp: now.subtract(const Duration(hours: 4)),
        title: 'Critical Complaint Logged: CMP-2026-0842',
        subtitle: 'Glass Panel Shatter classified with 94% confidence.',
        category: 'complaint',
        colorHex: 0xFFEF4444,
        iconCode: 0xe6e4, // warning
      ),
    ]);

    _saveAll();
  }

  Future<EvidenceItem> saveEvidenceFile({
    required File file,
    required String source,
    required String resolution,
    required String qualityGrade,
    String? gpsLocation,
    String? linkedComplaintId,
  }) async {
    final timestamp = DateTime.now();
    final bytes = await file.readAsBytes();
    final hash = sha256.convert(bytes).toString();

    final ext = file.path.split('.').last;
    final destFileName = 'EV_${timestamp.millisecondsSinceEpoch}_${hash.substring(0, 8)}.$ext';
    final destPath = '${_evidenceImagesDir.path}/$destFileName';

    await file.copy(destPath);

    final item = EvidenceItem(
      id: 'EV-${timestamp.millisecondsSinceEpoch.toString().substring(6)}',
      filePath: destPath,
      timestamp: timestamp,
      source: source,
      resolution: resolution,
      qualityGrade: qualityGrade,
      sha256Hash: hash,
      gpsLocation: gpsLocation,
      linkedComplaintId: linkedComplaintId,
    );

    _evidenceList.insert(0, item);
    await _saveAll();

    logEvent(
      title: 'Evidence Captured: ${item.id}',
      subtitle: '$resolution image stored in local vault (SHA: ${hash.substring(0, 8)}).',
      category: 'evidence',
      colorHex: 0xFF0284C7,
      iconCode: 0xe104, // camera
    );

    notifyListeners();
    return item;
  }

  Future<ComplaintItem> logComplaint({
    required String title,
    required String category,
    required String zone,
    required ComplaintSeverity severity,
    required double severityScore,
    required List<String> evidencePaths,
    String inspectorNotes = '',
    String? gpsCoordinates,
    String department = 'Public Works Department (PWD)',
  }) async {
    final now = DateTime.now();
    final duration = severity == ComplaintSeverity.critical
        ? const Duration(hours: 24)
        : (severity == ComplaintSeverity.high ? const Duration(hours: 48) : const Duration(days: 7));

    final id = 'CMP-2026-${(1000 + _complaintsList.length + 1).toString().padLeft(4, '0')}';

    final complaint = ComplaintItem(
      id: id,
      title: title,
      category: category,
      zone: zone,
      severity: severity,
      severityScore: severityScore,
      status: ComplaintStatus.submitted,
      createdAt: now,
      slaDeadline: now.add(duration),
      evidencePaths: evidencePaths,
      inspectorNotes: inspectorNotes,
      gpsCoordinates: gpsCoordinates,
      department: department,
    );

    _complaintsList.insert(0, complaint);

    // Also register in Defect Entity table
    final defect = DefectEntity(
      defectId: 'INV-D-${(1000 + _defectsList.length + 1)}',
      name: title,
      domain: category,
      defectType: category,
      severity: severity.displayName,
      severityScore: severityScore,
      firstSeen: now,
      lastSeen: now,
      observationCount: 1,
      location: zone,
      status: 'Active',
      primaryEvidencePath: evidencePaths.isNotEmpty ? evidencePaths.first : '',
      gpsCoordinates: gpsCoordinates,
      linkedComplaintId: id,
    );
    _defectsList.insert(0, defect);

    logEvent(
      title: 'New Complaint Logged: $id',
      subtitle: '$title at $zone ($department).',
      category: 'complaint',
      colorHex: severity == ComplaintSeverity.critical ? 0xFFEF4444 : 0xFFF59E0B,
      iconCode: 0xe425, // report_problem
    );

    await _saveAll();
    notifyListeners();
    return complaint;
  }

  Future<CaseItem> dispatchWorkOrder({
    required ComplaintItem complaint,
    required String assignedTeam,
    required String assignedEngineer,
  }) async {
    final now = DateTime.now();
    complaint.status = ComplaintStatus.dispatched;

    final caseId = 'CASE-2026-${(1000 + _casesList.length + 1)}';
    complaint.linkedCaseId = caseId;

    final workOrder = CaseItem(
      id: caseId,
      complaintId: complaint.id,
      title: complaint.title,
      department: complaint.department,
      assignedTeam: assignedTeam,
      status: CaseStatus.assigned,
      priority: '${complaint.severity.displayName} SLA',
      beforeEvidencePath: complaint.evidencePaths.isNotEmpty ? complaint.evidencePaths.first : '',
      createdAt: now,
      slaDeadline: complaint.slaDeadline,
      assignedEngineer: assignedEngineer,
    );

    _casesList.insert(0, workOrder);

    logEvent(
      title: 'Work Order Dispatched: $caseId',
      subtitle: 'Assigned to $assignedTeam ($assignedEngineer).',
      category: 'case',
      colorHex: 0xFF4F46E5,
      iconCode: 0xe0cd, // assignment
    );

    await _saveAll();
    notifyListeners();
    return workOrder;
  }

  Future<void> verifyAndCloseCase({
    required CaseItem workOrder,
    required String afterEvidencePath,
    required String verificationNotes,
  }) async {
    final now = DateTime.now();
    workOrder.status = CaseStatus.resolved;
    workOrder.afterEvidencePath = afterEvidencePath;
    workOrder.verificationNotes = verificationNotes;
    workOrder.verificationPassed = true;
    workOrder.resolvedAt = now;

    final compIdx = _complaintsList.indexWhere((c) => c.id == workOrder.complaintId);
    if (compIdx != -1) {
      _complaintsList[compIdx].status = ComplaintStatus.resolved;
    }

    logEvent(
      title: 'Case Verified & Closed: ${workOrder.id}',
      subtitle: 'Post-repair photo inspection passed. Defect resolved.',
      category: 'verification',
      colorHex: 0xFF10B981,
      iconCode: 0xe86c, // verified
    );

    await _saveAll();
    notifyListeners();
  }

  void logEvent({
    required String title,
    required String subtitle,
    required String category,
    required int colorHex,
    required int iconCode,
  }) {
    final event = MonitoringEvent(
      id: 'EVT-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: DateTime.now(),
      title: title,
      subtitle: subtitle,
      category: category,
      colorHex: colorHex,
      iconCode: iconCode,
    );
    _eventsList.insert(0, event);
    notifyListeners();
  }

  Future<void> _saveAll() async {
    try {
      await File('${_metadataDir.path}/complaints.json')
          .writeAsString(jsonEncode(_complaintsList.map((e) => e.toJson()).toList()));
      await File('${_metadataDir.path}/cases.json')
          .writeAsString(jsonEncode(_casesList.map((e) => e.toJson()).toList()));
      await File('${_metadataDir.path}/evidence.json')
          .writeAsString(jsonEncode(_evidenceList.map((e) => e.toJson()).toList()));
      await File('${_metadataDir.path}/defects.json')
          .writeAsString(jsonEncode(_defectsList.map((e) => e.toJson()).toList()));
      await File('${_metadataDir.path}/events.json')
          .writeAsString(jsonEncode(_eventsList.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('Error saving metadata: $e');
    }
  }
}
