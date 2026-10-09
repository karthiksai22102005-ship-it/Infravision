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
  String _activeFilter = 'ALL'; // ALL, CRITICAL, IN_PROGRESS, RESOLVED
  String _searchQuery = '';

  // Material Form Controllers
  final _asphaltController = TextEditingController(text: '2.5 m³ (Asphalt Type-II)');
  final _sealerController = TextEditingController(text: 'Polymer Modified Cold-Pour Sealer');
  final _hoursController = TextEditingController(text: '3.5 Crew Man-Hours');
  final _technicianSignController = TextEditingController(text: 'Er. Sandeep Verma (Lead Field Engineer)');

  @override
  void dispose() {
    _asphaltController.dispose();
    _sealerController.dispose();
    _hoursController.dispose();
    _technicianSignController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgCanvas,
      appBar: AppBar(
        backgroundColor: AppTheme.bgSurface,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.engineering_rounded, color: AppTheme.warning, size: 20),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'Resolution Operations Portal',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
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
                'RESOLUTION CREW',
                style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppTheme.warning),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
            onPressed: () => setState(() {}),
            tooltip: 'Refresh Assignments',
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppTheme.textSecondary),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Switch Portal',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListenableBuilder(
        listenable: AppStorage.instance,
        builder: (context, _) {
          final allCases = AppStorage.instance.casesList;

          if (_showCameraOverlay && _selectedCase != null) {
            return _buildGuidedCameraView(context);
          }

          if (_showMaterialsLog && _selectedCase != null) {
            return _buildMaterialsLogView(context);
          }

          return _buildAssignmentsDashboard(context, allCases);
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ASSIGNMENTS DASHBOARD
  // ---------------------------------------------------------------------------
  Widget _buildAssignmentsDashboard(BuildContext context, List<CaseItem> allCases) {
    final activeCases = allCases.where((c) => c.status != CaseStatus.resolved).toList();
    final resolvedCases = allCases.where((c) => c.status == CaseStatus.resolved).toList();
    final inProgressCases = allCases.where((c) => c.status == CaseStatus.inProgress).toList();
    final criticalCases = allCases.where((c) => c.priority.toLowerCase().contains('critical')).toList();

    // Filter according to active selection
    final filtered = allCases.where((c) {
      if (_activeFilter == 'CRITICAL' && !c.priority.toLowerCase().contains('critical')) {
        return false;
      }
      if (_activeFilter == 'IN_PROGRESS' && c.status != CaseStatus.inProgress) {
        return false;
      }
      if (_activeFilter == 'RESOLVED' && c.status != CaseStatus.resolved) {
        return false;
      }
      if (_activeFilter == 'ALL' && c.status == CaseStatus.resolved) {
        return false; // Show active by default under ALL
      }

      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchTitle = c.title.toLowerCase().contains(query);
        final matchId = c.id.toLowerCase().contains(query);
        final matchTeam = c.assignedTeam.toLowerCase().contains(query);
        final matchDept = c.department.toLowerCase().contains(query);
        if (!matchTitle && !matchId && !matchTeam && !matchDept) {
          return false;
        }
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
              // Header & KPI Metrics Bar
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
                        'Assigned Work Orders & Remediation Queue',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppTheme.textPrimary),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'ISO-55000 maintenance dispatch, geofenced evidence capture, and materials logging.',
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_rounded, color: AppTheme.success, size: 14),
                        SizedBox(width: 6),
                        Text(
                          'SLA COMPLIANCE: 98.4%',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppTheme.success),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // KPI Cards Grid
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
                        title: 'ACTIVE WORK ORDERS',
                        value: '${activeCases.length}',
                        subtitle: '${criticalCases.length} Critical 24h urgency',
                        icon: Icons.assignment_rounded,
                        color: AppTheme.warning,
                      ),
                      _buildKpiCard(
                        title: 'CREW IN-PROGRESS',
                        value: '${inProgressCases.length}',
                        subtitle: 'Dispatched to field sites',
                        icon: Icons.handyman_rounded,
                        color: AppTheme.cyan,
                      ),
                      _buildKpiCard(
                        title: 'RESOLVED & VERIFIED',
                        value: '${resolvedCases.length}',
                        subtitle: 'Closed with QA proof',
                        icon: Icons.check_circle_rounded,
                        color: AppTheme.success,
                      ),
                      _buildKpiCard(
                        title: 'CREW READINESS',
                        value: 'ONLINE (100%)',
                        subtitle: 'Rapid Response Unit Alpha',
                        icon: Icons.speed_rounded,
                        color: AppTheme.purple,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),

              // Filter Chips & Search Bar
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildFilterChip('Active Orders (${activeCases.length})', 'ALL'),
                      _buildFilterChip('Critical SLA (${criticalCases.length})', 'CRITICAL'),
                      _buildFilterChip('In Progress (${inProgressCases.length})', 'IN_PROGRESS'),
                      _buildFilterChip('Resolved (${resolvedCases.length})', 'RESOLVED'),
                    ],
                  ),
                  SizedBox(
                    width: 260,
                    height: 38,
                    child: TextField(
                      style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search case, team, Dept...',
                        hintStyle: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        prefixIcon: const Icon(Icons.search_rounded, size: 16, color: AppTheme.textSecondary),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        filled: true,
                        fillColor: AppTheme.bgSurface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.border)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.warning)),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Work Order List Items
              if (filtered.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.done_all_rounded, color: AppTheme.success.withValues(alpha: 0.6), size: 44),
                      const SizedBox(height: 12),
                      const Text(
                        'No matching work orders found in this view.',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'All assigned remediation tasks for this filter are up to date.',
                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  itemBuilder: (context, idx) {
                    final item = filtered[idx];
                    return _buildWorkOrderCard(context, item);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String code) {
    final isSelected = _activeFilter == code;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      selectedColor: AppTheme.warning.withValues(alpha: 0.25),
      side: BorderSide(color: isSelected ? AppTheme.warning : AppTheme.border),
      onSelected: (val) {
        if (val) {
          setState(() => _activeFilter = code);
        }
      },
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
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppTheme.textMuted, letterSpacing: 0.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
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

  Widget _buildWorkOrderCard(BuildContext context, CaseItem item) {
    final isResolved = item.status == CaseStatus.resolved;
    final isInProgress = item.status == CaseStatus.inProgress;
    final isCritical = item.priority.toLowerCase().contains('critical');

    return Card(
      color: AppTheme.bgSurface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isCritical && !isResolved ? AppTheme.warning.withValues(alpha: 0.4) : AppTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Badge Row
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isResolved
                            ? AppTheme.success.withValues(alpha: 0.15)
                            : isCritical
                                ? AppTheme.error.withValues(alpha: 0.15)
                                : AppTheme.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isResolved
                              ? AppTheme.success
                              : isCritical
                                  ? AppTheme.error
                                  : AppTheme.warning,
                        ),
                      ),
                      child: Text(
                        item.priority.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: isResolved
                              ? AppTheme.success
                              : isCritical
                                  ? AppTheme.error
                                  : AppTheme.warning,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isInProgress ? AppTheme.cyan.withValues(alpha: 0.15) : AppTheme.purple.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.status.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isInProgress ? AppTheme.cyan : AppTheme.purple,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  isResolved ? 'Resolved & Verified' : 'SLA Target: Within 24h Window',
                  style: TextStyle(fontSize: 10, color: isResolved ? AppTheme.success : AppTheme.cyan, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Title
            Text(
              item.title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 4),

            // Subtitle metadata
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  'Work Order ID: ${item.id}',
                  style: const TextStyle(fontSize: 10.5, color: AppTheme.textSecondary, fontFamily: 'monospace'),
                ),
                Text(
                  'Dept: ${item.department}',
                  style: const TextStyle(fontSize: 10.5, color: AppTheme.textSecondary),
                ),
                Text(
                  'Team: ${item.assignedTeam}',
                  style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                ),
                Text(
                  'Lead: ${item.assignedEngineer}',
                  style: const TextStyle(fontSize: 10.5, color: AppTheme.cyan),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Action Buttons
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.cyan,
                    side: const BorderSide(color: AppTheme.cyan),
                  ),
                  onPressed: () => _showBeforePhotoDialog(context, item),
                  icon: const Icon(Icons.image_search_rounded, size: 14),
                  label: const Text('View Before-Photo', style: TextStyle(fontSize: 11)),
                ),
                if (!isResolved && !isInProgress)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.cyan,
                    ),
                    onPressed: () {
                      AppStorage.instance.updateCaseStatus(item.id, CaseStatus.inProgress);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Dispatched: ${item.id} moved to In-Progress status.'),
                          backgroundColor: AppTheme.cyan,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.directions_run_rounded, size: 14),
                    label: const Text('Start Repair / Dispatch', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                if (!isResolved)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.warning),
                    onPressed: () {
                      setState(() {
                        _selectedCase = item;
                        _showCameraOverlay = true;
                      });
                    },
                    icon: const Icon(Icons.camera_alt_rounded, size: 14),
                    label: const Text('Mark Fixed', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                if (isResolved)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 14),
                        SizedBox(width: 6),
                        Text(
                          'QA Closed • Verified by Inspector',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.success),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showBeforePhotoDialog(BuildContext context, CaseItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.image_search_rounded, color: AppTheme.cyan, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Defect Evidence: ${item.id}',
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF070B14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.warning_amber_rounded, color: AppTheme.warning.withValues(alpha: 0.8), size: 44),
                            const SizedBox(height: 8),
                            Text(item.title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                            const SizedBox(height: 4),
                            const Text('AI Tensor Defect Segmentation Layer #1', style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted)),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
                        child: const Text('BEFORE REPAIR PROOF', style: TextStyle(fontSize: 8.5, color: AppTheme.cyan, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      left: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          'Geodesic GPS: 17.3850° N, 78.4866° E • Dept: ${item.department}',
                          style: const TextStyle(fontSize: 9, color: AppTheme.textSecondary, fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Remediation Protocol Guidelines:',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 4),
              const Text(
                '• Ensure surface is cleaned of moisture and loose aggregates prior to hot-pour sealing.\n• Compact with minimum 2-ton vibratory roller for uniform planarity.\n• Capture after-repair photograph from identical vantage point using ghost camera.',
                style: TextStyle(fontSize: 10, color: AppTheme.textSecondary, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Close Preview', style: TextStyle(fontSize: 12)),
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Guided After-Repair Photographic Validation',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Work Order: ${_selectedCase?.id} • ${_selectedCase?.title}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                  OutlinedButton(
                    onPressed: () => setState(() => _showCameraOverlay = false),
                    child: const Text('Cancel', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Viewfinder Container
              Container(
                height: 340,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF070B14),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Ghost overlay reference box
                    Container(
                      margin: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.5), width: 2),
                        color: AppTheme.cyan.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.filter_center_focus_rounded, color: AppTheme.cyan.withValues(alpha: 0.8), size: 48),
                            const SizedBox(height: 12),
                            const Text(
                              'ALIGN COMPLETED REPAIR TO GHOST OVERLAY REFERENCE',
                              style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Target Defect Zone: ${_selectedCase?.title}',
                              style: const TextStyle(fontSize: 9, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Top Telemetry Bar
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'ANGULAR ALIGNMENT: 98.2% MATCH',
                              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppTheme.success, fontFamily: 'monospace'),
                            ),
                            Text(
                              'GPS LOCK: ±0.5m',
                              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppTheme.cyan, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Action Bar
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.warning,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        setState(() {
                          _showCameraOverlay = false;
                          _showMaterialsLog = true;
                        });
                      },
                      icon: const Icon(Icons.camera_alt_rounded),
                      label: const Text('Capture & Proceed to Materials Log', style: TextStyle(fontWeight: FontWeight.bold)),
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

  // ---------------------------------------------------------------------------
  // MATERIALS & TIME LOG VIEW
  // ---------------------------------------------------------------------------
  Widget _buildMaterialsLogView(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Close Work Order & Log Bill of Materials (BOM)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                'Record the exact physical resources, paving volumes, and crew hours for Case ${_selectedCase?.id}.',
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),

              // Form fields in cards
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _asphaltController,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Asphalt / Concrete Volume Consumed',
                        labelStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        prefixIcon: Icon(Icons.grain_rounded, size: 18, color: AppTheme.cyan),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.warning)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    TextField(
                      controller: _sealerController,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Sealant / Hydraulic Compound Grade',
                        labelStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        prefixIcon: Icon(Icons.format_paint_rounded, size: 18, color: AppTheme.cyan),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.warning)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    TextField(
                      controller: _hoursController,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Total Crew Man-Hours Billed',
                        labelStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        prefixIcon: Icon(Icons.timer_rounded, size: 18, color: AppTheme.cyan),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.warning)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    TextField(
                      controller: _technicianSignController,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Certified Lead Engineer Digital Signature',
                        labelStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        prefixIcon: Icon(Icons.verified_user_rounded, size: 18, color: AppTheme.success),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.success)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => setState(() => _showMaterialsLog = false),
                      child: const Text('Back to Camera'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.success,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _finalizeCaseRepair(context),
                      icon: const Icon(Icons.verified_rounded),
                      label: const Text('Submit Fix Verification File', style: TextStyle(fontWeight: FontWeight.bold)),
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

  void _finalizeCaseRepair(BuildContext context) async {
    final storage = AppStorage.instance;
    if (_selectedCase != null) {
      final messenger = ScaffoldMessenger.of(context);
      await storage.verifyAndCloseCase(
        workOrder: _selectedCase!,
        afterEvidencePath: 'evidence/images/after_repair_01.jpg',
        verificationPassed: true,
        verificationNotes: 'Contractor auto-log: asphalt=${_asphaltController.text}, sealer=${_sealerController.text}, duration=${_hoursController.text}, signedBy=${_technicianSignController.text}',
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text('Repair file verified and submitted for ${_selectedCase!.id}.'),
          backgroundColor: AppTheme.success,
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
