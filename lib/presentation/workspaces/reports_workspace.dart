import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_theme.dart';
import '../../models/complaint_item.dart';
import '../../repositories/app_storage.dart';

class ReportsWorkspace extends StatelessWidget {
  const ReportsWorkspace({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);

    return ListenableBuilder(
      listenable: AppStorage.instance,
      builder: (context, _) {
        final complaints = AppStorage.instance.complaintsList;
        final cases = AppStorage.instance.casesList;

        return SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 14 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header
              _buildHeader(context),
              const SizedBox(height: 18),

              // 2. Printable Work Order Slips
              if (complaints.isEmpty)
                _buildEmptyState(context)
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: complaints.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, idx) {
                    final comp = complaints[idx];
                    final linkedCase = cases.cast<dynamic>().firstWhere(
                          (c) => c.complaintId == comp.id,
                          orElse: () => null,
                        );
                    return _buildPrintableSlip(context, comp, linkedCase);
                  },
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
      child: const Row(
        children: [
          Icon(Icons.print_rounded, color: AppTheme.primary, size: 24),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Audit Reports & Printable Work Order Slips',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
                SizedBox(height: 2),
                Text(
                  'Generate standardized ISO-55000 / PWD maintenance slips for field engineers and contractor sign-off.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrintableSlip(BuildContext context, ComplaintItem comp, dynamic linkedCase) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 1.5),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Slip Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'INFRAVISION MUNICIPAL INFRASTRUCTURE DEFECT REPORT',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.primary, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Ticket Ref: ${comp.id} • Issued: ${comp.createdAt.toLocal().toString().split('.').first}',
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.textMuted),
                  ),
                ],
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: 'INFRAVISION DEFECT SLIP\nID: ${comp.id}\nTitle: ${comp.title}\nCategory: ${comp.category}\nZone: ${comp.zone}\nSeverity: ${comp.severity.displayName}\nDepartment: ${comp.department}'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Report details copied to clipboard.'), behavior: SnackBarBehavior.floating),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: const Text('Export Slip'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: AppTheme.border),
          const SizedBox(height: 14),

          // Defect Details Table
          Table(
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(5),
            },
            children: [
              _buildTableRow('Defect Title:', comp.title),
              _buildTableRow('Classification Category:', comp.category),
              _buildTableRow('Geospatial Location / Zone:', comp.zone),
              _buildTableRow('Severity Level:', '${comp.severity.displayName} (Risk Score: ${(comp.severityScore * 100).toStringAsFixed(0)}%)'),
              _buildTableRow('Responsible Department:', comp.department),
              _buildTableRow('Current Status:', comp.status.displayName),
              _buildTableRow('Field Remarks:', comp.inspectorNotes.isEmpty ? 'Standard routine inspection finding.' : comp.inspectorNotes),
            ],
          ),
          const SizedBox(height: 16),

          // Sign-off signature footer
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
                    Text('Contractor Team Sign-off:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.textMuted)),
                    SizedBox(height: 14),
                    Text('___________________________', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Executive Engineer Approval: (${linkedCase?.assignedEngineer ?? "Er. Duty Officer"})', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.textMuted)),
                    const SizedBox(height: 14),
                    const Text('___________________________', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TableRow _buildTableRow(String label, String value) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        ),
      ],
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
          Icon(Icons.description_outlined, size: 48, color: AppTheme.textMuted),
          SizedBox(height: 14),
          Text('No Defect Reports Available', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
          SizedBox(height: 4),
          Text('Logged complaints automatically generate printable work order slips here.', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}
