import 'package:flutter/material.dart';
import '../../camera/camera_service.dart';
import '../../config/app_theme.dart';
import '../../vision/vision_service.dart';

import 'datasets_workspace.dart';
import 'diagnostics_workspace.dart';
import 'docker_workspace.dart';
import 'reports_workspace.dart';
import 'training_workspace.dart';

enum StudioTab { reports, datasets, training, docker, diagnostics }

/// Unified Hub for PDF Reports, Dataset Curation, Model Training, and Diagnostics.
class StudioHubWorkspace extends StatefulWidget {
  const StudioHubWorkspace({
    super.key,
    required this.cameraService,
    required this.visionService,
    this.initialTab = StudioTab.reports,
  });

  final CameraService cameraService;
  final VisionService visionService;
  final StudioTab initialTab;

  @override
  State<StudioHubWorkspace> createState() => _StudioHubWorkspaceState();
}

class _StudioHubWorkspaceState extends State<StudioHubWorkspace> {
  late StudioTab _currentTab;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
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
                        label: 'Audit Reports & Slips',
                        icon: Icons.print_rounded,
                        isSelected: _currentTab == StudioTab.reports,
                        onTap: () => setState(() => _currentTab = StudioTab.reports),
                      ),
                      const SizedBox(width: 8),
                      _SegmentPill(
                        label: 'Dataset Curation',
                        icon: Icons.folder_open_rounded,
                        isSelected: _currentTab == StudioTab.datasets,
                        onTap: () => setState(() => _currentTab = StudioTab.datasets),
                      ),
                      const SizedBox(width: 8),
                      _SegmentPill(
                        label: 'Real-Time Training',
                        icon: Icons.model_training_rounded,
                        isSelected: _currentTab == StudioTab.training,
                        onTap: () => setState(() => _currentTab = StudioTab.training),
                      ),
                      const SizedBox(width: 8),
                      _SegmentPill(
                        label: 'Docker & Edge',
                        icon: Icons.developer_board_rounded,
                        isSelected: _currentTab == StudioTab.docker,
                        onTap: () => setState(() => _currentTab = StudioTab.docker),
                      ),
                      const SizedBox(width: 8),
                      _SegmentPill(
                        label: 'Diagnostics',
                        icon: Icons.tune_rounded,
                        isSelected: _currentTab == StudioTab.diagnostics,
                        onTap: () => setState(() => _currentTab = StudioTab.diagnostics),
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
          child: switch (_currentTab) {
            StudioTab.reports => const ReportsWorkspace(),
            StudioTab.datasets => const DatasetsWorkspace(),
            StudioTab.training => const TrainingWorkspace(),
            StudioTab.docker => const DockerWorkspace(),
            StudioTab.diagnostics => DiagnosticsWorkspace(
                cameraService: widget.cameraService,
                visionService: widget.visionService,
              ),
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
