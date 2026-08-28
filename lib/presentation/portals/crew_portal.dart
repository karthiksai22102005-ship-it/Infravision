import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/case_item.dart';
import '../../repositories/app_storage.dart';

class CrewPortal extends StatefulWidget {
  const CrewPortal({super.key});

  @override
  State<CrewPortal> createState() => _CrewPortalState();
}

class _CrewPortalState extends State<CrewPortal> {
  CaseItem? _selectedCase;
  bool _showCameraOverlay = false;
  bool _showMaterialsLog = false;

  // Material Form Controllers
  final _asphaltController = TextEditingController(text: '2.5 cubic meters');
  final _sealerController = TextEditingController(text: 'Grade-A sealant');
  final _hoursController = TextEditingController(text: '3.5 hours');

  @override
  void dispose() {
    _asphaltController.dispose();
    _sealerController.dispose();
    _hoursController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgCanvas,
      appBar: AppBar(
        backgroundColor: AppTheme.bgSurface,
        title: Row(
          children: [
            const Icon(Icons.engineering_rounded, color: AppTheme.warning, size: 20),
            const SizedBox(width: 10),
            const Text(
              'Contractor Crew Portal',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'CONTRACTOR',
                style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppTheme.warning),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppTheme.textSecondary),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Switch Portal',
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: AppStorage.instance,
        builder: (context, _) {
          final cases = AppStorage.instance.casesList
              .where((c) => c.status != CaseStatus.resolved)
              .toList();

          if (_showCameraOverlay && _selectedCase != null) {
            return _buildGuidedCameraView(context);
          }

          if (_showMaterialsLog && _selectedCase != null) {
            return _buildMaterialsLogView(context);
          }

          return _buildAssignmentsListView(context, cases);
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ASSIGNMENTS LIST VIEW
  // ---------------------------------------------------------------------------
  Widget _buildAssignmentsListView(BuildContext context, List<CaseItem> cases) {
    if (cases.isEmpty) {
      return const Center(
        child: Text('No active work orders assigned to your division.', style: TextStyle(color: AppTheme.textMuted)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: cases.length,
      itemBuilder: (context, idx) {
        final item = cases[idx];
        return Card(
          color: AppTheme.bgSurface,
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        item.priority.toUpperCase(),
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.warning),
                      ),
                    ),
                    Text(
                      'SLA: Active Timer',
                      style: TextStyle(fontSize: 10, color: AppTheme.error.withValues(alpha: 0.9)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  item.title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Case Reference ID: ${item.id} • Dept: ${item.department}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.cyan,
                          side: const BorderSide(color: AppTheme.cyan),
                        ),
                        onPressed: () {
                          // Display simulated original before photo
                          _showBeforePhotoDialog(context, item);
                        },
                        icon: const Icon(Icons.image_search_rounded, size: 14),
                        label: const Text('View Before-Photo'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: AppTheme.warning),
                        onPressed: () {
                          setState(() {
                            _selectedCase = item;
                            _showCameraOverlay = true;
                          });
                        },
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 14),
                        label: const Text('Mark Fixed'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showBeforePhotoDialog(BuildContext context, CaseItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgSurface,
        title: const Text('Original Defect Reference Photo', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
        content: Container(
          height: 200,
          width: 300,
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image_rounded, color: Colors.white24, size: 40),
                SizedBox(height: 8),
                Text('Assets before image reference log', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Close'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // GUIDED GHOST CAMERA VIEW
  // ---------------------------------------------------------------------------
  Widget _buildGuidedCameraView(BuildContext context) {
    return Column(
      children: [
        // Camera with ghost before-photo overlay guide
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Mock camera feed background (e.g. solid black / gray)
              Container(color: Colors.black),

              // Semi-transparent original photo "ghost overlay" to match angle
              Opacity(
                opacity: 0.35,
                child: Container(
                  margin: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white54, width: 2),
                    color: Colors.white10,
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.filter_center_focus_rounded, color: Colors.white54, size: 40),
                        SizedBox(height: 12),
                        Text(
                          'ALIGN REPAIR VIEW TO THIS GHOST OVERLAY REFERENCE',
                          style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Viewfinder grid lines
              Positioned(
                top: 40,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  color: Colors.black54,
                  child: const Text(
                    'Guided Capture Mode: Matching Before-Photo Angle',
                    style: TextStyle(fontSize: 10, color: AppTheme.warning, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Action controls
        Container(
          padding: const EdgeInsets.all(20),
          color: AppTheme.bgSurface,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _showCameraOverlay = false;
                  });
                },
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.warning),
                onPressed: () {
                  setState(() {
                    _showCameraOverlay = false;
                    _showMaterialsLog = true;
                  });
                },
                icon: const Icon(Icons.camera_alt_rounded),
                label: const Text('Confirm Photo Alignment'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // MATERIALS & TIME LOG
  // ---------------------------------------------------------------------------
  Widget _buildMaterialsLogView(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Close Case & Log Materials',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 6),
          const Text(
            'Record the exact paving resources, volume, and crew labor to finalize invoice audits.',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),

          TextField(
            controller: _asphaltController,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Asphalt Volume Paved (cubic meters)',
              labelStyle: TextStyle(color: AppTheme.textSecondary),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.cyan)),
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _sealerController,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Joint/Fibre Sealant Grade',
              labelStyle: TextStyle(color: AppTheme.textSecondary),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.cyan)),
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _hoursController,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Total Crew Man-Hours Spent',
              labelStyle: TextStyle(color: AppTheme.textSecondary),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.cyan)),
            ),
          ),
          const SizedBox(height: 30),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _showMaterialsLog = false;
                    });
                  },
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
                  onPressed: () => _finalizeCaseRepair(context),
                  child: const Text('Submit Fix Verification File', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _finalizeCaseRepair(BuildContext context) async {
    final storage = AppStorage.instance;
    if (_selectedCase != null) {
      final messenger = ScaffoldMessenger.of(context);
      await storage.verifyAndCloseCase(
        workOrder: _selectedCase!,
        afterEvidencePath: 'evidence/images/after_repair_01.jpg',
        verificationPassed: true,
        verificationNotes: 'Contractor auto-log: asphalt=${_asphaltController.text}, sealer=${_sealerController.text}, duration=${_hoursController.text}',
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Repair file logged. Forwarded to supervisor verification queue.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() {
        _selectedCase = null;
        _showMaterialsLog = false;
      });
    }
  }
}
