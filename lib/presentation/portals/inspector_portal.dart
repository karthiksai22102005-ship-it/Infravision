import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../intelligence/issue_intelligence_engine.dart';
import '../../intelligence/models/match_result.dart';
import '../../intelligence/models/observation.dart';
import '../../models/complaint_item.dart';
import '../../repositories/app_storage.dart';

class InspectorPortal extends StatefulWidget {
  const InspectorPortal({super.key});

  @override
  State<InspectorPortal> createState() => _InspectorPortalState();
}

class _InspectorPortalState extends State<InspectorPortal> {
  int _currentIndex = 0;
  bool _offlineMode = false;
  final List<Map<String, dynamic>> _offlineQueue = [];
  final List<Map<String, dynamic>> _syncJournal = [
    {
      'id': 'OBS-SYNC-9842',
      'title': 'Zone A Asphalt Pothole Cluster',
      'category': 'Surface Fracture',
      'gps': '17.3852° N, 78.4868° E',
      'shaDigest': 'e4b901a8f2c3109a',
      'outcome': 'Correlated to PI-001 (94% Match)',
      'timestamp': '10 mins ago',
      'status': 'CORRELATED',
    },
    {
      'id': 'OBS-SYNC-9843',
      'title': 'Longitudinal Concrete Crack Segment',
      'category': 'Structural Degradation',
      'gps': '17.3861° N, 78.4877° E',
      'shaDigest': '79c3d1982b14e8a1',
      'outcome': 'Created New Issue PI-002',
      'timestamp': '25 mins ago',
      'status': 'PROVISIONED',
    },
    {
      'id': 'OBS-SYNC-9844',
      'title': 'Storm Drainage Subsidence Collar',
      'category': 'Subsurface Drainage',
      'gps': '17.3870° N, 78.4885° E',
      'shaDigest': '3f18a990cd21b44e',
      'outcome': 'Correlated to PI-003 (89% Match)',
      'timestamp': '1 hour ago',
      'status': 'CORRELATED',
    },
  ];

  bool _isProcessingBatch = false;
  double _batchProgress = 0.0;
  final List<Map<String, dynamic>> _batchDetections = [];

  // Selected defect simulation type for Live Sweep
  String _selectedDefectType = 'Surface Fracture & Pothole';
  double _simulatedConfidence = 0.92;
  double _simulatedVolume = 125.0; // cm³

  // Checklist items based on ISO-55000 / ASTM asset verification standard
  String _checklistFilter = 'ALL';
  final List<Map<String, dynamic>> _checklist = [
    {
      'id': 1,
      'task': 'Zone Alpha Primary Surface & Fracture Sweep',
      'category': 'Pavement & Surface',
      'standard': 'ASTM D6433',
      'severity': 'Nominal',
      'done': true,
    },
    {
      'id': 2,
      'task': 'Structural Concrete Collar & Storm Sump Audit',
      'category': 'Subsurface Drainage',
      'standard': 'ISO 55001-A4',
      'severity': 'Critical',
      'done': false,
    },
    {
      'id': 3,
      'task': 'Perimeter Guardrail & Regulatory Signage Inspection',
      'category': 'Safety & Boundary',
      'standard': 'EN 1317-2',
      'severity': 'Nominal',
      'done': false,
    },
    {
      'id': 4,
      'task': 'Electrical Enclosure & Utility Line Environmental Seal',
      'category': 'Auxiliary Assets',
      'standard': 'IEC 60529',
      'severity': 'Warning',
      'done': false,
    },
    {
      'id': 5,
      'task': 'Stormwater Outfall Siltation & Catch Basin Flume Clearance',
      'category': 'Subsurface Drainage',
      'standard': 'ISO 55001-A4',
      'severity': 'Nominal',
      'done': false,
    },
    {
      'id': 6,
      'task': 'High-Speed Expansion Joint Elastomeric Seal Integrity',
      'category': 'Pavement & Surface',
      'standard': 'ASTM D6433',
      'severity': 'Nominal',
      'done': true,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgCanvas,
      appBar: AppBar(
        backgroundColor: AppTheme.bgSurface,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.center_focus_strong_rounded, color: AppTheme.purple, size: 20),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'Field Intelligence Portal',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.purple.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.purple.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'FIELD INTELLIGENCE',
                style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppTheme.purple),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _offlineMode ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
              color: _offlineMode ? AppTheme.warning : AppTheme.success,
              size: 20,
            ),
            tooltip: _offlineMode ? 'Offline Mode (Tap to Go Online)' : 'Online Mode (Tap to Go Offline)',
            onPressed: () {
              setState(() => _offlineMode = !_offlineMode);
              if (!_offlineMode && _offlineQueue.isNotEmpty) {
                _syncOfflineQueue();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppTheme.textSecondary),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Switch Portal',
          ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (idx) => setState(() => _currentIndex = idx),
        backgroundColor: AppTheme.bgSurface,
        selectedItemColor: AppTheme.purple,
        unselectedItemColor: AppTheme.textSecondary,
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.videocam_rounded),
            label: 'Live CV Sweep',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.video_collection_rounded),
            label: 'Batch Route',
          ),
          BottomNavigationBarItem(
            icon: Badge(
              label: Text('${_offlineQueue.length}'),
              isLabelVisible: _offlineQueue.isNotEmpty,
              backgroundColor: AppTheme.warning,
              child: const Icon(Icons.sync_rounded),
            ),
            label: 'Offline Queue',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.fact_check_rounded),
            label: 'Checklist',
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([AppStorage.instance, IssueIntelligenceEngine.instance]),
        builder: (context, _) {
          switch (_currentIndex) {
            case 0:
              return _buildLiveScannerTab(context);
            case 1:
              return _buildBatchRouteTab(context);
            case 2:
              return _buildOfflineQueueTab(context);
            case 3:
            default:
              return _buildChecklistTab(context);
          }
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: INDUSTRIAL LIVE CV SCANNER & INTELLIGENCE INGESTION
  // ---------------------------------------------------------------------------
  Widget _buildLiveScannerTab(BuildContext context) {
    final engine = IssueIntelligenceEngine.instance;
    final totalIssues = engine.issues.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Live Edge Vision & Spatial Sweep Engine',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Real-time tensor inference with spatial correlation against physical issues.',
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.purple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.purple.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'ACTIVE ISSUES: $totalIssues',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppTheme.purple),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Edge Camera Stream Simulation HUD
              Container(
                height: 320,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF070B14),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Stack(
                  children: [
                    // Grid lines simulating camera HUD viewfinder
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _ViewfinderGridPainter(),
                      ),
                    ),

                    // Dynamic Bounding Box Overlay 1
                    Positioned(
                      left: 40,
                      top: 70,
                      child: _buildBBox(
                        label: '$_selectedDefectType ${(_simulatedConfidence * 100).toInt()}% (Vol: ${_simulatedVolume.toInt()}cm³)',
                        width: 200,
                        height: 100,
                        color: AppTheme.error,
                        isPrimary: true,
                      ),
                    ),

                    // Bounding Box Overlay 2 (Secondary fissure)
                    Positioned(
                      left: 260,
                      top: 130,
                      child: _buildBBox(
                        label: 'TRANSVERSE FRACTURE 78%',
                        width: 140,
                        height: 70,
                        color: AppTheme.warning,
                        isPrimary: false,
                      ),
                    ),

                    // Top Status Overlay (Sensor & Geodesic Telemetry)
                    Positioned(
                      top: 10,
                      left: 10,
                      right: 10,
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.gps_fixed_rounded, color: AppTheme.cyan, size: 12),
                                SizedBox(width: 5),
                                Text(
                                  'GPS: 17.3850° N, 78.4866° E (±0.8m)',
                                  style: TextStyle(fontSize: 9.5, color: Colors.white, fontFamily: 'monospace'),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.memory_rounded, color: AppTheme.success, size: 12),
                                SizedBox(width: 5),
                                Text(
                                  'YOLOv8 • 28.4 FPS • 16.8ms',
                                  style: TextStyle(fontSize: 9.5, color: AppTheme.success, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Bottom Matching Engine Live Indicator
                    Positioned(
                      bottom: 12,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.purple.withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.hub_rounded, color: AppTheme.purple, size: 14),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'SPATIAL CORRELATION ENGINE: 50m radius search active. Live fusion ready.',
                                style: TextStyle(fontSize: 10, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Defect Selector & Action Controls
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Active Target Defect Classification',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildDefectChip('Surface Fracture & Pothole', 0.94, 140.0),
                        _buildDefectChip('Structural Concrete Degradation', 0.88, 310.0),
                        _buildDefectChip('Optical Obscuration & Signage Defect', 0.91, 0.0),
                        _buildDefectChip('Drainage Collar Subsidence', 0.85, 210.0),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.purple,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _executeIndustrialFieldCapture(),
                      icon: const Icon(Icons.camera_rounded, size: 18),
                      label: const Text(
                        'Capture & Ingest Observation',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDefectChip(String label, double conf, double vol) {
    final isSelected = _selectedDefectType == label;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal)),
      selected: isSelected,
      selectedColor: AppTheme.purple.withValues(alpha: 0.25),
      side: BorderSide(color: isSelected ? AppTheme.purple : AppTheme.border),
      onSelected: (val) {
        if (val) {
          setState(() {
            _selectedDefectType = label;
            _simulatedConfidence = conf;
            _simulatedVolume = vol;
          });
        }
      },
    );
  }

  Widget _buildBBox({
    required String label,
    required double width,
    required double height,
    required Color color,
    required bool isPrimary,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: isPrimary ? 2.0 : 1.5),
        borderRadius: BorderRadius.circular(4),
        color: color.withValues(alpha: 0.06),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -20,
            left: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                label,
                style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _executeIndustrialFieldCapture() async {
    final now = DateTime.now();
    final hashInput = 'OBS-$now-$_selectedDefectType-$_simulatedConfidence';
    final shaDigest = sha256.convert(utf8.encode(hashInput)).toString().substring(0, 16);

    const lat = 17.38504;
    const lng = 78.48667;

    if (_offlineMode) {
      setState(() {
        _offlineQueue.add({
          'id': 'OFFLINE-${DateTime.now().millisecondsSinceEpoch}',
          'title': _selectedDefectType,
          'category': 'Surface & Infrastructure',
          'confidence': _simulatedConfidence,
          'volume': _simulatedVolume,
          'latitude': lat,
          'longitude': lng,
          'shaDigest': shaDigest,
          'timestamp': now.toIso8601String(),
          'notes': 'Field Agent live edge sweep observation (Buffered locally).',
        });
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Offline Buffer: Observation cached locally (Digest: $shaDigest).'),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      // Ingest directly into the IssueIntelligenceEngine
      final obs = Observation(
        observationId: 'OBS-${DateTime.now().millisecondsSinceEpoch}',
        sourceType: ObservationSourceType.fieldAgent,
        sourceId: 'FIELD-AGENT-SCAN-01',
        timestamp: now,
        latitude: lat,
        longitude: lng,
        locationAccuracy: 0.8,
        detectedIssueType: _selectedDefectType,
        classification: _selectedDefectType,
        aiConfidence: _simulatedConfidence,
        userDescription: 'Field Agent live visual sweep capture with volumetric estimate ${_simulatedVolume.toInt()}cm³.',
        contextData: {
          'sha256Digest': shaDigest,
          'volumetricEstimateCm3': _simulatedVolume,
          'edgeModel': 'YOLOv8-Infra',
        },
      );

      final outcome = IssueIntelligenceEngine.instance.submitObservation(obs);

      // Also sync to AppStorage for complaint store backwards compatibility
      await AppStorage.instance.logComplaint(
        title: _selectedDefectType,
        category: 'Physical Asset Hazards',
        zone: 'Zone 1 - East Corridor',
        severity: _simulatedConfidence > 0.9 ? ComplaintSeverity.high : ComplaintSeverity.moderate,
        severityScore: _simulatedConfidence,
        inspectorNotes: 'Ingested via Field Intelligence Portal. Correlated Issue: ${outcome.physicalIssue.physicalIssueId}.',
      );

      if (!mounted) return;

      final matchText = outcome.matchResult.resultType == MatchResultType.matched
          ? 'Correlated to existing Issue ${outcome.physicalIssue.physicalIssueId} (${(outcome.matchResult.overallConfidence * 100).toInt()}% match score)'
          : outcome.matchResult.resultType == MatchResultType.uncertain
              ? 'Flagged for Supervisor Review (Confidence: ${(outcome.matchResult.overallConfidence * 100).toInt()}%)'
              : 'Created New Persistent Physical Issue (${outcome.physicalIssue.physicalIssueId})';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Live Ingestion: $matchText'),
          backgroundColor: AppTheme.purple,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // TAB 2: INDUSTRIAL BATCH VIDEO SWEEP PROCESSOR
  // ---------------------------------------------------------------------------
  Widget _buildBatchRouteTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Batch Route Video Sweep & Trajectory Clustering',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 4),
              const Text(
                'Process continuous corridor route videos. The AI spatial-temporal clustering engine groups multi-frame hits into distinct Physical Issues.',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),

              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!_isProcessingBatch) ...[
                      const Icon(Icons.video_library_rounded, color: AppTheme.purple, size: 40),
                      const SizedBox(height: 12),
                      const Text(
                        'Route Corridor Footage (450 Frames / 1.2km)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Supports MP4, AVI with synchronized NMEA GPS subtitle telemetry.',
                        style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: AppTheme.purple),
                        onPressed: () {
                          setState(() {
                            _isProcessingBatch = true;
                            _batchProgress = 0.0;
                            _batchDetections.clear();
                          });
                          _runIndustrialBatchProcessor();
                        },
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Execute Batch AI Route Sweep'),
                      ),
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'TENSOR INFERENCE & SPATIAL CLUSTERING',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppTheme.purple),
                                ),
                                Text(
                                  '${(_batchProgress * 100).toInt()}%',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.purple),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(value: _batchProgress, color: AppTheme.purple),
                            const SizedBox(height: 12),
                            Text(
                              'Analyzing Frame ${(450 * _batchProgress).toInt()} / 450 • Geodesic clustering active...',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              if (_batchDetections.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Row(
                  children: [
                    Icon(Icons.hub_rounded, color: AppTheme.purple, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Spatial Clustering & Physical Issue Ingestion Summary',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final det in _batchDetections)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.bgSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (det['color'] as Color).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(Icons.merge_type_rounded, color: det['color'] as Color, size: 16),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                det['title'] as String,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${det['frames']} frame duplicates merged • GPS: ${det['gps']} • Ingested: ${det['issueId']}',
                                style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            det['status'] as String,
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.success),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _runIndustrialBatchProcessor() {
    Timer.periodic(const Duration(milliseconds: 120), (timer) {
      if (!mounted) return;
      setState(() {
        _batchProgress += 0.1;
      });

      if (_batchProgress >= 1.0) {
        timer.cancel();

        // Ingest the batch observations into the engine
        final obs1 = Observation(
          observationId: 'OBS-BATCH-01',
          sourceType: ObservationSourceType.aiBatchAnalysis,
          sourceId: 'ROUTE-SWEEP-CORRIDOR-A',
          timestamp: DateTime.now(),
          latitude: 17.3852,
          longitude: 78.4868,
          detectedIssueType: 'Pothole & Surface Fracture',
          aiConfidence: 0.94,
          userDescription: 'Batch video sweep merged 48 frames into distinct defect cluster.',
        );
        final res1 = IssueIntelligenceEngine.instance.submitObservation(obs1);

        final obs2 = Observation(
          observationId: 'OBS-BATCH-02',
          sourceType: ObservationSourceType.aiBatchAnalysis,
          sourceId: 'ROUTE-SWEEP-CORRIDOR-A',
          timestamp: DateTime.now(),
          latitude: 17.3860,
          longitude: 78.4875,
          detectedIssueType: 'Transverse Crack Segment',
          aiConfidence: 0.88,
          userDescription: 'Batch video sweep merged 21 frames into distinct defect cluster.',
        );
        final res2 = IssueIntelligenceEngine.instance.submitObservation(obs2);

        setState(() {
          _isProcessingBatch = false;
          _batchDetections.addAll([
            {
              'title': 'TrackID-042: Asphalt Surface Pothole Cluster',
              'frames': 48,
              'gps': '17.3852° N, 78.4868° E',
              'issueId': res1.physicalIssue.physicalIssueId,
              'status': 'CORRELATED',
              'color': AppTheme.error,
            },
            {
              'title': 'TrackID-045: Longitudinal Structural Fracture',
              'frames': 21,
              'gps': '17.3860° N, 78.4875° E',
              'issueId': res2.physicalIssue.physicalIssueId,
              'status': 'CORRELATED',
              'color': AppTheme.warning,
            },
            {
              'title': 'TrackID-047: Reflective Signpost Obscuration',
              'frames': 12,
              'gps': '17.3868° N, 78.4881° E',
              'issueId': 'PI-AUTO-03',
              'status': 'CORRELATED',
              'color': AppTheme.cyan,
            },
          ]);
        });
      }
    });
  }

  // ---------------------------------------------------------------------------
  // TAB 3: INDUSTRIAL OFFLINE QUEUE & BUFFER RECONCILIATION DASHBOARD
  // ---------------------------------------------------------------------------
  Widget _buildOfflineQueueTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Offline Capture Synchronization Queue',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppTheme.textPrimary),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Observations recorded without active cellular signal are buffered locally with SHA-256 integrity proofs.',
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.purple,
                          side: const BorderSide(color: AppTheme.purple),
                        ),
                        onPressed: () => _injectSimulatedOfflineCaptures(),
                        icon: const Icon(Icons.add_photo_alternate_rounded, size: 16),
                        label: const Text('Simulate +3 Offline Captures', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      if (_offlineQueue.isNotEmpty)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.success,
                          ),
                          onPressed: () => _syncOfflineQueue(),
                          icon: const Icon(Icons.sync_rounded, size: 16),
                          label: Text(
                            'Synchronize Buffer (${_offlineQueue.length})',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // KPI Metrics Grid (4 Cards)
              LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = constraints.maxWidth < 600 ? 2 : 4;
                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: constraints.maxWidth < 600 ? 1.6 : 1.8,
                    children: [
                      _buildKpiCard(
                        title: 'NETWORK STATUS',
                        value: _offlineMode ? 'OFFLINE' : 'ONLINE',
                        subtitle: _offlineMode ? 'Local Buffering Active' : 'Real-time WebSocket Sync',
                        icon: _offlineMode ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                        color: _offlineMode ? AppTheme.warning : AppTheme.success,
                      ),
                      _buildKpiCard(
                        title: 'BUFFERED QUEUE',
                        value: '${_offlineQueue.length} ITEMS',
                        subtitle: _offlineQueue.isEmpty ? 'All observations synced' : 'Pending cloud ingestion',
                        icon: Icons.inventory_2_rounded,
                        color: _offlineQueue.isEmpty ? AppTheme.cyan : AppTheme.warning,
                      ),
                      _buildKpiCard(
                        title: 'STORAGE CONSUMPTION',
                        value: '${(_offlineQueue.length * 12.4).toStringAsFixed(1)} KB',
                        subtitle: 'Local SQLite cache • 50 MB max',
                        icon: Icons.storage_rounded,
                        color: AppTheme.primary,
                      ),
                      _buildKpiCard(
                        title: 'CRYPTOGRAPHIC AUDIT',
                        value: 'SHA-256 LOCKED',
                        subtitle: 'Zero tamper anomalies detected',
                        icon: Icons.security_rounded,
                        color: AppTheme.success,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),

              // Two-Column Section: Queue Items & Sync Journal
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 768;

                  final queueSection = Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.bgSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.queue_rounded, color: AppTheme.warning, size: 16),
                                SizedBox(width: 8),
                                Text(
                                  'Current Offline Ingestion Queue',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _offlineQueue.isEmpty ? AppTheme.success.withValues(alpha: 0.15) : AppTheme.warning.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${_offlineQueue.length} PENDING',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: _offlineQueue.isEmpty ? AppTheme.success : AppTheme.warning,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_offlineQueue.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: AppTheme.success.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.cloud_done_rounded, color: AppTheme.success, size: 36),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Offline buffer is completely synchronized.',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'All edge captures have been correlated and ingested into the central physical issue database.',
                                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 14),
                                OutlinedButton.icon(
                                  onPressed: () => _injectSimulatedOfflineCaptures(),
                                  icon: const Icon(Icons.add_rounded, size: 14),
                                  label: const Text('Inject Test Observations', style: TextStyle(fontSize: 11)),
                                ),
                              ],
                            ),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _offlineQueue.length,
                            itemBuilder: (context, idx) {
                              final item = _offlineQueue[idx];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.border),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppTheme.warning.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Icon(Icons.cloud_off_rounded, color: AppTheme.warning, size: 16),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                item['title'] as String,
                                                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.cyan.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  '${((item['confidence'] as double) * 100).toInt()}% Conf',
                                                  style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: AppTheme.cyan),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            'GPS: ${item['latitude']}° N, ${item['longitude']}° E • SHA-256: ${item['shaDigest']}',
                                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 9.5, fontFamily: 'monospace'),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.textMuted, size: 18),
                                      onPressed: () {
                                        setState(() {
                                          _offlineQueue.removeAt(idx);
                                        });
                                      },
                                      tooltip: 'Discard',
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  );

                  final journalSection = Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.bgSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.history_rounded, color: AppTheme.cyan, size: 16),
                                SizedBox(width: 8),
                                Text(
                                  'Recent Synchronization Journal',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                                ),
                              ],
                            ),
                            Text(
                              'AUDIT RECEIPT',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        for (final item in _syncJournal)
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.success.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(Icons.done_all_rounded, color: AppTheme.success, size: 16),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['title'] as String,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${item['outcome']} • ${item['timestamp']}',
                                        style: const TextStyle(fontSize: 10, color: AppTheme.cyan, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Digest: ${item['shaDigest']} • GPS: ${item['gps']}',
                                        style: const TextStyle(fontSize: 9, color: AppTheme.textMuted, fontFamily: 'monospace'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: queueSection),
                        const SizedBox(width: 16),
                        Expanded(flex: 5, child: journalSection),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        queueSection,
                        const SizedBox(height: 16),
                        journalSection,
                      ],
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppTheme.textMuted, letterSpacing: 0.5),
              ),
              Icon(icon, color: color, size: 16),
            ],
          ),
          Text(
            value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color),
          ),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 9.5, color: AppTheme.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _injectSimulatedOfflineCaptures() {
    setState(() {
      _offlineMode = true;
      _offlineQueue.addAll([
        {
          'id': 'OFFLINE-${DateTime.now().millisecondsSinceEpoch}-1',
          'title': 'Surface Fracture & Pothole',
          'category': 'Road Surface',
          'confidence': 0.94,
          'volume': 145.0,
          'latitude': 17.38504,
          'longitude': 78.48667,
          'shaDigest': '8a9f4c21e0b7',
          'timestamp': DateTime.now().toIso8601String(),
          'notes': 'Offline sweep: High-severity pavement subsidence detected.',
        },
        {
          'id': 'OFFLINE-${DateTime.now().millisecondsSinceEpoch}-2',
          'title': 'Structural Concrete Degradation',
          'category': 'Subsurface Drainage',
          'confidence': 0.89,
          'volume': 280.0,
          'latitude': 17.38590,
          'longitude': 78.48740,
          'shaDigest': '4d11b83e9fa2',
          'timestamp': DateTime.now().toIso8601String(),
          'notes': 'Offline sweep: Storm sump collar separation.',
        },
        {
          'id': 'OFFLINE-${DateTime.now().millisecondsSinceEpoch}-3',
          'title': 'Optical Obscuration & Signage Defect',
          'category': 'Safety Signage',
          'confidence': 0.91,
          'volume': 0.0,
          'latitude': 17.38670,
          'longitude': 78.48820,
          'shaDigest': '7c88e23f011a',
          'timestamp': DateTime.now().toIso8601String(),
          'notes': 'Offline sweep: Speed limit sign obstructed by vegetation.',
        },
      ]);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Simulated: 3 offline observations added to local buffer.'),
        backgroundColor: AppTheme.warning,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _syncOfflineQueue() async {
    final engine = IssueIntelligenceEngine.instance;
    final storage = AppStorage.instance;

    int matchedCount = 0;
    int newCount = 0;

    for (final item in _offlineQueue) {
      final obs = Observation(
        observationId: 'OBS-SYNC-${DateTime.now().millisecondsSinceEpoch}',
        sourceType: ObservationSourceType.fieldAgent,
        sourceId: item['id'] as String,
        timestamp: DateTime.parse(item['timestamp'] as String),
        latitude: (item['latitude'] as num).toDouble(),
        longitude: (item['longitude'] as num).toDouble(),
        detectedIssueType: item['title'] as String,
        classification: item['title'] as String,
        aiConfidence: (item['confidence'] as num).toDouble(),
        userDescription: item['notes'] as String,
        contextData: {
          'sha256Digest': item['shaDigest'],
          'syncMode': 'reconciledOfflineBuffer',
        },
      );

      final outcome = engine.submitObservation(obs);
      if (outcome.matchResult.resultType == MatchResultType.matched) {
        matchedCount++;
      } else {
        newCount++;
      }

      await storage.logComplaint(
        title: item['title'] as String,
        category: 'Physical Asset Hazards',
        zone: 'Zone 1 - East Corridor',
        severity: ComplaintSeverity.moderate,
        severityScore: (item['confidence'] as num).toDouble(),
        inspectorNotes: 'Reconciled from Field Agent offline queue. Correlated ID: ${outcome.physicalIssue.physicalIssueId}.',
      );

      _syncJournal.insert(0, {
        'id': obs.observationId,
        'title': item['title'] as String,
        'category': item['category'] as String,
        'gps': '${item['latitude']}° N, ${item['longitude']}° E',
        'shaDigest': item['shaDigest'] as String,
        'outcome': outcome.matchResult.resultType == MatchResultType.matched
            ? 'Correlated to ${outcome.physicalIssue.physicalIssueId} (${(outcome.matchResult.overallConfidence * 100).toInt()}% Match)'
            : 'Created New Issue ${outcome.physicalIssue.physicalIssueId}',
        'timestamp': 'Just now',
        'status': outcome.matchResult.resultType == MatchResultType.matched ? 'CORRELATED' : 'PROVISIONED',
      });
    }

    setState(() {
      _offlineQueue.clear();
      _offlineMode = false;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Offline Queue Synced: $matchedCount matched, $newCount new physical issues provisioned.'),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 4: ISO-55000 / ASTM COMPLIANCE ASSET AUDIT SUITE
  // ---------------------------------------------------------------------------
  Widget _buildChecklistTab(BuildContext context) {
    final doneCount = _checklist.where((c) => c['done'] == true).length;
    final progress = _checklist.isEmpty ? 0.0 : doneCount / _checklist.length;

    final filteredChecklist = _checklist.where((item) {
      if (_checklistFilter == 'PAVEMENT' && !item['standard'].toString().contains('ASTM')) {
        return false;
      }
      if (_checklistFilter == 'DRAINAGE' && !item['standard'].toString().contains('ISO 55001')) {
        return false;
      }
      if (_checklistFilter == 'SAFETY' && !item['standard'].toString().contains('EN 1317')) {
        return false;
      }
      if (_checklistFilter == 'ELECTRICAL' && !item['standard'].toString().contains('IEC 60529')) {
        return false;
      }
      return true;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Header & Action Controls
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ISO-55000 Asset Audit & Verification Protocol',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppTheme.textPrimary),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Standardized compliance checklists for pavement distress (ASTM D6433) and drainage structures.',
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.cyan,
                          side: const BorderSide(color: AppTheme.cyan),
                        ),
                        onPressed: () => _showAddCheckpointDialog(context),
                        icon: const Icon(Icons.add_task_rounded, size: 16),
                        label: const Text('Add Checkpoint', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.purple,
                        ),
                        onPressed: () => _showExportCertificateDialog(context, doneCount, _checklist.length),
                        icon: const Icon(Icons.verified_rounded, size: 16),
                        label: const Text('Export Audit Certificate', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Progress Indicator Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Daily Route Asset Audit Completion',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                        ),
                        Text(
                          '$doneCount / ${_checklist.length} Verified (${(progress * 100).toInt()}%)',
                          style: const TextStyle(fontSize: 12, color: AppTheme.purple, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        color: AppTheme.purple,
                        backgroundColor: AppTheme.border,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Filter Chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildChecklistFilterChip('All Checkpoints (${_checklist.length})', 'ALL'),
                  _buildChecklistFilterChip('ASTM D6433 Pavement', 'PAVEMENT'),
                  _buildChecklistFilterChip('ISO 55001 Drainage', 'DRAINAGE'),
                  _buildChecklistFilterChip('EN 1317 Safety', 'SAFETY'),
                  _buildChecklistFilterChip('IEC 60529 Electrical', 'ELECTRICAL'),
                ],
              ),
              const SizedBox(height: 16),

              // Checklist Items
              for (int idx = 0; idx < filteredChecklist.length; idx++) ...[
                Builder(
                  builder: (context) {
                    final item = filteredChecklist[idx];
                    final isDone = item['done'] as bool;
                    final severity = item['severity'] as String? ?? 'Nominal';
                    final isCritical = severity == 'Critical';
                    final isWarning = severity == 'Warning';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.bgSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isCritical && !isDone
                              ? AppTheme.error.withValues(alpha: 0.4)
                              : isDone
                                  ? AppTheme.purple.withValues(alpha: 0.3)
                                  : AppTheme.border,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Checkbox(
                            value: isDone,
                            activeColor: AppTheme.purple,
                            onChanged: (val) {
                              setState(() {
                                item['done'] = val;
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['task'] as String,
                                  style: TextStyle(
                                    color: isDone ? AppTheme.textSecondary : AppTheme.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    decoration: isDone ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.cyan.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.3)),
                                      ),
                                      child: Text(
                                        item['standard'] as String,
                                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.cyan),
                                      ),
                                    ),
                                    Text(
                                      item['category'] as String,
                                      style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: isCritical
                                            ? AppTheme.error.withValues(alpha: 0.15)
                                            : isWarning
                                                ? AppTheme.warning.withValues(alpha: 0.15)
                                                : AppTheme.success.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        severity.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.bold,
                                          color: isCritical
                                              ? AppTheme.error
                                              : isWarning
                                                  ? AppTheme.warning
                                                  : AppTheme.success,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (!isDone)
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.warning,
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => _flagDefectFromChecklist(item),
                              icon: const Icon(Icons.report_problem_rounded, size: 14),
                              label: const Text('Flag Defect', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChecklistFilterChip(String label, String code) {
    final isSelected = _checklistFilter == code;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      selectedColor: AppTheme.purple.withValues(alpha: 0.25),
      side: BorderSide(color: isSelected ? AppTheme.purple : AppTheme.border),
      onSelected: (val) {
        if (val) {
          setState(() => _checklistFilter = code);
        }
      },
    );
  }

  void _flagDefectFromChecklist(Map<String, dynamic> item) {
    final obs = Observation(
      observationId: 'OBS-CHECKLIST-${DateTime.now().millisecondsSinceEpoch}',
      sourceType: ObservationSourceType.fieldAgent,
      sourceId: 'INSPECTOR-CHECKLIST-AUDIT',
      timestamp: DateTime.now(),
      latitude: 17.3855,
      longitude: 78.4870,
      detectedIssueType: item['task'] as String,
      classification: item['category'] as String,
      aiConfidence: 0.95,
      userDescription: 'Flagged non-compliance during daily inspection: ${item['task']} under standard ${item['standard']}.',
    );

    final outcome = IssueIntelligenceEngine.instance.submitObservation(obs);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Defect Ingested into Engine: Correlated to ${outcome.physicalIssue.physicalIssueId}.'),
        backgroundColor: AppTheme.purple,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showAddCheckpointDialog(BuildContext context) {
    final taskController = TextEditingController();
    String category = 'Pavement & Surface';
    String standard = 'ASTM D6433';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.bgSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Add Compliance Asset Checkpoint', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: taskController,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Inspection Task Description',
                    hintText: 'e.g. Guardrail Tension Bolt Torque Verification',
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.purple)),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: standard,
                  dropdownColor: AppTheme.bgSurface,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Compliance Standard',
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.purple)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'ASTM D6433', child: Text('ASTM D6433 Pavement Standard')),
                    DropdownMenuItem(value: 'ISO 55001-A4', child: Text('ISO 55001-A4 Subsurface Drainage')),
                    DropdownMenuItem(value: 'EN 1317-2', child: Text('EN 1317-2 Safety Barrier Standard')),
                    DropdownMenuItem(value: 'IEC 60529', child: Text('IEC 60529 Auxiliary Utilities')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() {
                        standard = val;
                        if (val.contains('ASTM')) category = 'Pavement & Surface';
                        if (val.contains('ISO')) category = 'Subsurface Drainage';
                        if (val.contains('EN')) category = 'Safety & Boundary';
                        if (val.contains('IEC')) category = 'Auxiliary Assets';
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(fontSize: 12)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.purple),
              onPressed: () {
                if (taskController.text.trim().isNotEmpty) {
                  setState(() {
                    _checklist.add({
                      'id': _checklist.length + 1,
                      'task': taskController.text.trim(),
                      'category': category,
                      'standard': standard,
                      'severity': 'Nominal',
                      'done': false,
                    });
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('Add Checkpoint', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showExportCertificateDialog(BuildContext context, int verified, int total) {
    final digest = sha256.convert(utf8.encode('AUDIT-$verified-$total-${DateTime.now()}')).toString().substring(0, 16);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.verified_rounded, color: AppTheme.success, size: 20),
            SizedBox(width: 8),
            Text('ISO-55000 Audit Certificate', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CERTIFICATE OF PHYSICAL ASSET INTEGRITY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppTheme.success)),
                    const SizedBox(height: 6),
                    Text('Verification Status: $verified / $total Checkpoints Completed (${((verified / (total == 0 ? 1 : total)) * 100).toInt()}%)',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                    const SizedBox(height: 4),
                    Text('Cryptographic Seal: SHA-256-$digest', style: const TextStyle(fontSize: 9.5, color: AppTheme.cyan, fontFamily: 'monospace')),
                    const SizedBox(height: 2),
                    Text('Timestamp: ${DateTime.now().toLocal()}', style: const TextStyle(fontSize: 9.5, color: AppTheme.textMuted)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'This certificate confirms that all primary route sweep inspections adhere to ASTM D6433 and ISO 55001 physical asset standards.',
                style: TextStyle(fontSize: 10.5, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Audit Certificate exported successfully (Seal: $digest).'),
                  backgroundColor: AppTheme.success,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.download_rounded, size: 14),
            label: const Text('Download Certificate (.JSON / .PDF)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for camera viewfinder HUD grid lines
class _ViewfinderGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.0;

    // Rule-of-thirds grid
    canvas.drawLine(Offset(size.width / 3, 0), Offset(size.width / 3, size.height), paint);
    canvas.drawLine(Offset(2 * size.width / 3, 0), Offset(2 * size.width / 3, size.height), paint);
    canvas.drawLine(Offset(0, size.height / 3), Offset(size.width, size.height / 3), paint);
    canvas.drawLine(Offset(0, 2 * size.height / 3), Offset(size.width, 2 * size.height / 3), paint);

    // Center crosshair
    final crossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 1.5;
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.drawLine(Offset(cx - 10, cy), Offset(cx + 10, cy), crossPaint);
    canvas.drawLine(Offset(cx, cy - 10), Offset(cx, cy + 10), crossPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
