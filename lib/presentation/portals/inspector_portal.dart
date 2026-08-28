import 'dart:async';
import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
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
  bool _isProcessingBatch = false;
  double _batchProgress = 0.0;
  final List<String> _batchDetections = [];

  // Checklist items
  final List<Map<String, dynamic>> _checklist = [
    {'id': 1, 'task': 'Inspect Sector A Main Arterial Road', 'done': true},
    {'id': 2, 'task': 'Verify stormsump concrete collar Sector B', 'done': false},
    {'id': 3, 'task': 'Audit circular route highway guardrails', 'done': false},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgCanvas,
      appBar: AppBar(
        backgroundColor: AppTheme.bgSurface,
        title: Row(
          children: [
            const Icon(Icons.center_focus_strong_rounded, color: AppTheme.purple, size: 20),
            const SizedBox(width: 10),
            const Text(
              'Field Inspector Portal',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
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
                'FIELD AGENT',
                style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppTheme.purple),
              ),
            ),
          ],
        ),
        actions: [
          // Offline/Online toggle
          Row(
            children: [
              Icon(
                _offlineMode ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                color: _offlineMode ? AppTheme.warning : AppTheme.success,
                size: 16,
              ),
              const SizedBox(width: 6),
              Switch(
                value: !_offlineMode,
                onChanged: (val) {
                  setState(() => _offlineMode = !val);
                  if (val && _offlineQueue.isNotEmpty) {
                    _syncOfflineQueue();
                  }
                },
                activeTrackColor: AppTheme.success.withValues(alpha: 0.5),
                activeThumbColor: AppTheme.success,
                inactiveThumbColor: AppTheme.warning,
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppTheme.textSecondary),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Switch Portal',
          ),
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
        listenable: AppStorage.instance,
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
  // TAB 1: LIVE SCANNER VIEW
  // ---------------------------------------------------------------------------
  Widget _buildLiveScannerTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Live Bounding Box Overlay scanner',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 12),

              // Mock Camera Stream Frame with YOLO boxes
              Container(
                height: 300,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Stack(
                  children: [
                    // Bounding Box Overlays
                    Positioned(
                      left: 60,
                      top: 80,
                      child: _buildBBox(
                        label: 'POTHOLE 92% (Volume: 125cm³)',
                        width: 180,
                        height: 100,
                        color: AppTheme.error,
                      ),
                    ),
                    Positioned(
                      left: 280,
                      top: 140,
                      child: _buildBBox(
                        label: 'TRANSVERSE CRACK 78%',
                        width: 140,
                        height: 80,
                        color: AppTheme.warning,
                      ),
                    ),

                    Positioned(
                      bottom: 16,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        color: Colors.black54,
                        child: const Text(
                          'YOLOv8n Inference: 24.1 FPS • Latency: 18.2ms',
                          style: TextStyle(fontSize: 10, color: AppTheme.success, fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.purple),
                      onPressed: () => _simulateInspectorCapture(),
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Capture & Log Defect'),
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

  Widget _buildBBox({
    required String label,
    required double width,
    required double height,
    required Color color,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -18,
            left: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              color: color,
              child: Text(
                label,
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _simulateInspectorCapture() async {
    const title = 'Asphalt Pothole Area Segment';
    const notes = 'Field inspector manual sweep confirmation.';

    if (_offlineMode) {
      setState(() {
        _offlineQueue.add({
          'title': title,
          'category': 'Road & Pavement Hazards',
          'notes': notes,
          'gps': '17.3850° N, 78.4867° E',
        });
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offline Mode: Capture saved to offline queue local buffer.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      await AppStorage.instance.logComplaint(
        title: title,
        category: 'Road & Pavement Hazards',
        zone: 'Zone 1 - East Corridor',
        severity: ComplaintSeverity.high,
        severityScore: 0.88,
        inspectorNotes: notes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Live Mode: Capture synced instantly with supervisor database.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // TAB 2: BATCH SWEEP LOG PROCESSOR
  // ---------------------------------------------------------------------------
  Widget _buildBatchRouteTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Batch Video Sweep & Duplicate Merge',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 4),
              const Text(
                'Upload a route drive video. AI auto-merges duplicate frame hits to generate single distinct complaints.',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),

              Container(
                height: 180,
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
                      const Icon(Icons.video_library_rounded, color: AppTheme.textSecondary, size: 36),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _isProcessingBatch = true;
                            _batchProgress = 0.0;
                            _batchDetections.clear();
                          });
                          _runMockBatchProcessor();
                        },
                        child: const Text('Load Route Video File'),
                      ),
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          children: [
                            LinearProgressIndicator(value: _batchProgress, color: AppTheme.purple),
                            const SizedBox(height: 12),
                            Text(
                              'Processing Frame ${(450 * _batchProgress).toInt()} / 450...',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              if (_batchDetections.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'Duplicate Aggregation Summary',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 8),
                for (final det in _batchDetections)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.merge_type_rounded, color: AppTheme.purple, size: 14),
                        const SizedBox(width: 8),
                        Text(
                          det,
                          style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary),
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

  void _runMockBatchProcessor() {
    Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (!mounted) return;
      setState(() {
        _batchProgress += 0.1;
      });

      if (_batchProgress >= 1.0) {
        timer.cancel();
        setState(() {
          _isProcessingBatch = false;
          _batchDetections.addAll([
            'TrackID-042 (Pothole): 48 frame duplicates merged into CMP-001',
            'TrackID-045 (Crack): 21 frame duplicates merged into CMP-002',
            'TrackID-047 (Signboard): 12 frame duplicates merged into CMP-003',
          ]);
        });
      }
    });
  }

  // ---------------------------------------------------------------------------
  // TAB 3: OFFLINE QUEUE
  // ---------------------------------------------------------------------------
  Widget _buildOfflineQueueTab(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Offline Capture Synchronization Queue',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 4),
          const Text(
            'Items captured without active cellular signal are cached locally here.',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),

          Expanded(
            child: _offlineQueue.isEmpty
                ? const Center(
                    child: Text('Offline queue is empty.', style: TextStyle(color: AppTheme.textMuted)),
                  )
                : ListView.builder(
                    itemCount: _offlineQueue.length,
                    itemBuilder: (context, idx) {
                      final item = _offlineQueue[idx];
                      return ListTile(
                        leading: const Icon(Icons.cloud_off_rounded, color: AppTheme.warning),
                        title: Text(
                          item['title'] as String,
                          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          item['notes'] as String,
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                        ),
                      );
                    },
                  ),
          ),

          if (_offlineQueue.isNotEmpty)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
                onPressed: () => _syncOfflineQueue(),
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Synchronize Local Buffer (Go Online)'),
              ),
            ),
        ],
      ),
    );
  }

  void _syncOfflineQueue() async {
    final storage = AppStorage.instance;
    for (final item in _offlineQueue) {
      await storage.logComplaint(
        title: item['title'] as String,
        category: item['category'] as String,
        zone: 'Zone 1 - East Corridor',
        severity: ComplaintSeverity.moderate,
        severityScore: 0.72,
        inspectorNotes: item['notes'] as String,
      );
    }
    setState(() {
      _offlineQueue.clear();
      _offlineMode = false;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Offline Queue fully synchronized and cleared.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 4: ROUTE CHECKLIST
  // ---------------------------------------------------------------------------
  Widget _buildChecklistTab(BuildContext context) {
    final doneCount = _checklist.where((c) => c['done'] == true).length;
    final progress = doneCount / _checklist.length;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Daily Inspection Routes & Checklist',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 12),

          // Progress indicator
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.bgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Today Completion Tracker', style: TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
                    Text('${(progress * 100).toInt()}% Done', style: const TextStyle(fontSize: 12, color: AppTheme.purple, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: progress, color: AppTheme.purple),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Expanded(
            child: ListView.builder(
              itemCount: _checklist.length,
              itemBuilder: (context, idx) {
                final item = _checklist[idx];
                return CheckboxListTile(
                  title: Text(
                    item['task'] as String,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      decoration: item['done'] == true ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  value: item['done'] as bool,
                  activeColor: AppTheme.purple,
                  onChanged: (val) {
                    setState(() {
                      item['done'] = val;
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
