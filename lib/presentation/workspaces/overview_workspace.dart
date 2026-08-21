import 'package:flutter/material.dart';
import '../../camera/camera_service.dart';
import '../../config/app_theme.dart';
import '../../models/complaint_item.dart';
import '../../repositories/app_storage.dart';
import '../../vision/vision_service.dart';
import '../navigation/workspace_navigation.dart';

// Sub-workspace views for the slides
import 'campus_map_workspace.dart';
import 'live_inspection_workspace.dart';
import 'verification_workspace.dart';

/// Mission Control Dashboard featuring Top KPI Cards & WhatsApp-Style Slideable Sub-Tabs.
class OverviewWorkspace extends StatefulWidget {
  const OverviewWorkspace({
    super.key,
    required this.onNavigateTab,
    required this.cameraService,
    required this.visionService,
    required this.onSnapshot,
  });

  final ValueChanged<AppTab> onNavigateTab;
  final CameraService cameraService;
  final VisionService visionService;
  final VoidCallback onSnapshot;

  @override
  State<OverviewWorkspace> createState() => _OverviewWorkspaceState();
}

class _OverviewWorkspaceState extends State<OverviewWorkspace> {
  DashboardSubTab _activeSubTab = DashboardSubTab.cameraFeed;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStorage.instance,
      builder: (context, _) {
        final storage = AppStorage.instance;
        final complaints = storage.complaintsList;
        final cases = storage.casesList;

        return Container(
          color: AppTheme.bgCanvas,
          child: Column(
            children: [
              // 1. Top KPI Summary Strip (Always Visible)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                color: AppTheme.bgCanvas,
                child: _buildKpiGrid(context, storage),
              ),

              // 2. WhatsApp-Style Horizontal Slideable Sub-Tab Bar (Dark Styling)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFF0F172A),
                  border: Border(
                    top: BorderSide(color: Color(0xFF1E293B)),
                    bottom: BorderSide(color: Color(0xFF1E293B)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final subTab in DashboardSubTab.values)
                              _SubTabPill(
                                label: subTab.label,
                                icon: subTab.icon,
                                isSelected: _activeSubTab == subTab,
                                onTap: () => setState(() => _activeSubTab = subTab),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 3. Dynamic Slide Viewport (Full Screen Width for Active View)
              Expanded(
                child: switch (_activeSubTab) {
                  DashboardSubTab.cameraFeed => LiveInspectionWorkspace(
                      cameraService: widget.cameraService,
                      visionService: widget.visionService,
                      onSnapshot: widget.onSnapshot,
                    ),
                  DashboardSubTab.campusMap => const CampusMapWorkspace(),
                  DashboardSubTab.aiVerification => const VerificationWorkspace(),
                  DashboardSubTab.incidentTriage => _buildIncidentTriageTable(context, complaints, cases),
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildKpiGrid(BuildContext context, AppStorage storage) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 750;

        return GridView.count(
          crossAxisCount: isNarrow ? 2 : 4,
          crossAxisSpacing: 14,
          mainAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: isNarrow ? 2.2 : 2.5,
          children: [
            _KpiCard(
              title: 'Total Defects',
              value: '${1420 + storage.complaintsList.length}',
              change: '+5% this week',
              icon: Icons.grid_view_rounded,
              color: AppTheme.primary,
            ),
            _KpiCard(
              title: 'Active Work Orders',
              value: '${storage.casesList.length}',
              change: '42 Assigned',
              icon: Icons.build_circle_rounded,
              color: AppTheme.warning,
            ),
            const _KpiCard(
              title: 'Critical 24h SLAs',
              value: '3',
              change: 'Urgent Alert',
              icon: Icons.access_time_filled_rounded,
              color: AppTheme.error,
            ),
            const _KpiCard(
              title: 'AI Verification Rate',
              value: '99.1%',
              change: '+0.2% on-site',
              icon: Icons.verified_user_rounded,
              color: AppTheme.success,
            ),
          ],
        );
      },
    );
  }

  Widget _buildIncidentTriageTable(BuildContext context, List<ComplaintItem> complaints, List<dynamic> cases) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF131D31),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1E293B)),
          boxShadow: AppTheme.shadowSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Live Incident & Triage Routing Feed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                      SizedBox(height: 2),
                      Text('Automated AI defect dispatch to Civil, PWD, and Electrical divisions with SLA countdowns.', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                    ],
                  ),
                  FilledButton.icon(
                    onPressed: () => widget.onNavigateTab(AppTab.workOrders),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Open Full Board'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF1E293B)),
            if (complaints.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No complaints logged in system', style: TextStyle(color: Color(0xFF64748B)))),
              )
            else
              ...complaints.map(
                (c) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.report_problem_rounded, color: AppTheme.error, size: 18),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
                            const SizedBox(height: 2),
                            Text('Category: ${c.category} • Zone: ${c.zone}', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(c.department, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE2E8F0))),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          c.status.displayName.toUpperCase(),
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SubTabPill extends StatelessWidget {
  const _SubTabPill({
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
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: Material(
        color: isSelected ? AppTheme.primary : const Color(0xFF131D31),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? AppTheme.primary : const Color(0xFF1E293B),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.change,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String change;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF131D31),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 2),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3),
                    ),
                    Text(
                      change,
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: color),
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
}
