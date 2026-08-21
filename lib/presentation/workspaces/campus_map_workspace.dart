import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/complaint_item.dart';
import '../../repositories/app_storage.dart';

class CampusMapWorkspace extends StatefulWidget {
  const CampusMapWorkspace({super.key});

  @override
  State<CampusMapWorkspace> createState() => _CampusMapWorkspaceState();
}

class _CampusMapWorkspaceState extends State<CampusMapWorkspace> {
  ComplaintItem? _selectedComplaint;

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);

    return ListenableBuilder(
      listenable: AppStorage.instance,
      builder: (context, _) {
        final storage = AppStorage.instance;
        final complaints = storage.complaintsList;

        return SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 14 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header
              _buildHeader(context),
              const SizedBox(height: 18),

              // 2. Main Map Grid Surface
              Container(
                height: 480,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: AppTheme.shadowMd,
                ),
                child: Stack(
                  children: [
                    // Grid background
                    CustomPaint(
                      size: Size.infinite,
                      painter: _MapGridPainter(),
                    ),

                    // Map Sector Labels
                    Positioned(top: 24, left: 30, child: _buildSectorLabel('SECTOR A: Solar Array Block')),
                    Positioned(top: 24, right: 40, child: _buildSectorLabel('SECTOR B: Academic Quad')),
                    Positioned(bottom: 40, left: 30, child: _buildSectorLabel('SECTOR C: West Perimeter Highway')),
                    Positioned(bottom: 40, right: 40, child: _buildSectorLabel('SECTOR D: Overpass & Bridge Division')),

                    // Defect Pins mapped dynamically
                    ..._buildDefectPins(complaints),

                    // Selected Detail Card Overlay
                    if (_selectedComplaint != null)
                      Positioned(
                        bottom: 16,
                        left: 16,
                        right: 16,
                        child: _buildDetailCard(context, _selectedComplaint!),
                      ),
                  ],
                ),
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
          Icon(Icons.map_rounded, color: AppTheme.primary, size: 24),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Campus & Municipal Geospatial Defect Map',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
                SizedBox(height: 2),
                Text(
                  'GIS coordinate overlay mapping active structural fractures, potholes, and open work orders.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectorLabel(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  List<Widget> _buildDefectPins(List<ComplaintItem> complaints) {
    final positions = [
      const Offset(0.25, 0.35),
      const Offset(0.72, 0.45),
      const Offset(0.40, 0.70),
      const Offset(0.80, 0.25),
      const Offset(0.18, 0.75),
    ];

    final widgets = <Widget>[];

    for (int i = 0; i < complaints.length; i++) {
      final comp = complaints[i];
      final pos = positions[i % positions.length];

      Color pinColor;
      switch (comp.severity) {
        case ComplaintSeverity.critical:
          pinColor = AppTheme.error;
          break;
        case ComplaintSeverity.high:
          pinColor = AppTheme.warning;
          break;
        case ComplaintSeverity.moderate:
          pinColor = AppTheme.accentBlue;
          break;
        case ComplaintSeverity.low:
          pinColor = AppTheme.success;
          break;
      }

      widgets.add(
        LayoutBuilder(
          builder: (context, constraints) {
            final x = constraints.maxWidth * pos.dx;
            final y = constraints.maxHeight * pos.dy;

            return Positioned(
              left: x - 16,
              top: y - 16,
              child: GestureDetector(
                onTap: () => setState(() => _selectedComplaint = comp),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: pinColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: pinColor.withValues(alpha: 0.6),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.place_rounded, color: Colors.white, size: 18),
                ),
              ),
            );
          },
        ),
      );
    }

    return widgets;
  }

  Widget _buildDetailCard(BuildContext context, ComplaintItem item) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowLg,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.location_on_rounded, color: AppTheme.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${item.id} • ${item.category}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => setState(() => _selectedComplaint = null),
                    ),
                  ],
                ),
                Text(
                  item.title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  'Location: ${item.zone} • Status: ${item.status.displayName}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 1;

    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Road outlines
    final roadPaint = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke;

    final roadPath = Path()
      ..moveTo(0, size.height * 0.5)
      ..quadraticBezierTo(size.width * 0.4, size.height * 0.3, size.width, size.height * 0.6);
    canvas.drawPath(roadPath, roadPaint);

    final roadPath2 = Path()
      ..moveTo(size.width * 0.5, 0)
      ..lineTo(size.width * 0.5, size.height);
    canvas.drawPath(roadPath2, roadPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
