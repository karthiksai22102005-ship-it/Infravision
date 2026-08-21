import 'package:flutter/material.dart';
import '../../camera/camera_service.dart';
import '../../config/app_theme.dart';
import '../../models/complaint_item.dart';
import '../../repositories/app_storage.dart';
import '../../vision/vision_service.dart';
import '../widgets/camera_preview.dart';
import '../widgets/camera_status_panel.dart';

enum InspectionMode {
  manual('Manual Camera', 'Clean observation with AI processing turned off', Icons.videocam_outlined),
  backgroundAi('Background AI', 'Silent AI defect detection without screen overlays', Icons.psychology_outlined),
  visualHud('Visual HUD', 'Real-time YOLO bounding boxes, tracking & confidence', Icons.view_in_ar_rounded),
  fieldInspection('Field Inspection', 'Full inspection mode with 1-tap evidence capture', Icons.fact_check_outlined);

  const InspectionMode(this.label, this.description, this.icon);
  final String label;
  final String description;
  final IconData icon;
}

/// Professional Live Inspection Workstation with Framing, Zoom, and Multi-Mode Controls.
class LiveInspectionWorkspace extends StatefulWidget {
  const LiveInspectionWorkspace({
    super.key,
    required this.cameraService,
    required this.visionService,
    required this.onSnapshot,
  });

  final CameraService cameraService;
  final VisionService visionService;
  final VoidCallback onSnapshot;

  @override
  State<LiveInspectionWorkspace> createState() => _LiveInspectionWorkspaceState();
}

class _LiveInspectionWorkspaceState extends State<LiveInspectionWorkspace> {
  InspectionMode _selectedMode = InspectionMode.visualHud;
  CameraFraming _framing = CameraFraming.fit;
  double _zoomLevel = 1.0;

  @override
  void initState() {
    super.initState();
    _applyMode(InspectionMode.visualHud);
  }

  void _applyMode(InspectionMode mode) {
    setState(() {
      _selectedMode = mode;
    });

    switch (mode) {
      case InspectionMode.manual:
        widget.visionService.setAiEnabled(false);
        widget.visionService.setOverlayEnabled(false);
        widget.visionService.stop();
        break;
      case InspectionMode.backgroundAi:
        widget.visionService.setAiEnabled(true);
        widget.visionService.setOverlayEnabled(false);
        if (widget.cameraService.isRunning) widget.visionService.start();
        break;
      case InspectionMode.visualHud:
        widget.visionService.setAiEnabled(true);
        widget.visionService.setOverlayEnabled(true);
        if (widget.cameraService.isRunning) widget.visionService.start();
        break;
      case InspectionMode.fieldInspection:
        widget.visionService.setAiEnabled(true);
        widget.visionService.setOverlayEnabled(true);
        if (widget.cameraService.isRunning) widget.visionService.start();
        break;
    }
  }

  Future<void> _handleLogComplaint() async {
    final titleCtrl = TextEditingController(text: 'Road Pothole / Surface Cavity (D40)');
    final zoneCtrl = TextEditingController(text: 'Campus Access Corridor - Zone 2');
    final notesCtrl = TextEditingController(text: 'Observed during live camera mobile inspection.');
    String category = 'Road & Pavement Hazards';
    ComplaintSeverity severity = ComplaintSeverity.high;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.report_problem_rounded, color: AppTheme.error, size: 22),
              SizedBox(width: 10),
              Text('Log Live Complaint', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Complaint Title', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  TextField(controller: titleCtrl, decoration: const InputDecoration(hintText: 'e.g. Broken Paver Blocks')),
                  const SizedBox(height: 12),

                  const Text('Category', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    items: const [
                      DropdownMenuItem(value: 'Road & Pavement Hazards', child: Text('Road & Pavement Hazards (D40/D20)')),
                      DropdownMenuItem(value: 'Concrete & Structural', child: Text('Concrete & Structural Cracks')),
                      DropdownMenuItem(value: 'Glass & Solar Assets', child: Text('Glass & Solar Panel Fractures')),
                      DropdownMenuItem(value: 'Drainage & Manholes', child: Text('Open / Broken Manhole Hazard')),
                      DropdownMenuItem(value: 'Electrical & Lighting', child: Text('Electrical & Wire Hazard')),
                      DropdownMenuItem(value: 'Sanitation & Debris', child: Text('Garbage / Debris Obstruction')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDlgState(() => category = val);
                    },
                  ),
                  const SizedBox(height: 12),

                  const Text('Location / Ward / Zone', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  TextField(controller: zoneCtrl, decoration: const InputDecoration(hintText: 'e.g. Overpass Pillar #12')),
                  const SizedBox(height: 12),

                  const Text('Severity Level', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  Row(
                    children: ComplaintSeverity.values.map((s) {
                      final isSel = severity == s;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(s.displayName, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isSel ? Colors.white : AppTheme.textPrimary)),
                          selected: isSel,
                          selectedColor: s == ComplaintSeverity.critical ? AppTheme.error : (s == ComplaintSeverity.high ? AppTheme.warning : AppTheme.accentBlue),
                          onSelected: (_) => setDlgState(() => severity = s),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  const Text('Inspector Field Notes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  TextField(controller: notesCtrl, maxLines: 2, decoration: const InputDecoration(hintText: 'Field observation details…')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Submit Complaint Ticket'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      final comp = await AppStorage.instance.logComplaint(
        title: titleCtrl.text.trim(),
        category: category,
        zone: zoneCtrl.text.trim(),
        severity: severity,
        severityScore: severity == ComplaintSeverity.critical ? 0.95 : (severity == ComplaintSeverity.high ? 0.85 : 0.6),
        evidencePaths: [],
        inspectorNotes: notesCtrl.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Complaint ${comp.id} logged successfully.'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 12 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header Toolbar (Modes + Status)
          _buildHeader(context),
          const SizedBox(height: 14),

          // 2. Main Inspection Canvas & Control Deck
          if (MediaQuery.sizeOf(context).width >= 1100)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Camera Viewport (Flex 7)
                Expanded(
                  flex: 7,
                  child: _buildCameraViewport(context),
                ),
                const SizedBox(width: 16),
                // Right: Inspection Controls & Hardware Status (Flex 5)
                Expanded(
                  flex: 5,
                  child: _buildSideControlPanel(context),
                ),
              ],
            )
          else ...[
            _buildCameraViewport(context),
            const SizedBox(height: 16),
            _buildSideControlPanel(context),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.videocam_rounded, color: AppTheme.primary, size: 20),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Live Vision & Defect Inspection Workstation',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                  ),
                  Text(
                    'YOLOv5 Multi-Model Detection • Hardware DirectShow Stream',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            children: InspectionMode.values.map((mode) {
              final isSel = _selectedMode == mode;
              return ChoiceChip(
                avatar: Icon(mode.icon, size: 14, color: isSel ? Colors.white : AppTheme.textSecondary),
                label: Text(mode.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isSel ? Colors.white : AppTheme.textPrimary)),
                selected: isSel,
                selectedColor: AppTheme.primary,
                onSelected: (_) => _applyMode(mode),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraViewport(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowMd,
      ),
      child: Column(
        children: [
          // 1. Camera Viewport Surface
          SizedBox(
            height: 480,
            width: double.infinity,
            child: CameraPreview(
              framing: _framing,
              zoomLevel: _zoomLevel,
              onDoubleTapResetZoom: () => setState(() => _zoomLevel = 1.0),
            ),
          ),

          // 2. Stream Bottom Action Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                // Zoom presets
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.zoom_in_rounded, size: 16, color: Colors.white70),
                    const SizedBox(width: 6),
                    ...[1.0, 1.5, 2.0, 3.0].map((z) {
                      final isSel = (_zoomLevel - z).abs() < 0.1;
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: InkWell(
                          onTap: () => setState(() => _zoomLevel = z),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSel ? AppTheme.primary : const Color(0xFF334155),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${z.toStringAsFixed(1)}x',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isSel ? Colors.white : Colors.white70,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),

                // Action Buttons
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: widget.onSnapshot,
                      icon: const Icon(Icons.camera_alt_outlined, size: 16),
                      label: const Text('Snapshot'),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.error,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      onPressed: _handleLogComplaint,
                      icon: const Icon(Icons.warning_amber_rounded, size: 16),
                      label: const Text('Log Complaint'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideControlPanel(BuildContext context) {
    return Column(
      children: [
        // Camera Hardware Status & Switcher
        const CameraStatusPanel(),
        const SizedBox(height: 10),

        // Quick Hardware Stream Switch
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: widget.cameraService.isRunning ? AppTheme.error : AppTheme.success,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () async {
                  if (widget.cameraService.isRunning) {
                    widget.visionService.stop();
                    await widget.cameraService.stopCamera();
                  } else {
                    final ok = await widget.cameraService.startCamera();
                    if (ok) {
                      await widget.visionService.start();
                    }
                  }
                  if (mounted) setState(() {});
                },
                icon: Icon(widget.cameraService.isRunning ? Icons.videocam_off_rounded : Icons.videocam_rounded, size: 18),
                label: Text(
                  widget.cameraService.isRunning ? 'Stop Camera Stream' : 'Start Camera Stream',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Framing & Zoom Deck
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.bgSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
            boxShadow: AppTheme.shadowSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.aspect_ratio_rounded, color: AppTheme.primary, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Framing & Optical Zoom',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Framing Radio
              const Text('Framing Mode', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
              const SizedBox(height: 6),
              Row(
                children: CameraFraming.values.map((f) {
                  final isSel = _framing == f;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: InkWell(
                        onTap: () => setState(() => _framing = f),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: isSel ? AppTheme.primaryLight : AppTheme.bgSurfaceSubtle,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isSel ? AppTheme.primary : AppTheme.border),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            f.label.split(' ').first,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isSel ? AppTheme.primary : AppTheme.textPrimary),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // Zoom Slider
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Digital Zoom', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                  Text('${_zoomLevel.toStringAsFixed(1)}x', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary, fontFamily: 'monospace')),
                ],
              ),
              Slider(
                value: _zoomLevel,
                min: 1.0,
                max: 4.0,
                divisions: 30,
                activeColor: AppTheme.primary,
                onChanged: (val) => setState(() => _zoomLevel = val),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Live YOLO Object Detection & Neural Pipeline Controller
        ListenableBuilder(
          listenable: widget.visionService,
          builder: (context, _) {
            final vision = widget.visionService;
            final isAiOn = vision.aiEnabled;
            final isOverlayOn = vision.overlayEnabled;
            final isTrackingOn = vision.trackingEnabled;
            final tracks = vision.trackedObjects;

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.bgSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isAiOn ? AppTheme.primary.withValues(alpha: 0.4) : AppTheme.border),
                boxShadow: AppTheme.shadowSm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + Master Switch
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: isAiOn ? AppTheme.primaryLight : AppTheme.bgSurfaceSubtle,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(Icons.psychology_rounded, color: isAiOn ? AppTheme.primary : AppTheme.textMuted, size: 18),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'YOLO Detection',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                                  ),
                                  Text(
                                    'Edge CV Engine',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: isAiOn,
                        activeThumbColor: AppTheme.primary,
                        onChanged: (val) {
                          vision.setAiEnabled(val);
                          if (val) vision.setOverlayEnabled(true);
                          if (val && widget.cameraService.isRunning) {
                            vision.start();
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Overlay & Tracker Fast Toggles
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => vision.setOverlayEnabled(!isOverlayOn),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                            decoration: BoxDecoration(
                              color: isOverlayOn ? const Color(0xFF0F291E) : AppTheme.bgSurfaceSubtle,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isOverlayOn ? const Color(0xFF00E5A0) : AppTheme.border),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.view_in_ar_rounded, size: 14, color: isOverlayOn ? const Color(0xFF00E5A0) : AppTheme.textMuted),
                                const SizedBox(width: 6),
                                Text(
                                  'Visual HUD',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isOverlayOn ? const Color(0xFF00E5A0) : AppTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () => vision.setTrackingEnabled(!isTrackingOn),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                            decoration: BoxDecoration(
                              color: isTrackingOn ? const Color(0xFF0C2433) : AppTheme.bgSurfaceSubtle,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isTrackingOn ? const Color(0xFF00B4D8) : AppTheme.border),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.sensors_rounded, size: 14, color: isTrackingOn ? const Color(0xFF00B4D8) : AppTheme.textMuted),
                                const SizedBox(width: 6),
                                Text(
                                  'Track IDs',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isTrackingOn ? const Color(0xFF00B4D8) : AppTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Sensitivity Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Flexible(
                        child: Text(
                          'Detection Sensitivity',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                        ),
                      ),
                      Text('${(vision.confidenceThreshold * 100).toInt()}% Conf', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppTheme.primary, fontFamily: 'monospace')),
                    ],
                  ),
                  Slider(
                    value: vision.confidenceThreshold,
                    min: 0.25,
                    max: 0.90,
                    divisions: 13,
                    activeColor: AppTheme.primary,
                    onChanged: (val) => vision.setConfidenceThreshold(val),
                  ),
                  const SizedBox(height: 10),

                  // Live Detected Objects Feed
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.bgSurfaceSubtle,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                'DETECTED OBJECTS (${tracks.length})',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: AppTheme.textMuted),
                              ),
                            ),
                            Text(
                              '${vision.inferenceFps.toStringAsFixed(1)} AI-FPS',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF00B4D8), fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (tracks.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Icon(
                                  widget.cameraService.isRunning ? Icons.radar_rounded : Icons.videocam_off_outlined,
                                  size: 16,
                                  color: AppTheme.textMuted,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.cameraService.isRunning
                                        ? 'Scanning live camera feed for objects…'
                                        : 'Start camera stream to activate detection.',
                                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: tracks.map((t) {
                              final col = Color(t.colorHex);
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: col.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: col.withValues(alpha: 0.6)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(color: col, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${t.displayId} ${t.className.toUpperCase()} ${(t.confidence * 100).toInt()}%',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: col,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
