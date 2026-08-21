import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/case_item.dart';
import '../../repositories/app_storage.dart';

class CasesWorkspace extends StatefulWidget {
  const CasesWorkspace({super.key});

  @override
  State<CasesWorkspace> createState() => _CasesWorkspaceState();
}

class _CasesWorkspaceState extends State<CasesWorkspace> {
  String _selectedStatus = 'All';

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);

    return ListenableBuilder(
      listenable: AppStorage.instance,
      builder: (context, _) {
        final storage = AppStorage.instance;
        final cases = storage.casesList;

        final filtered = cases.where((c) {
          if (_selectedStatus == 'Active') return c.status != CaseStatus.resolved;
          if (_selectedStatus == 'Awaiting Verification') return c.status == CaseStatus.awaitingVerification || c.status == CaseStatus.repairCompleted;
          if (_selectedStatus == 'Resolved') return c.status == CaseStatus.resolved;
          return true;
        }).toList();

        return SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 14 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header
              _buildHeader(context),
              const SizedBox(height: 18),

              // 2. Filter Bar
              _buildFilterBar(context, cases),
              const SizedBox(height: 18),

              // 3. Work Order Cards
              if (filtered.isEmpty)
                _buildEmptyState(context)
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, idx) => _buildCaseCard(context, filtered[idx]),
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.accentBlueLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.assignment_turned_in_rounded, color: AppTheme.accentBlue, size: 24),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Maintenance Work Orders & Verification Cases',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
                SizedBox(height: 2),
                Text(
                  'Manage contractor repair lifecycles, SLA countdowns, and Before/After visual verification.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context, List<CaseItem> all) {
    final filters = [
      'All (${all.length})',
      'Active (${all.where((c) => c.status != CaseStatus.resolved).length})',
      'Awaiting Verification (${all.where((c) => c.status == CaseStatus.repairCompleted || c.status == CaseStatus.awaitingVerification).length})',
      'Resolved (${all.where((c) => c.status == CaseStatus.resolved).length})',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final key = f.split(' (').first;
            final isSel = _selectedStatus == key;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(f, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isSel ? Colors.white : AppTheme.textPrimary)),
                selected: isSel,
                selectedColor: AppTheme.primary,
                onSelected: (_) => setState(() => _selectedStatus = key),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCaseCard(BuildContext context, CaseItem item) {
    final isResolved = item.status == CaseStatus.resolved;

    Color statusColor;
    switch (item.status) {
      case CaseStatus.assigned:
        statusColor = AppTheme.accentBlue;
        break;
      case CaseStatus.inProgress:
        statusColor = AppTheme.warning;
        break;
      case CaseStatus.repairCompleted:
      case CaseStatus.awaitingVerification:
        statusColor = AppTheme.purple;
        break;
      case CaseStatus.resolved:
        statusColor = AppTheme.success;
        break;
    }

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
                decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(2)),
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
                          '${item.id} • Linked to ${item.complaintId}',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.status.displayName,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
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
                      '${item.department} • Assigned: ${item.assignedTeam} (${item.assignedEngineer})',
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
                    item.isOverdue ? Icons.warning_amber_rounded : Icons.schedule_rounded,
                    size: 14,
                    color: item.isOverdue ? AppTheme.error : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.isOverdue
                        ? 'SLA BREACHED'
                        : 'SLA: ${item.remainingTime.inHours > 0 ? '${item.remainingTime.inHours}h remaining' : 'Due soon'}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: item.isOverdue ? AppTheme.error : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isResolved)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.success,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                      onPressed: () => _openVerificationModal(context, item),
                      icon: const Icon(Icons.verified_rounded, size: 14),
                      label: const Text('Verify & Close Case'),
                    ),
                  if (isResolved)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.successLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded, size: 14, color: AppTheme.success),
                          SizedBox(width: 4),
                          Text('Repaired & Verified', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.successDark)),
                        ],
                      ),
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
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined, size: 48, color: AppTheme.textMuted),
          SizedBox(height: 14),
          Text('No Maintenance Cases Found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
          SizedBox(height: 4),
          Text('Dispatch a complaint ticket to issue a new maintenance work order.', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Future<void> _openVerificationModal(BuildContext context, CaseItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final notesCtrl = TextEditingController(text: 'Physical site re-inspection verified. Asphalt patch flush with road surface.');

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.verified_rounded, color: AppTheme.success, size: 22),
            SizedBox(width: 10),
            Text('Before vs After Repair Verification', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Audit verification for Work Order ${item.id}:', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              const SizedBox(height: 16),

              // Side by side verification cards
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.bgSurfaceSubtle,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.broken_image_outlined, size: 32, color: AppTheme.error),
                          SizedBox(height: 6),
                          Text('BEFORE (Defect Sighting)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.error)),
                          Text('Original fault image logged', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.successLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.task_alt_rounded, size: 32, color: AppTheme.success),
                          SizedBox(height: 6),
                          Text('AFTER (Post-Repair)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.successDark)),
                          Text('Site cleared & restored', style: TextStyle(fontSize: 10, color: AppTheme.successDark)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              const Text('Inspector Sign-off Remarks', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
              const SizedBox(height: 4),
              TextField(controller: notesCtrl, maxLines: 2, decoration: const InputDecoration(hintText: 'Add clearance remarks…')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_circle_rounded, size: 16),
            label: const Text('Pass Inspection & Close Ticket'),
          ),
        ],
      ),
    );

    if (res == true && mounted) {
      await AppStorage.instance.verifyAndCloseCase(
        workOrder: item,
        afterEvidencePath: 'verified_site_photo.jpg',
        verificationNotes: notesCtrl.text.trim(),
      );

      messenger.showSnackBar(
        SnackBar(
          content: Text('Case ${item.id} verified and closed successfully.'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
