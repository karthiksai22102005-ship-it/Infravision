import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../models/case_item.dart';
import '../models/complaint_item.dart';
import '../models/defect_entity.dart';
import '../models/evidence_item.dart';
import '../models/monitoring_event.dart';
import '../intelligence/issue_intelligence_engine.dart';
import '../field/field_orchestrator.dart';
import 'authority_bridge_service.dart';

/// Central Local-First Storage & Repository Manager for InfraVision.
class AppStorage extends ChangeNotifier {
  AppStorage._();
  static final AppStorage instance = AppStorage._();

  bool _isInitialized = false;
  int _mirrorSeq = 90001;
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

    // Register the citizen<->authority reverse-mirror endpoint early so any
    // synced citizen report is absorbed even before portals are opened.
    AuthorityBridgeService.instance.registerPortalSink(absorbCitizenUpload);

        // Prime the domain-independent ISSUE INTELLIGENCE ENGINE — it subscribes
    // to the shared complaint event bus and correlates every portal input
    // into persistent PhysicalIssues automatically.
    await IssueIntelligenceEngine.instance.initialize();

    // Prime the FIELD INTELLIGENCE orchestrator: registers all source
    // adapters, boots the processing pipeline and the IoT layer so Live CV
    // Sweep, Batch Route, Offline Queue and Checklist feed the same
    // observation -> correlation -> lifecycle pipeline.
    await FieldOrchestrator.instance.initialize();

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

  /// Test-only redirection of the whole InfraVision store (hermetic tests).
  @visibleForTesting
  static Directory? baseDirectoryOverride;

  Directory _getBaseDirectory() {
    final override = baseDirectoryOverride;
    if (override != null) return override;
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['APPDATA'] ??
          'C:/Users/Dell/AppData/Local';
      return Directory('$localAppData/InfraVision');
    }
    // Android & other mobile platforms: use persistent app documents dir
    final appDir = Directory('${Directory.systemTemp.parent.path}/app_flutter/InfraVision');
    if (!appDir.existsSync()) {
      try {
        appDir.createSync(recursive: true);
        return appDir;
      } catch (_) {}
    } else {
      return appDir;
    }
    return Directory('${Directory.systemTemp.path}/infravision_data');
  }

  Future<void> _loadPersistedData() async {
    final compFile = File('${_metadataDir.path}/complaints.json');
    if (await compFile.exists()) {
      try {
        final content = await compFile.readAsString();
        final List<dynamic> list = jsonDecode(content) as List<dynamic>;
        _complaintsList.clear();
        _complaintsList.addAll(list.map((e) => ComplaintItem.fromJson(e as Map<String, dynamic>)));

        // If complaints were filled with repetitive test duplicates, refresh with rich realistic seed
        final uniqueTitles = _complaintsList.map((c) => c.title).toSet();
        if (_complaintsList.length > 3 && uniqueTitles.length <= 1) {
          _complaintsList.clear();
          _casesList.clear();
          _bootstrapDefaultSampleData();
          return;
        }
      } catch (_) {
        _bootstrapDefaultSampleData();
      }
    }

    final caseFile = File('${_metadataDir.path}/cases.json');
    if (await caseFile.exists()) {
      try {
        final content = await caseFile.readAsString();
        final List<dynamic> list = jsonDecode(content) as List<dynamic>;
        _casesList.clear();
        _casesList.addAll(list.map((e) => CaseItem.fromJson(e as Map<String, dynamic>)));

        // If cases contain repetitive identical titles from older runs, refresh with rich seed
        final uniqueCaseTitles = _casesList.map((c) => c.title).toSet();
        if (_casesList.length > 2 && uniqueCaseTitles.length <= 1) {
          _casesList.clear();
          _bootstrapDefaultSampleData();
        }
      } catch (_) {}
    }

    final evFile = File('${_metadataDir.path}/evidence.json');
    if (await evFile.exists()) {
      try {
        final content = await evFile.readAsString();
        final List<dynamic> list = jsonDecode(content) as List<dynamic>;
        _evidenceList.clear();
        _evidenceList.addAll(list.map((e) => EvidenceItem.fromJson(e as Map<String, dynamic>)));
      } catch (_) {}
    }

    final defFile = File('${_metadataDir.path}/defects.json');
    if (await defFile.exists()) {
      try {
        final content = await defFile.readAsString();
        final List<dynamic> list = jsonDecode(content) as List<dynamic>;
        _defectsList.clear();
        _defectsList.addAll(list.map((e) => DefectEntity.fromJson(e as Map<String, dynamic>)));
      } catch (_) {}
    }

    final evtFile = File('${_metadataDir.path}/events.json');
    if (await evtFile.exists()) {
      try {
        final content = await evtFile.readAsString();
        final List<dynamic> list = jsonDecode(content) as List<dynamic>;
        _eventsList.clear();
        _eventsList.addAll(list.map((e) => MonitoringEvent.fromJson(e as Map<String, dynamic>)));
      } catch (_) {}
    }

    if (_complaintsList.isEmpty && _casesList.isEmpty) {
      _bootstrapDefaultSampleData();
    } else {
      if (_evidenceList.isEmpty) {
        _evidenceList.addAll([
          EvidenceItem(
            id: 'EVD-2026-001',
            filePath: 'assets/sample_before.jpg',
            timestamp: DateTime.now().subtract(const Duration(hours: 4)),
            source: 'Edge Front Camera (4K Sensor)',
            resolution: '3840x2160',
            qualityGrade: 'A (High Clarity)',
            sha256Hash: 'a8f3b29c512d7e8b9a0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a',
            gpsLocation: '17.3850° N, 78.4867° E',
          ),
          EvidenceItem(
            id: 'EVD-2026-002',
            filePath: 'assets/sample_after.jpg',
            timestamp: DateTime.now().subtract(const Duration(hours: 12)),
            source: 'Mobile Inspection Terminal',
            resolution: '1920x1080',
            qualityGrade: 'A+ (Forensic Grade)',
            sha256Hash: 'b9e4c30d623e8f9c0b1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2b3c',
            gpsLocation: '17.3865° N, 78.4878° E',
          ),
        ]);
      }
      if (_eventsList.isEmpty) {
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
  }

  void _bootstrapDefaultSampleData() {
    final now = DateTime.now();

    final c1 = ComplaintItem(
      id: 'CMP-2026-101',
      title: 'Severe Asphalt Pothole Cavity (Depth 8.4cm)',
      category: 'Road & Pavement Hazards',
      zone: 'Sector A • Academic Quad Road',
      severity: ComplaintSeverity.critical,
      severityScore: 0.94,
      status: ComplaintStatus.dispatched,
      createdAt: now.subtract(const Duration(hours: 4)),
      slaDeadline: now.add(const Duration(hours: 20)),
      inspectorNotes: 'High-impact cavity causing wheel deflection. Asphalt sub-base eroded.',
      department: 'Public Works Department (PWD)',
      gpsCoordinates: '17.3850° N, 78.4867° E',
    );

    final c2 = ComplaintItem(
      id: 'CMP-2026-102',
      title: 'Longitudinal Structural Concrete Fracture',
      category: 'Concrete & Structural',
      zone: 'Sector B • North Overpass Pillar #12',
      severity: ComplaintSeverity.high,
      severityScore: 0.88,
      status: ComplaintStatus.dispatched,
      createdAt: now.subtract(const Duration(hours: 12)),
      slaDeadline: now.add(const Duration(hours: 36)),
      inspectorNotes: 'Diagonal crack > 12mm with moisture seepage. High-pressure epoxy grouting required.',
      department: 'Civil Maintenance Wing',
      gpsCoordinates: '17.3865° N, 78.4878° E',
    );

    final c3 = ComplaintItem(
      id: 'CMP-2026-103',
      title: 'Damaged LED Traffic Caution Signboard & Pole Tilt',
      category: 'Road Infrastructure',
      zone: 'Sector C • Library Central Circle',
      severity: ComplaintSeverity.moderate,
      severityScore: 0.76,
      status: ComplaintStatus.triaged,
      createdAt: now.subtract(const Duration(hours: 8)),
      slaDeadline: now.add(const Duration(hours: 64)),
      inspectorNotes: 'Signboard mount compromised due to vehicle scrape. Night visibility impaired.',
      department: 'Electrical & Traffic Wing',
      gpsCoordinates: '17.3842° N, 78.4851° E',
    );

    final c4 = ComplaintItem(
      id: 'CMP-2026-104',
      title: 'Blocked Stormwater Drainage Sump & Surface Ponding',
      category: 'Drainage & Public Health',
      zone: 'Sector D • Hostel Complex Sector B',
      severity: ComplaintSeverity.high,
      severityScore: 0.84,
      status: ComplaintStatus.submitted,
      createdAt: now.subtract(const Duration(hours: 2)),
      slaDeadline: now.add(const Duration(hours: 46)),
      inspectorNotes: 'Debris obstruction in culvert throat causing 15cm standing water across carriageway.',
      department: 'Municipal Drainage Division',
      gpsCoordinates: '17.3878° N, 78.4886° E',
    );

    final c5 = ComplaintItem(
      id: 'CMP-2026-105',
      title: 'Alligator Pattern Fatigue Cracking on Asphalt',
      category: 'Road & Pavement Hazards',
      zone: 'Sector A • West Perimeter Highway KM 3.2',
      severity: ComplaintSeverity.moderate,
      severityScore: 0.79,
      status: ComplaintStatus.dispatched,
      createdAt: now.subtract(const Duration(hours: 18)),
      slaDeadline: now.add(const Duration(hours: 54)),
      inspectorNotes: 'Interconnected micro-cracking mesh. Cold-milling and asphalt overlay scheduled.',
      department: 'Public Works Department (PWD)',
      gpsCoordinates: '17.3832° N, 78.4839° E',
    );

    final c6 = ComplaintItem(
      id: 'CMP-2026-106',
      title: 'Manhole Chamber Frame Displacement & Settlement',
      category: 'Public Works & Utilities',
      zone: 'Sector B • Tech & Engineering Park Avenue',
      severity: ComplaintSeverity.critical,
      severityScore: 0.91,
      status: ComplaintStatus.resolved,
      createdAt: now.subtract(const Duration(days: 2)),
      slaDeadline: now.subtract(const Duration(hours: 6)),
      inspectorNotes: 'Pre-cast ring fractured. Repaired with polymer concrete and certified on-site.',
      department: 'Civil Maintenance Wing',
      gpsCoordinates: '17.3858° N, 78.4895° E',
    );

    _complaintsList.addAll([c1, c2, c3, c4, c5, c6]);

    final case1 = CaseItem(
      id: 'CASE-2026-101',
      complaintId: c1.id,
      title: 'Emergency Hot-Mix Asphalt Patching — Academic Quad',
      department: 'Public Works Department (PWD)',
      assignedTeam: 'Rapid Response Unit Alpha',
      status: CaseStatus.inProgress,
      priority: 'Critical (24h)',
      beforeEvidencePath: '',
      createdAt: now.subtract(const Duration(hours: 3)),
      slaDeadline: now.add(const Duration(hours: 21)),
      assignedEngineer: 'Er. Sandeep Verma',
    );

    final case2 = CaseItem(
      id: 'CASE-2026-102',
      complaintId: c2.id,
      title: 'Overpass Pillar #12 Epoxy Pressure Grouting',
      department: 'Civil Maintenance Wing',
      assignedTeam: 'Heavy Structural Crew #3',
      status: CaseStatus.assigned,
      priority: 'High (48h)',
      beforeEvidencePath: '',
      createdAt: now.subtract(const Duration(hours: 11)),
      slaDeadline: now.add(const Duration(hours: 37)),
      assignedEngineer: 'Er. R. K. Nair',
    );

    final case3 = CaseItem(
      id: 'CASE-2026-103',
      complaintId: c4.id,
      title: 'Culvert Throat Debris Clearance & Sump Desilting',
      department: 'Municipal Drainage Division',
      assignedTeam: 'Hydrology Rapid Response #1',
      status: CaseStatus.assigned,
      priority: 'Critical (24h)',
      beforeEvidencePath: '',
      createdAt: now.subtract(const Duration(hours: 1)),
      slaDeadline: now.add(const Duration(hours: 23)),
      assignedEngineer: 'Er. A. K. Sharma',
    );

    final case4 = CaseItem(
      id: 'CASE-2026-105',
      complaintId: c5.id,
      title: 'West Perimeter Highway Cold-Milling & Asphalt Overlay',
      department: 'Public Works Department (PWD)',
      assignedTeam: 'Pavement Maintenance Squad 4',
      status: CaseStatus.inProgress,
      priority: 'High (48h)',
      beforeEvidencePath: '',
      createdAt: now.subtract(const Duration(hours: 6)),
      slaDeadline: now.add(const Duration(hours: 42)),
      assignedEngineer: 'Er. Sandeep Verma',
    );

    final case5 = CaseItem(
      id: 'CASE-2026-106',
      complaintId: c6.id,
      title: 'Manhole Chamber Reconstruction & Polymer Leveling',
      department: 'Civil Maintenance Wing',
      assignedTeam: 'Utility Team Delta',
      status: CaseStatus.resolved,
      priority: 'Critical (24h)',
      beforeEvidencePath: '',
      createdAt: now.subtract(const Duration(days: 2)),
      slaDeadline: now.subtract(const Duration(hours: 6)),
      assignedEngineer: 'Er. Sandeep Verma',
    );

    _casesList.addAll([case1, case2, case3, case4, case5]);

    _eventsList.addAll([
      MonitoringEvent(
        id: 'EVT-1001',
        timestamp: now.subtract(const Duration(minutes: 5)),
        title: 'Geospatial Radar & GPS Engine Initialized',
        subtitle: 'Live campus coordinates locked: 17.3850° N, 78.4867° E.',
        category: 'camera',
        colorHex: 0xFF10B981,
        iconCode: 0xe6a5,
      ),
      MonitoringEvent(
        id: 'EVT-1002',
        timestamp: now.subtract(const Duration(hours: 3)),
        title: 'Work Order Dispatched: CASE-101',
        subtitle: 'Rapid Response Unit Alpha dispatched to Academic Quad Road.',
        category: 'case',
        colorHex: 0xFF4F46E5,
        iconCode: 0xe0cd,
      ),
      MonitoringEvent(
        id: 'EVT-1003',
        timestamp: now.subtract(const Duration(hours: 4)),
        title: 'Critical Hazard Logged: CMP-2026-101',
        subtitle: 'Severe Pothole Cavity detected with 94% confidence.',
        category: 'complaint',
        colorHex: 0xFFEF4444,
        iconCode: 0xe6e4,
      ),
    ]);

    _evidenceList.addAll([
      EvidenceItem(
        id: 'EVD-2026-001',
        filePath: 'assets/sample_before.jpg',
        timestamp: now.subtract(const Duration(hours: 4)),
        source: 'Edge Front Camera (4K Sensor)',
        resolution: '3840x2160',
        qualityGrade: 'A (High Clarity)',
        sha256Hash: 'a8f3b29c512d7e8b9a0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a',
        gpsLocation: '17.3850° N, 78.4867° E',
        linkedComplaintId: c1.id,
        linkedCaseId: case1.id,
      ),
      EvidenceItem(
        id: 'EVD-2026-002',
        filePath: 'assets/sample_after.jpg',
        timestamp: now.subtract(const Duration(hours: 12)),
        source: 'Mobile Inspection Terminal',
        resolution: '1920x1080',
        qualityGrade: 'A+ (Forensic Grade)',
        sha256Hash: 'b9e4c30d623e8f9c0b1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2b3c',
        gpsLocation: '17.3865° N, 78.4878° E',
        linkedComplaintId: c2.id,
        linkedCaseId: case2.id,
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
    String? linkedCaseId,
    List<String> tags = const [],
  }) async {
    final bytes = await file.readAsBytes();
    final hash = sha256.convert(bytes).toString();
    final filename =
        'EV_${DateTime.now().millisecondsSinceEpoch}_${file.path.split(Platform.pathSeparator).last}';
    final targetFile = File('${_evidenceImagesDir.path}/$filename');
    await targetFile.writeAsBytes(bytes);

    final item = EvidenceItem(
      id: 'EVD-${DateTime.now().millisecondsSinceEpoch % 100000}',
      filePath: targetFile.path,
      timestamp: DateTime.now(),
      source: source,
      resolution: resolution,
      qualityGrade: qualityGrade,
      sha256Hash: hash,
      gpsLocation: gpsLocation ?? '17.3850° N, 78.4867° E',
      linkedComplaintId: linkedComplaintId,
      linkedCaseId: linkedCaseId,
    );

    _evidenceList.insert(0, item);
    _saveAll();
    notifyListeners();
    return item;
  }

  Future<ComplaintItem> logComplaint({
    required String title,
    required String category,
    required String zone,
    required ComplaintSeverity severity,
    required double severityScore,
    List<String> evidencePaths = const [],
    String inspectorNotes = '',
    String? gpsCoordinates,
    String department = 'Public Works Department (PWD)',
  }) async {
    final now = DateTime.now();
    final item = ComplaintItem(
      id: 'CMP-${now.year}-${(now.millisecondsSinceEpoch % 10000).toString().padLeft(4, '0')}',
      title: title,
      category: category,
      zone: zone,
      severity: severity,
      severityScore: severityScore,
      status: ComplaintStatus.submitted,
      createdAt: now,
      slaDeadline: now.add(
        severity == ComplaintSeverity.critical
            ? const Duration(hours: 24)
            : (severity == ComplaintSeverity.high ? const Duration(hours: 48) : const Duration(days: 7)),
      ),
      evidencePaths: evidencePaths,
      inspectorNotes: inspectorNotes,
      gpsCoordinates: gpsCoordinates ?? '17.3850° N, 78.4867° E',
      department: department,
    );

    _complaintsList.insert(0, item);

    final defect = DefectEntity(
      defectId: 'DEF-${item.id}',
      name: title,
      domain: category,
      defectType: category,
      severity: severity.displayName,
      severityScore: severityScore,
      firstSeen: now,
      lastSeen: now,
      observationCount: 1,
      location: zone,
      status: 'Reported',
      primaryEvidencePath: evidencePaths.isNotEmpty ? evidencePaths.first : '',
      gpsCoordinates: gpsCoordinates ?? '17.3850° N, 78.4867° E',
      linkedComplaintId: item.id,
    );
    _defectsList.insert(0, defect);

    AuthorityBridgeService.instance.mirrorInspectorLog(item);

    _saveAll();
    notifyListeners();
    return item;
  }

  Future<void> addComplaint(ComplaintItem item) async {
    _complaintsList.insert(0, item);
    _saveAll();
    notifyListeners();
  }

  /// Reverse-mirror endpoint (registered with the AuthorityBridgeService):
  /// absorbs an officially-synced citizen report so supervisor workflows can
  /// triage and dispatch it like any portal-created complaint.
  void absorbCitizenUpload(MirrorPayload payload) {
    final marker = '@@SRC:${payload.id}';
    final exists = _complaintsList.any((c) =>
        c.linkedCaseId == payload.caseId ||
        c.inspectorNotes.contains(marker));
    if (exists) return;

    final severity = ComplaintSeverity.values.firstWhere(
      (s) => s.name == payload.severityName,
      orElse: () => ComplaintSeverity.moderate,
    );
    final created =
        DateTime.tryParse(payload.createdAtIso)?.toLocal() ?? DateTime.now();
    final sla = switch (severity.name) {
      'critical' => const Duration(hours: 24),
      'high' => const Duration(hours: 48),
      'low' => const Duration(days: 14),
      _ => const Duration(days: 7),
    };

    final item = ComplaintItem(
      id: 'CMP-${created.year}-${_mirrorSeq++}',
      title: payload.title,
      category: payload.category,
      zone: payload.address,
      severity: severity,
      severityScore: payload.severityScore,
      status: ComplaintStatus.submitted,
      createdAt: created,
      slaDeadline: created.add(sla),
      evidencePaths: payload.images,
      inspectorNotes: '${payload.description}\n$marker',
      linkedCaseId: payload.caseId,
      gpsCoordinates:
          '${payload.latitude.toStringAsFixed(4)}\u00B0 N, ${payload.longitude.toStringAsFixed(4)}\u00B0 E',
    );
    _complaintsList.insert(0, item);
    _saveAll();
    notifyListeners();
    debugPrint('AuthorityBridge: absorbed citizen case ${payload.caseId}');
  }

  Future<void> updateComplaintStatus(String id, ComplaintStatus newStatus) async {
    final index = _complaintsList.indexWhere((c) => c.id == id);
    if (index != -1) {
      _complaintsList[index].status = newStatus;
      _saveAll();
      notifyListeners();
    }
  }

  Future<CaseItem> dispatchWorkOrder({
    required ComplaintItem complaint,
    required String assignedTeam,
    String? assignedEngineer,
    String? priority,
  }) async {
    final now = DateTime.now();
    final caseItem = CaseItem(
      id: 'CASE-${now.year}-${(now.millisecondsSinceEpoch % 10000).toString().padLeft(4, '0')}',
      complaintId: complaint.id,
      title: 'Work Order: ${complaint.title}',
      department: complaint.department,
      assignedTeam: assignedTeam,
      status: CaseStatus.assigned,
      priority: priority ?? (complaint.severity == ComplaintSeverity.critical ? 'Critical (24h)' : 'High (48h)'),
      beforeEvidencePath: complaint.evidencePaths.isNotEmpty ? complaint.evidencePaths.first : '',
      createdAt: now,
      slaDeadline: complaint.slaDeadline,
      assignedEngineer: assignedEngineer ?? 'Duty Engineer',
    );

    complaint.status = ComplaintStatus.dispatched;
    complaint.linkedCaseId = caseItem.id;
    _casesList.insert(0, caseItem);

    AuthorityBridgeService.instance
        .reflectWorkOrderDispatch(complaint, caseItem);

    _saveAll();
    notifyListeners();
    return caseItem;
  }

  Future<void> verifyAndCloseCase({
    required CaseItem workOrder,
    required String afterEvidencePath,
    bool verificationPassed = true,
    String verificationNotes = '',
  }) async {
    workOrder.status = CaseStatus.resolved;
    workOrder.afterEvidencePath = afterEvidencePath;
    workOrder.verificationPassed = verificationPassed;
    workOrder.resolvedAt = DateTime.now();
    workOrder.verificationNotes = verificationNotes;

    final compIndex = _complaintsList.indexWhere((c) => c.id == workOrder.complaintId);
    if (compIndex != -1) {
      _complaintsList[compIndex].status = ComplaintStatus.resolved;
    }

    AuthorityBridgeService.instance.reflectClosure(
      workOrder,
      verificationPassed: verificationPassed,
      afterEvidencePath: afterEvidencePath,
    );

    _saveAll();
    notifyListeners();
  }

  Future<void> addCase(CaseItem item) async {
    _casesList.insert(0, item);
    _saveAll();
    notifyListeners();
  }

  Future<void> updateCaseStatus(String id, CaseStatus newStatus) async {
    final index = _casesList.indexWhere((c) => c.id == id);
    if (index != -1) {
      _casesList[index].status = newStatus;
      AuthorityBridgeService.instance
          .reflectCaseStage(_casesList[index], newStatus);
      _saveAll();
      notifyListeners();
    }
  }

  Future<void> addEvent(MonitoringEvent event) async {
    _eventsList.insert(0, event);
    _saveAll();
    notifyListeners();
  }

  void _saveAll() {
    try {
      File('${_metadataDir.path}/complaints.json')
          .writeAsStringSync(jsonEncode(_complaintsList.map((e) => e.toJson()).toList()));
      File('${_metadataDir.path}/cases.json')
          .writeAsStringSync(jsonEncode(_casesList.map((e) => e.toJson()).toList()));
      File('${_metadataDir.path}/evidence.json')
          .writeAsStringSync(jsonEncode(_evidenceList.map((e) => e.toJson()).toList()));
      File('${_metadataDir.path}/defects.json')
          .writeAsStringSync(jsonEncode(_defectsList.map((e) => e.toJson()).toList()));
      File('${_metadataDir.path}/events.json')
          .writeAsStringSync(jsonEncode(_eventsList.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('AppStorage save error: $e');
    }
  }
}
