import 'dart:async';
import 'package:flutter/material.dart';

import '../../camera/camera_service.dart';
import '../../config/app_theme.dart';
import '../../core/app_preferences.dart';
import '../../vision/vision_service.dart';

// Navigation & Shell Components
import '../navigation/workspace_navigation.dart';
import 'app_header.dart';
import 'app_sidebar.dart';
import 'telemetry_status_bar.dart';

// Workspaces
import '../workspaces/campus_map_workspace.dart';
import '../workspaces/diagnostics_workspace.dart';
import '../workspaces/evidence_workspace.dart';
import '../workspaces/inspect_hub_workspace.dart';
import '../workspaces/issues_hub_workspace.dart';
import '../workspaces/overview_workspace.dart';
import '../workspaces/reports_workspace.dart';
import '../workspaces/training_workspace.dart';
import '../workspaces/verification_workspace.dart';

/// InfraVision Complete Enterprise AI & Operations Workstation Shell.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final CameraService _cameraService = CameraService.instance;
  final VisionService _visionService = VisionService.instance;
  final AppPreferences _prefs = AppPreferences.instance;

  // Default to Mission Control on startup
  AppTab _currentTab = AppTab.missionControl;
  bool _isSidebarCollapsed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialiseWorkstationStandby());
  }

  /// Initializes preferences and hardware in dormant standby.
  Future<void> _initialiseWorkstationStandby() async {
    await _prefs.init();
    _visionService.setConfidenceThreshold(_prefs.confidenceThreshold);
    _visionService.setTargetInferenceFps(_prefs.targetInferenceFps);
    _visionService.setOverlayEnabled(false);
    _visionService.setTrackingEnabled(_prefs.trackingEnabled);

    // Enumerate cameras in standby without activating stream
    await _cameraService.enumerateCameras();
    if (!mounted) return;

    if (_cameraService.devices.isNotEmpty) {
      _cameraService.selectDevice(0);
    }
    setState(() {});
  }

  Future<void> _startCamera() async {
    if (_cameraService.isStarting || _cameraService.isStopping) return;
    final success = await _cameraService.startCamera();
    if (!mounted) return;

    if (success) {
      await _visionService.start();
    }
  }

  Future<void> _stopCamera() async {
    if (_cameraService.isStopping) return;
    _visionService.stop();
    await _cameraService.stopCamera();
    if (mounted) setState(() {});
  }

  Future<void> _takeSnapshot() async {
    final savedPath = await _visionService.takeSnapshot();
    if (!mounted) return;

    if (savedPath != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Evidence captured & SHA-256 sealed: $savedPath',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _switchTab(AppTab newTab) {
    // If leaving live camera view, automatically stop camera stream to release hardware
    if ((_currentTab == AppTab.aiInspection || _currentTab == AppTab.missionControl) &&
        (newTab != AppTab.aiInspection && newTab != AppTab.missionControl)) {
      if (_cameraService.isRunning) {
        _stopCamera();
      }
    }
    setState(() => _currentTab = newTab);
  }

  @override
  void dispose() {
    _visionService.stop();
    unawaited(_cameraService.stopCamera());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);

    return ListenableBuilder(
      listenable: _cameraService,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppTheme.bgCanvas,
          body: SafeArea(
            child: Column(
              children: [
                // 1. Full-Width Global Top Bar
                AppHeader(
                  currentTab: _currentTab,
                  cameraService: _cameraService,
                  visionService: _visionService,
                  isCollapsed: _isSidebarCollapsed,
                  onToggleCollapse: isMobile
                      ? null
                      : () {
                          setState(() {
                            _isSidebarCollapsed = !_isSidebarCollapsed;
                          });
                        },
                ),

                // 2. Main Body (Left Pro Sidebar + Dynamic Workspace)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!isMobile)
                        AppSidebar(
                          currentTab: _currentTab,
                          onTabSelected: _switchTab,
                          isCollapsed: _isSidebarCollapsed,
                        ),
                      Expanded(
                        child: _buildWorkspaceContent(),
                      ),
                    ],
                  ),
                ),

                // 3. Bottom Status & Telemetry Strip
                TelemetryStatusBar(
                  cameraService: _cameraService,
                  visionService: _visionService,
                  onToggleCamera: () {
                    if (_cameraService.isRunning) {
                      _stopCamera();
                    } else {
                      _startCamera();
                    }
                  },
                  onSnapshot: _takeSnapshot,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWorkspaceContent() {
    switch (_currentTab) {
      case AppTab.missionControl:
        return OverviewWorkspace(
          onNavigateTab: _switchTab,
          cameraService: _cameraService,
          visionService: _visionService,
          onSnapshot: _takeSnapshot,
        );

      case AppTab.aiInspection:
        return InspectHubWorkspace(
          cameraService: _cameraService,
          visionService: _visionService,
          onSnapshot: _takeSnapshot,
        );

      case AppTab.campusMap:
        return const CampusMapWorkspace();

      case AppTab.workOrders:
        return const IssuesHubWorkspace();

      case AppTab.verification:
        return const VerificationWorkspace();

      case AppTab.evidenceVault:
        return const EvidenceWorkspace();

      case AppTab.reports:
        return const ReportsWorkspace();

      case AppTab.modelStudio:
        return const TrainingWorkspace();

      case AppTab.diagnostics:
        return DiagnosticsWorkspace(
          cameraService: _cameraService,
          visionService: _visionService,
        );
    }
  }
}
