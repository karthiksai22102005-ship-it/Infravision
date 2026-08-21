import 'package:flutter/material.dart';

/// Categories grouping workspaces in the sidebar.
enum WorkspaceCategory {
  coreOperations('CORE OPERATIONS'),
  maintenanceWorkflow('MAINTENANCE WORKFLOW'),
  analyticsAndMlops('ANALYTICS & MLOPS');

  final String title;
  const WorkspaceCategory(this.title);
}

/// Primary navigation tabs in the Left Pro Sidebar.
enum AppTab {
  missionControl(
    label: 'Mission Control',
    headerTitle: 'MISSION CONTROL & OPERATIONS DASHBOARD',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard_rounded,
    category: WorkspaceCategory.coreOperations,
    badgeText: 'Live',
  ),
  aiInspection(
    label: 'AI Vision',
    headerTitle: 'AI VISION INSPECTION (DETECT & LOCATE)',
    icon: Icons.camera_alt_outlined,
    selectedIcon: Icons.camera_alt_rounded,
    category: WorkspaceCategory.coreOperations,
    badgeText: '3 Feeds',
  ),
  campusMap(
    label: 'Campus Map',
    headerTitle: 'CAMPUS & MUNICIPAL GEOSPATIAL MAP',
    icon: Icons.map_outlined,
    selectedIcon: Icons.map_rounded,
    category: WorkspaceCategory.coreOperations,
    badgeText: '14 Zones',
  ),
  workOrders(
    label: 'Work Orders',
    headerTitle: 'WORK ORDERS & TRIAGE (PRIORITIZE & ASSIGN)',
    icon: Icons.assignment_outlined,
    selectedIcon: Icons.assignment_rounded,
    category: WorkspaceCategory.maintenanceWorkflow,
    badgeText: '42 Open',
  ),
  verification(
    label: 'AI Verification',
    headerTitle: 'BEFORE & AFTER AI REPAIR VERIFICATION',
    icon: Icons.fact_check_outlined,
    selectedIcon: Icons.fact_check_rounded,
    category: WorkspaceCategory.maintenanceWorkflow,
    badgeText: '9 Pending',
  ),
  evidenceVault(
    label: 'Evidence Vault',
    headerTitle: 'CRYPTOGRAPHIC EVIDENCE VAULT (SHA-256)',
    icon: Icons.perm_media_outlined,
    selectedIcon: Icons.perm_media_rounded,
    category: WorkspaceCategory.maintenanceWorkflow,
    badgeText: 'SHA-256',
  ),
  reports(
    label: 'Audit Reports',
    headerTitle: 'PRINTABLE AUDIT SLIPS & COMPLIANCE REPORTS',
    icon: Icons.print_outlined,
    selectedIcon: Icons.print_rounded,
    category: WorkspaceCategory.analyticsAndMlops,
  ),
  modelStudio(
    label: 'Model Studio',
    headerTitle: 'EDGE AI TRAINING & MLOPS PIPELINE',
    icon: Icons.model_training_outlined,
    selectedIcon: Icons.model_training_rounded,
    category: WorkspaceCategory.analyticsAndMlops,
    badgeText: 'YOLOv8',
  ),
  diagnostics(
    label: 'Diagnostics',
    headerTitle: 'DIRECTSHOW & SENSOR HARDWARE DIAGNOSTICS',
    icon: Icons.tune_outlined,
    selectedIcon: Icons.tune_rounded,
    category: WorkspaceCategory.analyticsAndMlops,
    badgeText: 'DirectShow',
  );

  final String label;
  final String headerTitle;
  final IconData icon;
  final IconData selectedIcon;
  final WorkspaceCategory category;
  final String? badgeText;

  const AppTab({
    required this.label,
    required this.headerTitle,
    required this.icon,
    required this.selectedIcon,
    required this.category,
    this.badgeText,
  });
}

/// Slideable sub-tabs inside Mission Control Dashboard.
enum DashboardSubTab {
  cameraFeed('Real-Time Camera Feed', Icons.videocam_rounded),
  campusMap('3D Geospatial Campus Map', Icons.map_rounded),
  aiVerification('Before vs After AI Verification', Icons.fact_check_rounded),
  incidentTriage('Live Incident Triage Feed', Icons.table_chart_rounded);

  final String label;
  final IconData icon;
  const DashboardSubTab(this.label, this.icon);
}
