import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../config/app_theme.dart';
import '../../../citizen/models/complaint.dart';
import '../../../citizen/models/complaint_evidence.dart';
import '../../../citizen/repository/complaint_repository.dart';
import 'complaint_detail_view.dart';

/// TAB 3 — Nearby Issues: live issue discovery, confirmation, following and
/// duplicate prevention. Supports list + map views with filters.
class NearbyIssuesTab extends StatefulWidget {
  const NearbyIssuesTab({super.key});

  @override
  State<NearbyIssuesTab> createState() => _NearbyIssuesTabState();
}

class _NearbyIssuesTabState extends State<NearbyIssuesTab> {
  bool _mapView = false;

  String? _categoryFilter;
  String? _statusFilter;
  String? _priorityFilter;
  double _maxDistanceKm = 5.0;
  bool _recentOnly = false;
  bool _beingRepairedOnly = false;

  static const List<String> _categories = [
    'Pothole & Asphalt Degradation',
    'Concrete & Structural',
    'Drainage & Public Health',
    'Streetlight & Traffic Signal',
    'Manhole / Drainage',
  ];

  void _openDetail(Complaint c) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ComplaintDetailView(complaint: c)));
  }

  Future<void> _addEvidence(Complaint c) async {
    final picked = await FilePicker.pickFiles(type: FileType.media);
    if (picked.isEmpty || picked.first.path == null) return;
    ComplaintRepository.instance.addEvidence(c.id,
        path: picked.first.path!,
        kind: EvidenceKind.image,
        caption: 'Supporting evidence from nearby citizen');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Evidence added to this issue.'),
          behavior: SnackBarBehavior.floating));
    }
  }

  List<Complaint> _filter(List<Complaint> all) {
    var list = List<Complaint>.from(all);
    // Respect the current citizen's GPS as the anchor.
    list.sort((a, b) => a.distanceTo(_anchorLat, _anchorLon)
        .compareTo(b.distanceTo(_anchorLat, _anchorLon)));
    if (_categoryFilter != null) {
      list = list.where((c) => c.category == _categoryFilter).toList();
    }
    if (_statusFilter != null) {
      if (_statusFilter == 'Open') {
        list = list.where((c) => c.isOpen).toList();
      } else if (_statusFilter == 'Being repaired') {
        list = list.where((c) => c.status == ComplaintStatus.repairTeamAssigned || c.status == ComplaintStatus.workStarted).toList();
      } else if (_statusFilter == 'Resolved') {
        list = list.where((c) => c.status == ComplaintStatus.closed).toList();
      }
    }
    if (_priorityFilter != null) {
      list = list.where((c) => c.priority.label == _priorityFilter).toList();
    }
    list = list.where((c) => c.distanceTo(_anchorLat, _anchorLon) <= _maxDistanceKm * 1000).toList();
    if (_recentOnly) {
      list = list.where((c) => DateTime.now().difference(c.createdAt).inHours <= 24).toList();
    }
    if (_beingRepairedOnly) {
      list = list.where((c) => c.status == ComplaintStatus.repairTeamAssigned || c.status == ComplaintStatus.workStarted).toList();
    }
    return list;
  }

  final double _anchorLat = 17.3850;
  final double _anchorLon = 78.4867;
  @override
  Widget build(BuildContext context) {
    final repo = ComplaintRepository.instance;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final filtered = _filter(repo.publicIssues);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(children: [
                const Expanded(
                  child: Text('Nearby Issues & Verification',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                ),
                IconButton(
                  onPressed: () => setState(() => _mapView = !_mapView),
                  icon: Icon(_mapView ? Icons.view_list_rounded : Icons.map_rounded, color: AppTheme.cyan),
                  tooltip: _mapView ? 'List view' : 'Map view',
                ),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Confirm issues others reported instead of creating duplicates. '
                'Affected count & impact score drive priority.',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ),
            const SizedBox(height: 6),
            _filterBar(),
            const SizedBox(height: 6),
            Expanded(child: _mapView ? _mapViewWidget(filtered) : _listView(filtered)),
          ],
        );
      },
    );
  }

  Widget _filterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        _dropdown('Category', _categoryFilter, _categories, (v) => setState(() => _categoryFilter = v)),
        const SizedBox(width: 8),
        _dropdown('Status', _statusFilter, const ['Open', 'Being repaired', 'Resolved'], (v) => setState(() => _statusFilter = v)),
        const SizedBox(width: 8),
        _dropdown('Priority', _priorityFilter, const ['Low', 'Medium', 'High', 'Critical'], (v) => setState(() => _priorityFilter = v)),
        const SizedBox(width: 8),
        FilterChip(
          label: const Text('Recent 24h', style: TextStyle(fontSize: 11)),
          selected: _recentOnly,
          onSelected: (v) => setState(() => _recentOnly = v),
        ),
        const SizedBox(width: 8),
        FilterChip(
          label: const Text('Being repaired', style: TextStyle(fontSize: 11)),
          selected: _beingRepairedOnly,
          onSelected: (v) => setState(() => _beingRepairedOnly = v),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<double>(
          initialValue: _maxDistanceKm,
          onSelected: (v) => setState(() => _maxDistanceKm = v),
          itemBuilder: (_) => [
            for (final d in [0.5, 1.0, 2.0, 5.0, 10.0])
              PopupMenuItem(value: d, child: Text('Within $d km', style: const TextStyle(fontSize: 12))),
          ],
          child: Chip(
            avatar: const Icon(Icons.near_me_rounded, size: 14, color: AppTheme.cyan),
            label: Text('$_maxDistanceKm km', style: const TextStyle(fontSize: 11)),
          ),
        ),
      ]),
    );
  }

  Widget _dropdown(String label, String? value, List<String> options, void Function(String?) onChanged) {
    return PopupMenuButton<String>(
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [
        PopupMenuItem(value: null, child: Text('$label: All', style: const TextStyle(fontSize: 12))),
        for (final o in options) PopupMenuItem(value: o, child: Text('$label: $o', style: const TextStyle(fontSize: 12))),
      ],
      child: Chip(
        avatar: Icon(value == null ? Icons.filter_list_rounded : Icons.check_circle_rounded,
            size: 14, color: AppTheme.cyan),
        label: Text(value ?? label, style: const TextStyle(fontSize: 11)),
      ),
    );
  }
  Widget _listView(List<Complaint> items) {
    if (items.isEmpty) {
      return const Center(child: Text('No issues match these filters.', style: TextStyle(color: AppTheme.textMuted)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: items.length,
      itemBuilder: (context, i) => _card(items[i]),
    );
  }

  Widget _mapViewWidget(List<Complaint> items) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: AppTheme.bgSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: Size.infinite, painter: _GridMapPainter()),
          const Positioned(
            left: 150, top: 120,
            child: Icon(Icons.my_location_rounded, color: AppTheme.cyan, size: 22),
          ),
          for (final c in items)
            Positioned(
              left: 60.0 + (c.id.hashCode % 160),
              top: 60.0 + (c.id.hashCode % 220),
              child: Tooltip(
                message: '${c.category} • ${c.confirmationCount} confirmations',
                child: GestureDetector(
                  onTap: () => _openDetail(c),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _priorityColor(c).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: _priorityColor(c), width: 2),
                    ),
                    child: Icon(Icons.warning_rounded, color: _priorityColor(c), size: 14),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 10, top: 10,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)),
              child: const Text('Colored dots = issue priority', style: TextStyle(fontSize: 9, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
  Widget _card(Complaint c) {
    final repo = ComplaintRepository.instance;
    final isFollowed = repo.followedIds.contains(c.id);
    final dist = c.distanceTo(_anchorLat, _anchorLon);
    return Card(
      color: AppTheme.bgSurface,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => _openDetail(c),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.category, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                    const SizedBox(height: 2),
                    Text('${_distanceLabel(dist)} away • ${c.address}',
                        style: const TextStyle(fontSize: 10, color: AppTheme.cyan)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 20),
              ]),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _chip(c.status.label, AppTheme.cyan),
              _chip(c.priority.label, _priorityColor(c)),
              _chip('${c.confirmationCount} confirm', AppTheme.warning),
              _chip('${c.followerCount} follow', AppTheme.purple),
              _chip(_fmt(c.createdAt), AppTheme.textMuted),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.success, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                onPressed: () => repo.confirmIssue(c.id),
                icon: const Icon(Icons.verified_rounded, size: 14),
                label: const Text('Confirm same issue', style: TextStyle(fontSize: 10)),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.purple, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                onPressed: () => repo.followIssue(c.id, follow: !isFollowed),
                icon: Icon(isFollowed ? Icons.notifications_off_rounded : Icons.notifications_rounded, size: 14),
                label: Text(isFollowed ? 'Following' : 'Follow', style: const TextStyle(fontSize: 10)),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.cyan, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                onPressed: () => _addEvidence(c),
                icon: const Icon(Icons.add_photo_alternate_rounded, size: 14),
                label: const Text('Add evidence', style: TextStyle(fontSize: 10)),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  String _distanceLabel(double meters) =>
      meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)} km' : '${meters.round()} m';
  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.4))),
        child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      );

  Color _priorityColor(Complaint c) => switch (c.priority) {
        ComplaintPriorityLevel.critical => AppTheme.error,
        ComplaintPriorityLevel.high => AppTheme.warning,
        ComplaintPriorityLevel.medium => AppTheme.cyan,
        ComplaintPriorityLevel.low => AppTheme.success,
      };

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _GridMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppTheme.border.withValues(alpha: 0.3)
      ..strokeWidth = 1.0;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
