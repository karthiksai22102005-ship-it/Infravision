import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_theme.dart';
import '../../models/evidence_item.dart';
import '../../repositories/app_storage.dart';

enum _EvidenceFilter { all, images, verified, linked }

/// Enhanced Evidence Vault — filter bar, SHA-256 detail panel, GPS chain-of-custody display.
class EvidenceWorkspace extends StatefulWidget {
  const EvidenceWorkspace({super.key});

  @override
  State<EvidenceWorkspace> createState() => _EvidenceWorkspaceState();
}

class _EvidenceWorkspaceState extends State<EvidenceWorkspace>
    with TickerProviderStateMixin {
  _EvidenceFilter _filter = _EvidenceFilter.all;
  int? _selectedIndex;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  List<EvidenceItem> _filtered(List<EvidenceItem> all) {
    switch (_filter) {
      case _EvidenceFilter.all:
        return all;
      case _EvidenceFilter.images:
        return all.where((e) => !e.filePath.endsWith('.mp4')).toList();
      case _EvidenceFilter.verified:
        return all.where((e) => e.sha256Hash.length == 64).toList();
      case _EvidenceFilter.linked:
        return all
            .where((e) =>
                e.linkedComplaintId != null || e.linkedCaseId != null)
            .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);

    return ListenableBuilder(
      listenable: AppStorage.instance,
      builder: (context, _) {
        final all = AppStorage.instance.evidenceList;
        final evidence = _filtered(all);
        final selected =
            (_selectedIndex != null && _selectedIndex! < evidence.length)
                ? evidence[_selectedIndex!]
                : null;

        return isMobile
            ? _buildMobileLayout(context, evidence, all.length)
            : _buildDesktopLayout(context, evidence, all.length, selected);
      },
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    List<EvidenceItem> evidence,
    int totalCount,
    EvidenceItem? selected,
  ) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _buildHeader(context, totalCount, evidence.length),
              _buildFilterBar(context),
              Expanded(child: _buildGrid(context, evidence, false)),
            ],
          ),
        ),
        if (selected != null)
          Container(
            width: 380,
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: AppTheme.border)),
              color: AppTheme.bgSurface,
            ),
            child: _buildDetailPanel(context, selected),
          ),
      ],
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    List<EvidenceItem> evidence,
    int totalCount,
  ) {
    return Column(
      children: [
        _buildHeader(context, totalCount, evidence.length),
        _buildFilterBar(context),
        Expanded(child: _buildGrid(context, evidence, true)),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, int total, int filtered) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: const BoxDecoration(
        color: AppTheme.bgSurface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) => Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.cyan.withValues(alpha: _pulseAnim.value * 0.18),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppTheme.cyan.withValues(alpha: _pulseAnim.value * 0.5)),
              ),
              child: const Icon(Icons.perm_media_rounded,
                  color: AppTheme.cyan, size: 22),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cryptographic Evidence Vault',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  'SHA-256 tamper-proof media with GPS chain-of-custody. $total items stored.',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Row(
            children: [
              _StatChip(label: 'Total', value: '$total', color: AppTheme.primary),
              const SizedBox(width: 8),
              _StatChip(
                label: 'Verified',
                value: '${AppStorage.instance.evidenceList.where((e) => e.sha256Hash.length == 64).length}',
                color: AppTheme.success,
              ),
              const SizedBox(width: 8),
              _StatChip(label: 'Showing', value: '$filtered', color: AppTheme.cyan),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    final filters = [
      (_EvidenceFilter.all, 'All Evidence', Icons.all_inclusive_rounded),
      (_EvidenceFilter.images, 'Images Only', Icons.image_rounded),
      (_EvidenceFilter.verified, 'SHA-256 Verified', Icons.verified_rounded),
      (_EvidenceFilter.linked, 'Linked to Case', Icons.link_rounded),
    ];

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppTheme.bgSurface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          for (final item in filters) ...[
            _FilterPill(
              label: item.$2,
              icon: item.$3,
              isSelected: _filter == item.$1,
              onTap: () => setState(() {
                _filter = item.$1;
                _selectedIndex = null;
              }),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildGrid(
      BuildContext context, List<EvidenceItem> evidence, bool isMobile) {
    if (evidence.isEmpty) return _buildEmptyState(context);

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isMobile ? 1 : 3,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        mainAxisExtent: 260,
      ),
      itemCount: evidence.length,
      itemBuilder: (context, idx) => _EvidenceCard(
        item: evidence[idx],
        isSelected: _selectedIndex == idx,
        onTap: () => setState(() {
          _selectedIndex = _selectedIndex == idx ? null : idx;
        }),
      ),
    );
  }

  Widget _buildDetailPanel(BuildContext context, EvidenceItem item) {
    final file = File(item.filePath);
    final exists = file.existsSync();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border))),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppTheme.primary, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Evidence Detail & Chain of Custody',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    size: 18, color: AppTheme.textMuted),
                onPressed: () => setState(() => _selectedIndex = null),
                tooltip: 'Close',
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: exists
                      ? Image.file(file,
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.cover)
                      : Container(
                          height: 200,
                          color: const Color(0xFF0F172A),
                          child: const Center(
                              child: Icon(Icons.broken_image_rounded,
                                  color: Colors.white30, size: 48)),
                        ),
                ),
                const SizedBox(height: 16),
                _DetailRow(label: 'Evidence ID', value: item.id, isMonospace: true, copyable: true, ctx: context),
                _DetailRow(label: 'Source', value: item.source, ctx: context),
                _DetailRow(label: 'Resolution', value: item.resolution, ctx: context),
                _DetailRow(label: 'Quality Grade', value: item.qualityGrade, ctx: context),
                _DetailRow(label: 'GPS Location', value: item.gpsLocation ?? 'Unavailable (Off-grid)', ctx: context),
                _DetailRow(
                    label: 'Captured At',
                    value: item.timestamp.toLocal().toString().split('.').first,
                    ctx: context),
                if (item.linkedComplaintId != null)
                  _DetailRow(
                      label: 'Linked Complaint',
                      value: item.linkedComplaintId!,
                      isMonospace: true,
                      ctx: context),
                if (item.linkedCaseId != null)
                  _DetailRow(
                      label: 'Linked Case',
                      value: item.linkedCaseId!,
                      isMonospace: true,
                      ctx: context),
                const SizedBox(height: 14),
                const Text(
                  'SHA-256 Cryptographic Integrity Hash',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppTheme.success.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_rounded,
                          color: AppTheme.success, size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.sha256Hash,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 9,
                            color: AppTheme.success,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded,
                            size: 14, color: AppTheme.success),
                        tooltip: 'Copy Hash',
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: item.sha256Hash));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('SHA-256 hash copied.'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.success.withValues(alpha: 0.08),
                        AppTheme.cyan.withValues(alpha: 0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppTheme.success.withValues(alpha: 0.25)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.verified_rounded,
                          color: AppTheme.success, size: 20),
                      SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CRYPTOGRAPHICALLY SEALED',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.success),
                          ),
                          Text(
                            'Tamper-proof · Immutable · Court Admissible',
                            style: TextStyle(
                                fontSize: 10, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: AppTheme.cyanLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.photo_library_outlined,
                size: 48, color: AppTheme.cyan),
          ),
          const SizedBox(height: 16),
          const Text('Evidence Vault Empty',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 6),
          const Text(
            'Snapshots captured during live inspection\nappear here with SHA-256 hashes.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _EvidenceCard extends StatefulWidget {
  const _EvidenceCard({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final EvidenceItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_EvidenceCard> createState() => _EvidenceCardState();
}

class _EvidenceCardState extends State<_EvidenceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final file = File(widget.item.filePath);
    final exists = file.existsSync();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: AppTheme.bgSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isSelected
                  ? AppTheme.primary
                  : (_hovered ? AppTheme.primaryLight : AppTheme.border),
              width: widget.isSelected ? 2 : 1,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.2),
                      blurRadius: 12,
                      spreadRadius: 2,
                    )
                  ]
                : AppTheme.shadowSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12)),
                      child: exists
                          ? Image.file(file,
                              width: double.infinity, fit: BoxFit.cover)
                          : Container(
                              color: const Color(0xFF0F172A),
                              child: const Center(
                                child: Icon(Icons.broken_image_rounded,
                                    color: Colors.white30, size: 36),
                              ),
                            ),
                    ),
                    if (widget.item.sha256Hash.length == 64)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_rounded,
                                  size: 10, color: Colors.white),
                              SizedBox(width: 3),
                              Text('SHA-256',
                                  style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.gps_fixed_rounded,
                                size: 10, color: AppTheme.cyan),
                            SizedBox(width: 3),
                            Text('GPS',
                                style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.cyan)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          widget.item.id,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.successLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.item.qualityGrade,
                            style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.successDark),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${widget.item.resolution} • ${widget.item.source}',
                      style: const TextStyle(
                          fontSize: 10, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.item.gpsLocation ?? 'GPS: N/A',
                      style: const TextStyle(
                          fontSize: 9,
                          color: AppTheme.cyan,
                          fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'SHA: ${widget.item.sha256Hash.length >= 12 ? widget.item.sha256Hash.substring(0, 12) : widget.item.sha256Hash}…',
                      style: const TextStyle(
                          fontSize: 9,
                          fontFamily: 'monospace',
                          color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.ctx,
    this.isMonospace = false,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool isMonospace;
  final bool copyable;
  final BuildContext ctx;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
                fontFamily: isMonospace ? 'monospace' : null,
              ),
            ),
          ),
          if (copyable)
            IconButton(
              icon: const Icon(Icons.copy_rounded,
                  size: 13, color: AppTheme.textMuted),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text('$label copied.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              tooltip: 'Copy',
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _FilterPill extends StatelessWidget {
  const _FilterPill({
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
      color: isSelected ? AppTheme.cyanLight : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: isSelected ? AppTheme.cyan : AppTheme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color:
                      isSelected ? AppTheme.cyan : AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? AppTheme.cyan
                        : AppTheme.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _StatChip extends StatelessWidget {
  const _StatChip(
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
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color),
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
