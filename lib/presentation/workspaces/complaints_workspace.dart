import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/complaint_item.dart';
import '../../repositories/app_storage.dart';

class ComplaintsWorkspace extends StatefulWidget {
  const ComplaintsWorkspace({super.key});

  @override
  State<ComplaintsWorkspace> createState() => _ComplaintsWorkspaceState();
}

class _ComplaintsWorkspaceState extends State<ComplaintsWorkspace> {
  String _searchQuery = '';
  String _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);

    return ListenableBuilder(
      listenable: AppStorage.instance,
      builder: (context, _) {
        final storage = AppStorage.instance;
        final allComplaints = storage.complaintsList;

        final filtered = allComplaints.where((c) {
          final matchesSearch = c.id.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              c.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              c.zone.toLowerCase().contains(_searchQuery.toLowerCase());

          if (!matchesSearch) return false;

          switch (_selectedFilter) {
            case 'Critical':
              return c.severity == ComplaintSeverity.critical;
            case 'Dispatched':
              return c.status == ComplaintStatus.dispatched;
            case 'Resolved':
              return c.status == ComplaintStatus.resolved;
            case 'Pending':
              return c.status == ComplaintStatus.submitted || c.status == ComplaintStatus.triaged;
            default:
              return true;
          }
        }).toList();

        return SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 14 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header & Actions
              _buildHeader(context),
              const SizedBox(height: 18),

              // 2. Search & Filter Bar
              _buildFilterBar(context, allComplaints),
              const SizedBox(height: 18),

              // 3. Complaints Table / Card List
              if (filtered.isEmpty)
                _buildEmptyState(context)
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, idx) => _buildComplaintCard(context, filtered[idx]),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(14),
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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.warningLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.report_gmailerrorred_rounded, color: AppTheme.warning, size: 24),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Infrastructure Complaints & Grievance Intake',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Triage, prioritize, and dispatch infrastructure defects across municipal divisions.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ],
          ),
          FilledButton.icon(
            onPressed: () => _openNewComplaintDialog(context),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Log New Complaint'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context, List<ComplaintItem> all) {
    final filters = [
      'All (${all.length})',
      'Pending (${all.where((c) => c.status == ComplaintStatus.submitted || c.status == ComplaintStatus.triaged).length})',
      'Critical (${all.where((c) => c.severity == ComplaintSeverity.critical).length})',
      'Dispatched (${all.where((c) => c.status == ComplaintStatus.dispatched).length})',
      'Resolved (${all.where((c) => c.status == ComplaintStatus.resolved).length})',
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search by Complaint ID (e.g. CMP-2026-0842), title, or location zone…',
              prefixIcon: Icon(Icons.search_rounded, size: 18, color: AppTheme.textSecondary),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: filters.map((f) {
                final key = f.split(' ').first;
                final isSel = _selectedFilter == key;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isSel ? Colors.white : AppTheme.textPrimary)),
                    selected: isSel,
                    selectedColor: AppTheme.primary,
                    onSelected: (_) => setState(() => _selectedFilter = key),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComplaintCard(BuildContext context, ComplaintItem item) {
    Color sevColor;
    switch (item.severity) {
      case ComplaintSeverity.critical:
        sevColor = AppTheme.error;
        break;
      case ComplaintSeverity.high:
        sevColor = AppTheme.warning;
        break;
      case ComplaintSeverity.moderate:
        sevColor = AppTheme.accentBlue;
        break;
      case ComplaintSeverity.low:
        sevColor = AppTheme.success;
        break;
    }

    final isResolved = item.status == ComplaintStatus.resolved;

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 48,
                decoration: BoxDecoration(
                  color: sevColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          item.id,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isResolved ? AppTheme.successLight : (item.status == ComplaintStatus.dispatched ? AppTheme.accentBlueLight : AppTheme.warningLight),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.status.displayName,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isResolved ? AppTheme.successDark : (item.status == ComplaintStatus.dispatched ? AppTheme.accentBlue : AppTheme.warningDark),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.title,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.category} • Zone: ${item.zone}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 12),

          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    item.isOverdue ? Icons.timer_off_rounded : Icons.timer_outlined,
                    size: 14,
                    color: item.isOverdue ? AppTheme.error : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.isOverdue
                        ? 'SLA OVERDUE'
                        : 'SLA: ${item.remainingTime.inHours > 0 ? '${item.remainingTime.inHours}h remaining' : 'Due soon'}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: item.isOverdue ? AppTheme.error : AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Dept: ${item.department}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.status != ComplaintStatus.dispatched && item.status != ComplaintStatus.resolved)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                      onPressed: () => _openDispatchDialog(context, item),
                      icon: const Icon(Icons.send_rounded, size: 14),
                      label: const Text('Dispatch Case'),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inventory_2_outlined, size: 48, color: AppTheme.textMuted),
          const SizedBox(height: 14),
          const Text('No Complaints Found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
          const SizedBox(height: 4),
          const Text('No grievance records match the selected filter criteria.', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _searchQuery = '';
              _selectedFilter = 'All';
            }),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Reset Filters'),
          ),
        ],
      ),
    );
  }

  Future<void> _openNewComplaintDialog(BuildContext context) async {
    final titleCtrl = TextEditingController();
    final zoneCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String category = 'Road & Pavement Hazards';
    ComplaintSeverity severity = ComplaintSeverity.high;

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.add_task_rounded, color: AppTheme.primary, size: 22),
              SizedBox(width: 10),
              Text('Log Infrastructure Complaint Ticket', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Title / Description', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  TextField(controller: titleCtrl, decoration: const InputDecoration(hintText: 'e.g. Broken Paver Blocks on Walkway')),
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

                  const Text('Campus / Ward / GPS Zone', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  TextField(controller: zoneCtrl, decoration: const InputDecoration(hintText: 'e.g. Science Block Skywalk Link')),
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

                  const Text('Inspector Remarks', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  TextField(controller: notesCtrl, maxLines: 2, decoration: const InputDecoration(hintText: 'Add initial field triage remarks…')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: () {
                if (titleCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Save & Submit'),
            ),
          ],
        ),
      ),
    );

    if (res == true && mounted) {
      await AppStorage.instance.logComplaint(
        title: titleCtrl.text.trim(),
        category: category,
        zone: zoneCtrl.text.trim(),
        severity: severity,
        severityScore: severity == ComplaintSeverity.critical ? 0.95 : (severity == ComplaintSeverity.high ? 0.85 : 0.6),
        evidencePaths: [],
        inspectorNotes: notesCtrl.text.trim(),
      );
    }
  }

  Future<void> _openDispatchDialog(BuildContext context, ComplaintItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final teamCtrl = TextEditingController(text: 'Rapid Response Unit 1');
    final engineerCtrl = TextEditingController(text: 'Er. Sandeep Verma');

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.send_rounded, color: AppTheme.primary, size: 20),
            SizedBox(width: 10),
            Text('Dispatch Work Order Case', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Convert ${item.id} into an active maintenance work order and assign contractor crew:', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              const SizedBox(height: 14),
              const Text('Assigned Crew / Team', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
              const SizedBox(height: 4),
              TextField(controller: teamCtrl, decoration: const InputDecoration(hintText: 'e.g. Structural Crew #2')),
              const SizedBox(height: 12),
              const Text('Supervising Engineer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
              const SizedBox(height: 4),
              TextField(controller: engineerCtrl, decoration: const InputDecoration(hintText: 'e.g. Er. P. K. Singh')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text('Confirm Dispatch'),
          ),
        ],
      ),
    );

    if (res == true && mounted) {
      final workOrder = await AppStorage.instance.dispatchWorkOrder(
        complaint: item,
        assignedTeam: teamCtrl.text.trim(),
        assignedEngineer: engineerCtrl.text.trim(),
      );

      messenger.showSnackBar(
        SnackBar(
          content: Text('Work Order ${workOrder.id} dispatched successfully.'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
