import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/case_item.dart';
import '../../repositories/app_storage.dart';

/// Dedicated AI Before-vs-After Repair Verification Workspace.
class VerificationWorkspace extends StatefulWidget {
  const VerificationWorkspace({super.key});

  @override
  State<VerificationWorkspace> createState() => _VerificationWorkspaceState();
}

class _VerificationWorkspaceState extends State<VerificationWorkspace> {
  int _selectedCaseIndex = 0;
  bool _isVerifying = false;
  bool _verificationPassed = true;
  final double _postRepairConfidence = 0.02; // 2% residual -> Clean repair

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStorage.instance,
      builder: (context, _) {
        final storage = AppStorage.instance;
        final cases = storage.casesList;

        if (cases.isEmpty) {
          return const Center(
            child: Text(
              'No active cases available for verification',
              style: TextStyle(color: AppTheme.textMuted),
            ),
          );
        }

        final activeCase = _selectedCaseIndex < cases.length ? cases[_selectedCaseIndex] : cases.first;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Header with Case Selector
              _buildCaseSelectorHeader(context, cases, activeCase),
              const SizedBox(height: 18),

              // Dual-Pane Before & After Comparison Grid
              _buildDualComparisonView(context, activeCase),
              const SizedBox(height: 18),

              // AI Verification Certificate & Action Bar
              _buildVerificationActionBar(context, storage, activeCase),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCaseSelectorHeader(BuildContext context, List<CaseItem> cases, CaseItem activeCase) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.fact_check_rounded, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Case ${activeCase.id}: ${activeCase.title}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  'Assigned Dept: ${activeCase.department} • Contractor: ${activeCase.assignedTeam}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
            ),
            child: Text(
              activeCase.status.displayName.toUpperCase(),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.warningDark),
            ),
          ),
          const SizedBox(width: 14),
          DropdownButton<int>(
            value: _selectedCaseIndex,
            underline: const SizedBox.shrink(),
            icon: const Icon(Icons.arrow_drop_down_rounded, color: AppTheme.primary),
            items: List.generate(
              cases.length,
              (i) => DropdownMenuItem(
                value: i,
                child: Text('Case #${cases[i].id}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
            onChanged: (val) {
              if (val != null) setState(() => _selectedCaseIndex = val);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDualComparisonView(BuildContext context, CaseItem activeCase) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;

        return isNarrow
            ? Column(
                children: [
                  _buildBeforeCard(activeCase),
                  const SizedBox(height: 14),
                  _buildAfterCard(activeCase),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildBeforeCard(activeCase)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildAfterCard(activeCase)),
                ],
              );
      },
    );
  }

  Widget _buildBeforeCard(CaseItem activeCase) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppTheme.error, size: 18),
                    SizedBox(width: 8),
                    Text('BEFORE REPAIR (ORIGINAL DEFECT)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.errorDark)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.error,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('DEFECT: 94%', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          Container(
            height: 220,
            width: double.infinity,
            color: const Color(0xFF1E293B),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF334155), Color(0xFF0F172A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Center(
                    child: Icon(Icons.broken_image_outlined, size: 48, color: Colors.white24),
                  ),
                ),
                // Simulated Bounding Box Overlay
                Center(
                  child: Container(
                    width: 140,
                    height: 100,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.error, width: 2.5),
                      borderRadius: BorderRadius.circular(6),
                      color: AppTheme.error.withValues(alpha: 0.15),
                    ),
                    alignment: Alignment.topLeft,
                    padding: const EdgeInsets.all(4),
                    child: Container(
                      color: AppTheme.error,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: const Text('POTHOLE 94%', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recorded: ${activeCase.createdAt.toString().split('.').first}', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                const Text('Severity: CRITICAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.error)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAfterCard(CaseItem activeCase) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.verified_rounded, color: AppTheme.success, size: 18),
                    SizedBox(width: 8),
                    Text('AFTER REPAIR (POST-FIX INSPECTION)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.successDark)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.success,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('CLEARED (0% DEFECT)', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          Container(
            height: 220,
            width: double.infinity,
            color: const Color(0xFF0F172A),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Center(
                    child: Icon(Icons.check_circle_outline_rounded, size: 48, color: Colors.white24),
                  ),
                ),
                // Smooth Asphalt Cleared Overlay
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.2),
                      border: Border.all(color: AppTheme.success, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_user_rounded, color: AppTheme.success, size: 24),
                        SizedBox(width: 8),
                        Text(
                          'AI VERIFIED — RESOLVED',
                          style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Contractor: Certified Patch Applied', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                Text('Defect Residual: ${(_postRepairConfidence * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.success)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationActionBar(BuildContext context, AppStorage storage, CaseItem activeCase) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.shield_rounded, color: AppTheme.success, size: 28),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Automated AI Resolution Certification', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.textPrimary)),
                SizedBox(height: 2),
                Text('The dual comparison engine confirms surface smoothing and 0% defect presence.', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _isVerifying
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    setState(() => _isVerifying = true);
                    await Future.delayed(const Duration(milliseconds: 700));
                    if (!mounted) return;
                    setState(() {
                      _isVerifying = false;
                      _verificationPassed = true;
                    });
                    messenger.showSnackBar(
                      const SnackBar(
                        backgroundColor: AppTheme.success,
                        content: Text('Case verified and officially marked as RESOLVED & CLOSED!'),
                      ),
                    );
                  },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
            icon: _isVerifying
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_rounded, size: 16),
            label: Text(_verificationPassed ? 'Re-Run AI Verification' : 'Certify & Close Case'),
          ),
        ],
      ),
    );
  }
}
