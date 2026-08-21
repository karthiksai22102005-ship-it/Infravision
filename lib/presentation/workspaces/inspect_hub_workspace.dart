import 'package:flutter/material.dart';
import '../../camera/camera_service.dart';
import '../../config/app_theme.dart';
import '../../vision/vision_service.dart';

import 'image_analysis_workspace.dart';
import 'live_inspection_workspace.dart';
import 'video_analysis_workspace.dart';

enum InspectMode { live, image, video }

/// Unified AI Vision Inspection Hub hosting Live Camera, Image Upload, and Video Scan.
class InspectHubWorkspace extends StatefulWidget {
  const InspectHubWorkspace({
    super.key,
    required this.cameraService,
    required this.visionService,
    required this.onSnapshot,
    this.initialMode = InspectMode.live,
  });

  final CameraService cameraService;
  final VisionService visionService;
  final VoidCallback onSnapshot;
  final InspectMode initialMode;

  @override
  State<InspectHubWorkspace> createState() => _InspectHubWorkspaceState();
}

class _InspectHubWorkspaceState extends State<InspectHubWorkspace> {
  late InspectMode _currentMode;

  @override
  void initState() {
    super.initState();
    _currentMode = widget.initialMode;
  }

  void _onModeChanged(InspectMode mode) {
    if (_currentMode == InspectMode.live && mode != InspectMode.live) {
      if (widget.cameraService.isRunning) {
        widget.visionService.stop();
        widget.cameraService.stopCamera();
      }
    }
    setState(() => _currentMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top Modern Segmented Switcher
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: AppTheme.bgSurface,
            border: Border(bottom: BorderSide(color: AppTheme.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _SegmentPill(
                        label: 'Live Camera Feed',
                        icon: Icons.videocam_rounded,
                        isSelected: _currentMode == InspectMode.live,
                        onTap: () => _onModeChanged(InspectMode.live),
                      ),
                      const SizedBox(width: 8),
                      _SegmentPill(
                        label: 'Photo Diagnosis',
                        icon: Icons.image_search_rounded,
                        isSelected: _currentMode == InspectMode.image,
                        onTap: () => _onModeChanged(InspectMode.image),
                      ),
                      const SizedBox(width: 8),
                      _SegmentPill(
                        label: 'Video Clip Scan',
                        icon: Icons.video_file_rounded,
                        isSelected: _currentMode == InspectMode.video,
                        onTap: () => _onModeChanged(InspectMode.video),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Sub-Workspace Body
        Expanded(
          child: switch (_currentMode) {
            InspectMode.live => LiveInspectionWorkspace(
                cameraService: widget.cameraService,
                visionService: widget.visionService,
                onSnapshot: widget.onSnapshot,
              ),
            InspectMode.image => const ImageAnalysisWorkspace(),
            InspectMode.video => const VideoAnalysisWorkspace(),
          },
        ),
      ],
    );
  }
}

class _SegmentPill extends StatelessWidget {
  const _SegmentPill({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppTheme.primaryLight : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppTheme.primary : AppTheme.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 17,
                color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AppTheme.primary : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
