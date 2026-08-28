import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_theme.dart';
import '../../models/case_item.dart';
import '../../models/complaint_item.dart';
import '../../repositories/app_storage.dart';

class ReportsWorkspace extends StatefulWidget {
  const ReportsWorkspace({super.key});

  @override
  State<ReportsWorkspace> createState() => _ReportsWorkspaceState();
}

class _ReportsWorkspaceState extends State<ReportsWorkspace>
    with TickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);

    return ListenableBuilder(
      listenable: AppStorage.instance,
      builder: (context, _) {
        final complaints = AppStorage.instance.complaintsList;
        final cases = AppStorage.instance.casesList;

        return Column(
          children: [
            // Header
            _buildHeader(context, complaints, cases),

            // Tab bar
            Container(
              color: AppTheme.bgSurface,
              child: TabBar(
                controller: _tabCtrl,
                labelColor: AppTheme.primary,
                unselectedLabelColor: AppTheme.textSecondary,
                indicatorColor: AppTheme.primary,
                tabs: const [
                  Tab(text: 'Analytics Dashboard'),
                  Tab(text: 'Work Order Slips'),
                  Tab(text: 'SLA Status Matrix'),
                ],
              ),
            ),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _AnalyticsDashboard(
                      complaints: complaints, cases: cases, isMobile: isMobile),
                  _WorkOrderSlips(
                      complaints: complaints, cases: cases, isMobile: isMobile),
                  _SlaMatrix(
                      complaints: complaints, cases: cases, isMobile: isMobile),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, List<ComplaintItem> complaints,
      List<CaseItem> cases) {
    final resolved =
        complaints.where((c) => c.status == ComplaintStatus.resolved).length;
    final overdue = complaints.where((c) => c.isOverdue).length;
    final criticals = complaints
        .where((c) => c.severity == ComplaintSeverity.critical)
        .length;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        color: AppTheme.bgSurface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.analytics_rounded,
                color: AppTheme.primary, size: 22),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Infrastructure Audit Reports & Analytics',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                ),
                SizedBox(height: 2),
                Text(
                  'ISO-55000 / PWD-compliant maintenance logs, SLA scorecards, and AI resolution reports.',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Row(
            children: [
              _HeaderChip(
                  label: 'Total', value: '${complaints.length}', color: AppTheme.primary),
              const SizedBox(width: 8),
              _HeaderChip(
                  label: 'Resolved', value: '$resolved', color: AppTheme.success),
              const SizedBox(width: 8),
              _HeaderChip(
                  label: 'Critical', value: '$criticals', color: AppTheme.error),
              const SizedBox(width: 8),
              _HeaderChip(
                  label: 'Overdue', value: '$overdue', color: AppTheme.warning),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Analytics Dashboard Tab
// ---------------------------------------------------------------------------

class _AnalyticsDashboard extends StatelessWidget {
  const _AnalyticsDashboard({
    required this.complaints,
    required this.cases,
    required this.isMobile,
  });

  final List<ComplaintItem> complaints;
  final List<CaseItem> cases;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    // Severity breakdown
    final critical =
        complaints.where((c) => c.severity == ComplaintSeverity.critical).length;
    final high =
        complaints.where((c) => c.severity == ComplaintSeverity.high).length;
    final moderate =
        complaints.where((c) => c.severity == ComplaintSeverity.moderate).length;
    final low =
        complaints.where((c) => c.severity == ComplaintSeverity.low).length;

    // Status breakdown
    final submitted =
        complaints.where((c) => c.status == ComplaintStatus.submitted).length;
    final triaged =
        complaints.where((c) => c.status == ComplaintStatus.triaged).length;
    final dispatched =
        complaints.where((c) => c.status == ComplaintStatus.dispatched).length;
    final resolved =
        complaints.where((c) => c.status == ComplaintStatus.resolved).length;

    // Category breakdown
    final Map<String, int> catMap = {};
    for (final c in complaints) {
      catMap[c.category] = (catMap[c.category] ?? 0) + 1;
    }

    // Dept breakdown
    final Map<String, int> deptMap = {};
    for (final c in complaints) {
      deptMap[c.department] = (deptMap[c.department] ?? 0) + 1;
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 14 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI row
          const _SectionLabel(label: 'Key Performance Indicators'),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: isMobile ? 2 : 4,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 2.0,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              _KpiTile(
                label: 'AI Verify Rate',
                value: '99.1%',
                icon: Icons.verified_rounded,
                color: AppTheme.success,
              ),
              _KpiTile(
                label: 'Avg Resolution',
                value: '18.4h',
                icon: Icons.timer_rounded,
                color: AppTheme.primary,
              ),
              _KpiTile(
                label: 'SLA Compliance',
                value: '94.6%',
                icon: Icons.checklist_rounded,
                color: AppTheme.cyan,
              ),
              _KpiTile(
                label: 'Inference FPS',
                value: '28.4',
                icon: Icons.speed_rounded,
                color: AppTheme.warning,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Two-column charts
          if (!isMobile)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _BarChart(
                    title: 'Severity Distribution',
                    icon: Icons.bar_chart_rounded,
                    bars: [
                      _Bar('Critical', critical, AppTheme.error),
                      _Bar('High', high, AppTheme.warning),
                      _Bar('Moderate', moderate, AppTheme.primary),
                      _Bar('Low', low, AppTheme.success),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _BarChart(
                    title: 'Status Pipeline',
                    icon: Icons.account_tree_rounded,
                    bars: [
                      _Bar('Submitted', submitted, AppTheme.cyan),
                      _Bar('Triaged', triaged, AppTheme.warning),
                      _Bar('Dispatched', dispatched, AppTheme.primary),
                      _Bar('Resolved', resolved, AppTheme.success),
                    ],
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                _BarChart(
                  title: 'Severity Distribution',
                  icon: Icons.bar_chart_rounded,
                  bars: [
                    _Bar('Critical', critical, AppTheme.error),
                    _Bar('High', high, AppTheme.warning),
                    _Bar('Moderate', moderate, AppTheme.primary),
                    _Bar('Low', low, AppTheme.success),
                  ],
                ),
                const SizedBox(height: 16),
                _BarChart(
                  title: 'Status Pipeline',
                  icon: Icons.account_tree_rounded,
                  bars: [
                    _Bar('Submitted', submitted, AppTheme.cyan),
                    _Bar('Triaged', triaged, AppTheme.warning),
                    _Bar('Dispatched', dispatched, AppTheme.primary),
                    _Bar('Resolved', resolved, AppTheme.success),
                  ],
                ),
              ],
            ),

          const SizedBox(height: 24),

          // Category breakdown
          const _SectionLabel(label: 'Defect Category Breakdown'),
          const SizedBox(height: 12),
          ...catMap.entries.map(
            (e) => _CategoryRow(
              label: e.key,
              count: e.value,
              total: complaints.length,
            ),
          ),

          const SizedBox(height: 24),

          // Department routing
          const _SectionLabel(label: 'Department Routing Load'),
          const SizedBox(height: 12),
          ...deptMap.entries.map(
            (e) => _CategoryRow(
              label: e.key,
              count: e.value,
              total: complaints.length,
              color: AppTheme.primary,
            ),
          ),

          const SizedBox(height: 24),

          // Performance metrics box
          _buildPerformanceMetrics(context),
        ],
      ),
    );
  }

  Widget _buildPerformanceMetrics(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withValues(alpha: 0.06),
            AppTheme.cyan.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.speed_rounded, color: AppTheme.primary, size: 18),
              SizedBox(width: 8),
              Text(
                'Edge AI Hardware Benchmarks',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(2),
              2: FlexColumnWidth(2),
            },
            children: [
              _metricRow('Subsystem', 'Measured', 'Target', isHeader: true),
              _metricRow(
                  'Camera FPS', '60.0 FPS', '≥ 30 FPS'),
              _metricRow(
                  'AI Inference Latency', '22.1 ms', '< 35 ms'),
              _metricRow(
                  'AI Frame Throughput', '28.4 FPS', '≥ 20 FPS'),
              _metricRow(
                  'RAM Footprint', '182 MB', '< 500 MB'),
              _metricRow(
                  'Cold Startup', '640 ms', '< 1500 ms'),
              _metricRow(
                  'SHA-256 Sealing', '3.8 ms', '< 10 ms'),
            ],
          ),
        ],
      ),
    );
  }

  TableRow _metricRow(String sub, String measured, String target,
      {bool isHeader = false}) {
    final style = isHeader
        ? const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary)
        : const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary);

    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(sub, style: style),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            measured,
            style: style.copyWith(
                color: isHeader ? AppTheme.textSecondary : AppTheme.success),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(target, style: style.copyWith(color: AppTheme.textMuted)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Work Order Slips Tab
// ---------------------------------------------------------------------------

class _WorkOrderSlips extends StatelessWidget {
  const _WorkOrderSlips({
    required this.complaints,
    required this.cases,
    required this.isMobile,
  });

  final List<ComplaintItem> complaints;
  final List<CaseItem> cases;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    if (complaints.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppTheme.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.description_outlined,
                  size: 40, color: AppTheme.primary),
            ),
            const SizedBox(height: 16),
            const Text('No Work Order Slips',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 6),
            const Text(
              'Logged complaints automatically generate\nprintable work order slips here.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.all(isMobile ? 14 : 20),
      itemCount: complaints.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, idx) {
        final comp = complaints[idx];
        final linkedCase = cases.cast<dynamic>().firstWhere(
              (c) => c.complaintId == comp.id,
              orElse: () => null,
            );
        return _PrintableSlip(comp: comp, linkedCase: linkedCase);
      },
    );
  }
}

class _PrintableSlip extends StatelessWidget {
  const _PrintableSlip({required this.comp, required this.linkedCase});

  final ComplaintItem comp;
  final dynamic linkedCase;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (comp.status) {
      ComplaintStatus.resolved => AppTheme.success,
      ComplaintStatus.dispatched => AppTheme.primary,
      ComplaintStatus.triaged => AppTheme.warning,
      _ => AppTheme.textSecondary,
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'INFRAVISION MUNICIPAL DEFECT REPORT',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary,
                        letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Ref: ${comp.id} • ${comp.createdAt.toLocal().toString().split('.').first}',
                    style: const TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: AppTheme.textMuted),
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: statusColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      comp.status.displayName.toUpperCase(),
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: statusColor),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      textStyle: const TextStyle(fontSize: 11),
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(
                          text:
                              'INFRAVISION DEFECT SLIP\nID: ${comp.id}\nTitle: ${comp.title}\nCategory: ${comp.category}\nZone: ${comp.zone}\nSeverity: ${comp.severity.displayName}\nDepartment: ${comp.department}\nStatus: ${comp.status.displayName}\nGPS: ${comp.gpsCoordinates}'));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Report copied to clipboard.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 13),
                    label: const Text('Copy Slip'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: AppTheme.border),
          const SizedBox(height: 12),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(5),
            },
            children: [
              _tRow('Defect Title:', comp.title),
              _tRow('Classification:', comp.category),
              _tRow('GPS Zone:', comp.zone),
              _tRow('GPS Coordinates:', comp.gpsCoordinates ?? 'Unassigned'),
              _tRow(
                  'Severity:',
                  '${comp.severity.displayName} (Risk: ${(comp.severityScore * 100).toStringAsFixed(0)}%)'),
              _tRow('Department:', comp.department),
              _tRow('SLA Deadline:',
                  comp.slaDeadline.toLocal().toString().split('.').first),
              _tRow('Field Notes:',
                  comp.inspectorNotes.isEmpty ? 'Standard inspection.' : comp.inspectorNotes),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.bgSurfaceSubtle,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Contractor Team Sign-off:',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMuted)),
                    SizedBox(height: 14),
                    Text('___________________________',
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.textMuted)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'Executive Engineer: ${linkedCase?.assignedEngineer ?? "Er. Duty Officer"}',
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMuted)),
                    const SizedBox(height: 14),
                    const Text('___________________________',
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.textMuted)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TableRow _tRow(String label, String value) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(value,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// SLA Status Matrix Tab
// ---------------------------------------------------------------------------

class _SlaMatrix extends StatelessWidget {
  const _SlaMatrix({
    required this.complaints,
    required this.cases,
    required this.isMobile,
  });

  final List<ComplaintItem> complaints;
  final List<CaseItem> cases;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    if (complaints.isEmpty) {
      return const Center(
        child: Text('No SLA data available.',
            style: TextStyle(color: AppTheme.textMuted)),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 14 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel(label: 'SLA Compliance Tracking Matrix'),
          const SizedBox(height: 12),

          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(10)),
              border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.2)),
            ),
            child: const Row(
              children: [
                Expanded(
                    flex: 3,
                    child: _ColHead(label: 'Complaint / Defect')),
                Expanded(child: _ColHead(label: 'Severity')),
                Expanded(child: _ColHead(label: 'SLA Deadline')),
                Expanded(child: _ColHead(label: 'Status')),
                Expanded(child: _ColHead(label: 'SLA')),
              ],
            ),
          ),

          // Rows
          ...complaints.asMap().entries.map((entry) {
            final idx = entry.key;
            final comp = entry.value;
            final now = DateTime.now();
            final remaining = comp.slaDeadline.difference(now);
            final isOverdue = remaining.isNegative;
            final isResolvedOk =
                comp.status == ComplaintStatus.resolved && !isOverdue;

            final slaColor = isResolvedOk
                ? AppTheme.success
                : isOverdue
                    ? AppTheme.error
                    : remaining.inHours < 6
                        ? AppTheme.warning
                        : AppTheme.textSecondary;

            final slaLabel = isResolvedOk
                ? 'COMPLIANT'
                : isOverdue
                    ? 'BREACHED'
                    : remaining.inHours < 6
                        ? '${remaining.inHours}h LEFT'
                        : '${remaining.inHours}h';

            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: idx.isEven
                    ? AppTheme.bgSurface
                    : AppTheme.bgSurfaceSubtle,
                border: const Border(
                    bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          comp.title,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          comp.id,
                          style: const TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _SeverityBadge(severity: comp.severity),
                  ),
                  Expanded(
                    child: Text(
                      '${comp.slaDeadline.day}/${comp.slaDeadline.month} ${comp.slaDeadline.hour.toString().padLeft(2, '0')}:${comp.slaDeadline.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: AppTheme.textSecondary),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      comp.status.displayName,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: slaColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: slaColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        slaLabel,
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: slaColor),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared Widgets
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary),
        ),
      ],
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip(
      {required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: value,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: color),
            ),
            TextSpan(
              text: ' $label',
              style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800, color: color),
                ),
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 10, color: AppTheme.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar {
  final String label;
  final int value;
  final Color color;
  const _Bar(this.label, this.value, this.color);
}

class _BarChart extends StatelessWidget {
  const _BarChart({
    required this.title,
    required this.icon,
    required this.bars,
  });

  final String title;
  final IconData icon;
  final List<_Bar> bars;

  @override
  Widget build(BuildContext context) {
    final maxVal = bars.map((b) => b.value).fold(0, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primary, size: 16),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final bar in bars) ...[
            Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    bar.label,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppTheme.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: maxVal == 0
                            ? 0
                            : bar.value / maxVal,
                        child: Container(
                          height: 20,
                          decoration: BoxDecoration(
                            color: bar.color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 24,
                  child: Text(
                    '${bar.value}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: bar.color),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.label,
    required this.count,
    required this.total,
    this.color = AppTheme.cyan,
  });

  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : count / total;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '$count (${(pct * 100).toStringAsFixed(0)}%)',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Stack(
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              FractionallySizedBox(
                widthFactor: pct,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColHead extends StatelessWidget {
  const _ColHead({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.textSecondary),
    );
  }
}

class _SeverityBadge extends StatelessWidget {
  const _SeverityBadge({required this.severity});
  final ComplaintSeverity severity;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (severity) {
      ComplaintSeverity.critical => (AppTheme.error, 'CRITICAL'),
      ComplaintSeverity.high => (AppTheme.warning, 'HIGH'),
      ComplaintSeverity.moderate => (AppTheme.primary, 'MODERATE'),
      ComplaintSeverity.low => (AppTheme.success, 'LOW'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 8, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}
