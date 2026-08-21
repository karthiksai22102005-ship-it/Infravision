import 'package:flutter/material.dart';
import '../../config/app_theme.dart';

import 'cases_workspace.dart';
import 'complaints_workspace.dart';
import 'evidence_workspace.dart';

enum IssuesTab { complaints, cases, evidence }

/// Unified Hub for Grievances, Work Orders, and Evidence Vault.
class IssuesHubWorkspace extends StatefulWidget {
  const IssuesHubWorkspace({
    super.key,
    this.initialTab = IssuesTab.complaints,
  });

  final IssuesTab initialTab;

  @override
  State<IssuesHubWorkspace> createState() => _IssuesHubWorkspaceState();
}

class _IssuesHubWorkspaceState extends State<IssuesHubWorkspace> {
  late IssuesTab _currentTab;

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
                        label: 'Citizen Complaints',
                        icon: Icons.report_gmailerrorred_rounded,
                        isSelected: _currentTab == IssuesTab.complaints,
                        onTap: () => setState(() => _currentTab = IssuesTab.complaints),
                      ),
                      const SizedBox(width: 8),
                      _SegmentPill(
                        label: 'Work Orders & Cases',
                        icon: Icons.assignment_turned_in_rounded,
                        isSelected: _currentTab == IssuesTab.cases,
                        onTap: () => setState(() => _currentTab = IssuesTab.cases),
                      ),
                      const SizedBox(width: 8),
                      _SegmentPill(
                        label: 'Evidence Media Vault',
                        icon: Icons.perm_media_rounded,
                        isSelected: _currentTab == IssuesTab.evidence,
                        onTap: () => setState(() => _currentTab = IssuesTab.evidence),
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
            IssuesTab.complaints => const ComplaintsWorkspace(),
            IssuesTab.cases => const CasesWorkspace(),
            IssuesTab.evidence => const EvidenceWorkspace(),
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
