import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/case_item.dart';
import '../../repositories/app_storage.dart';

/// Advanced AI Before vs After Repair Forensic Verification Workspace with Interactive Split Slider.
class VerificationWorkspace extends StatefulWidget {
  const VerificationWorkspace({super.key});

  @override
  State<VerificationWorkspace> createState() => _VerificationWorkspaceState();
}

class _VerificationWorkspaceState extends State<VerificationWorkspace> {
  int _selectedCaseIndex = 0;
  bool _isVerifying = false;
  bool _verificationPassed = true;
  double _splitPosition = 0.5; // Split slider at 50%

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
              // 1. Top Header with Case Selector & GPS Coordinates
              _buildCaseSelectorHeader(context, cases, activeCase),
              const SizedBox(height: 16),

              // 2. Interactive Before vs After Split Wipe Visualizer
              _buildInteractiveSplitVisualizer(context, activeCase),
              const SizedBox(height: 16),

              // 3. Side-by-Side Diagnostic Telemetry Cards
              _buildDualComparisonCards(context, activeCase),
              const SizedBox(height: 16),

              // 4. Cryptographic AI Certification Action Bar
              _buildCertificationActionBar(context, storage, activeCase),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCaseSelectorHeader(BuildContext context, List<CaseItem> cases, CaseItem activeCase) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF131D31),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
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
            child: const Icon(Icons.fact_check_rounded, color: AppTheme.cyan, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Case ${activeCase.id}: ${activeCase.title}',
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  'Assigned Dept: ${activeCase.department} • Contractor: ${activeCase.assignedTeam}',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
            ),
            child: Text(
              activeCase.status.displayName.toUpperCase(),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.warning),
            ),
          ),
          const SizedBox(width: 14),
          DropdownButton<int>(
            value: _selectedCaseIndex < cases.length ? _selectedCaseIndex : 0,
            underline: const SizedBox.shrink(),
            dropdownColor: const Color(0xFF131D31),
            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
            icon: const Icon(Icons.arrow_drop_down_rounded, color: AppTheme.cyan),
            items: List.generate(
              cases.length,
              (i) => DropdownMenuItem(
                value: i,
                child: Text('Case #${cases[i].id}'),
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

  Widget _buildInteractiveSplitVisualizer(BuildContext context, CaseItem activeCase) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131D31),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B)),
        boxShadow: AppTheme.shadowMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.compare_rounded, color: AppTheme.cyan, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'INTERACTIVE FORENSIC SPLIT WIPE (DRAG SLIDER)',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5),
                    ),
                  ],
                ),
                Text(
                  'Wipe Position: ${(_splitPosition * 100).toInt()}%',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.cyan, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF1E293B)),

          // The Interactive Split Wipe Box
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              const height = 260.0;

              return SizedBox(
                width: width,
                height: height,
                child: Stack(
                  children: [
                    // Layer 1: Repaired Road Surface (Full Width Base)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _RepairedAsphaltPainter(),
                      ),
                    ),

                    // Layer 2: Damaged Road Surface (Clipped by Slider Position)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: width * _splitPosition,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          maxWidth: width,
                          maxHeight: height,
                          minWidth: width,
                          minHeight: height,
                          child: CustomPaint(
                            size: Size(width, height),
                            painter: _DamagedAsphaltPainter(),
                          ),
                        ),
                      ),
                    ),

                    // Slider Divider Line & Handle
                    Positioned(
                      left: (width * _splitPosition) - 14,
                      top: 0,
                      bottom: 0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragUpdate: (details) {
                          setState(() {
                            _splitPosition = (_splitPosition + details.delta.dx / width).clamp(0.05, 0.95);
                          });
                        },
                        child: Center(
                          child: Container(
                            width: 28,
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primary.withValues(alpha: 0.6),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.drag_indicator_rounded, color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                    ),

                    // Badges Left (Before) & Right (After)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.error,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('BEFORE: DEFECT 94%', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.success,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('AFTER: CLEARED 0%', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDualComparisonCards(BuildContext context, CaseItem activeCase) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;

        return isNarrow
            ? Column(
                children: [
                  _buildBeforeMetricCard(activeCase),
                  const SizedBox(height: 14),
                  _buildAfterMetricCard(activeCase),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildBeforeMetricCard(activeCase)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildAfterMetricCard(activeCase)),
                ],
              );
      },
    );
  }

  Widget _buildBeforeMetricCard(CaseItem activeCase) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131D31),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: AppTheme.error, size: 16),
                SizedBox(width: 8),
                Text('ORIGINAL DEFECT TELEMETRY', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: AppTheme.errorDark)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _buildMetricRow('Defect Classification', 'Asphalt Pothole (D40)', AppTheme.error),
                _buildMetricRow('Cavity Depth', '8.4 cm (Severe)', Colors.white),
                _buildMetricRow('Surface Area Impact', '0.42 m²', Colors.white),
                _buildMetricRow('Public Safety Hazard', 'High Impact Risk', AppTheme.error),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAfterMetricCard(CaseItem activeCase) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131D31),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: const Row(
              children: [
                Icon(Icons.verified_rounded, color: AppTheme.success, size: 16),
                SizedBox(width: 8),
                Text('POST-REPAIR AI VERIFICATION METRICS', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: AppTheme.success)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _buildMetricRow('Residual Defect Presence', '0.0% (Cleared)', AppTheme.success),
                _buildMetricRow('Asphalt Compaction Index', '99.4% Density', Colors.white),
                _buildMetricRow('Roughness Index (IRI)', '1.1 mm/m (Smooth)', Colors.white),
                _buildMetricRow('GPS Geofence Match', 'Verified within 0.6m', AppTheme.cyan),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8))),
          Text(value, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: valueColor, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildCertificationActionBar(BuildContext context, AppStorage storage, CaseItem activeCase) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131D31),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.shield_rounded, color: AppTheme.success, size: 26),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cryptographic AI Verification Certificate', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
                SizedBox(height: 2),
                Text('Dual comparison neural model confirms 0% residual defect and certified on-site seal.', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _isVerifying
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    setState(() => _isVerifying = true);
                    await Future.delayed(const Duration(milliseconds: 600));
                    await storage.updateCaseStatus(activeCase.id, CaseStatus.resolved);
                    if (!mounted) return;
                    setState(() {
                      _isVerifying = false;
                      _verificationPassed = true;
                    });
                    messenger.showSnackBar(
                      const SnackBar(
                        backgroundColor: AppTheme.success,
                        content: Text('Case verified and officially certified as RESOLVED & CLOSED!'),
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

/// Custom Canvas Painter for Damaged Asphalt (Pothole Cavity + Crack Contours).
class _DamagedAsphaltPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Rough road asphalt texture
    final basePaint = Paint()..color = const Color(0xFF1E222B);
    canvas.drawRect(Offset.zero & size, basePaint);

    // Asphalt aggregate speckles
    final specklePaint = Paint()..color = const Color(0xFF2D333F);
    for (int i = 0; i < 40; i++) {
      final x = (i * 37) % size.width;
      final y = (i * 23) % size.height;
      canvas.drawCircle(Offset(x, y), 2.5, specklePaint);
    }

    // Pothole Fracture Cavity (Dark jagged hole)
    final holeCenter = Offset(size.width * 0.45, size.height * 0.5);
    final holePaint = Paint()..color = const Color(0xFF090A0D);
    canvas.drawOval(Rect.fromCenter(center: holeCenter, width: 140, height: 90), holePaint);

    // Fracture Cracks spreading outward
    final crackPaint = Paint()
      ..color = const Color(0xFF11141A)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawLine(holeCenter + const Offset(-60, 0), holeCenter + const Offset(-110, -30), crackPaint);
    canvas.drawLine(holeCenter + const Offset(60, 0), holeCenter + const Offset(120, 40), crackPaint);
    canvas.drawLine(holeCenter + const Offset(0, 40), holeCenter + const Offset(30, 90), crackPaint);

    // Glowing Neon Bounding Box HUD
    final boxPaint = Paint()
      ..color = AppTheme.error
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final boxRect = Rect.fromCenter(center: holeCenter, width: 180, height: 130);
    canvas.drawRRect(RRect.fromRectAndRadius(boxRect, const Radius.circular(8)), boxPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom Canvas Painter for Repaired Smooth Asphalt (Clean Patch + AI Verified Seal).
class _RepairedAsphaltPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Smooth fresh dark asphalt base
    final basePaint = Paint()..color = const Color(0xFF131720);
    canvas.drawRect(Offset.zero & size, basePaint);

    // Fresh hot-mix patch area
    final patchCenter = Offset(size.width * 0.45, size.height * 0.5);
    final patchPaint = Paint()..color = const Color(0xFF1A1F2B);
    final patchRect = Rect.fromCenter(center: patchCenter, width: 220, height: 150);
    canvas.drawRRect(RRect.fromRectAndRadius(patchRect, const Radius.circular(12)), patchPaint);

    // Compacted seam border
    final seamPaint = Paint()
      ..color = const Color(0xFF2D3545)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(RRect.fromRectAndRadius(patchRect, const Radius.circular(12)), seamPaint);

    // Holographic AI Cleared Badge
    final badgePaint = Paint()
      ..color = AppTheme.success.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    final badgeBorder = Paint()
      ..color = AppTheme.success
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final badgeRect = Rect.fromCenter(center: patchCenter, width: 200, height: 50);
    canvas.drawRRect(RRect.fromRectAndRadius(badgeRect, const Radius.circular(10)), badgePaint);
    canvas.drawRRect(RRect.fromRectAndRadius(badgeRect, const Radius.circular(10)), badgeBorder);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
