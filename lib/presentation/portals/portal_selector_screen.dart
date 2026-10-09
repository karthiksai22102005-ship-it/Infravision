import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import 'citizen_portal.dart';
import 'inspector_portal.dart';
import 'crew_portal.dart';
import 'supervisor_portal.dart';

class PortalSelectorScreen extends StatelessWidget {
  const PortalSelectorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 768;

    return Scaffold(
      backgroundColor: AppTheme.bgCanvas,
      body: Stack(
        children: [
          // Cyber ambient glow spots
          Positioned(
            top: -200,
            left: -200,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: 0.15),
              ),
            ),
          ),
          Positioned(
            bottom: -200,
            right: -200,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.cyan.withValues(alpha: 0.15),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo & Title
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppTheme.primary, AppTheme.cyan],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primary.withValues(alpha: 0.3),
                                  blurRadius: 16,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.construction_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'InfraVision',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.textPrimary,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              Text(
                                'Autonomous Physical Issue Intelligence Platform',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.cyan,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Select Your Operational Role Portal',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),

                      // Roles Grid
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: isMobile ? 1 : 2,
                        crossAxisSpacing: 24,
                        mainAxisSpacing: 24,
                        childAspectRatio: isMobile ? 1.45 : 1.25,
                        children: [
                          _RoleCard(
                            title: 'Observation Portal',
                            subtitle: 'Multi-Source Defect Intake & Observation Stream',
                            description: 'Submit or capture real-world observations via photos, videos, descriptions, and GPS directly into the central Observation → Issue Intelligence pipeline.',
                            icon: Icons.record_voice_over_rounded,
                            badge: 'OBSERVATION STREAM',
                            color: AppTheme.cyan,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const CitizenPortal(),
                                ),
                              );
                            },
                          ),
                          _RoleCard(
                            title: 'Field Intelligence Portal',
                            subtitle: 'On-Device Edge Vision & Sweep Engine',
                            description: 'Perform real-time computer vision sweeps with live AI overlays, execute batch video tracking, capture evidence, and manage offline sync queue.',
                            icon: Icons.center_focus_strong_rounded,
                            badge: 'LIVE YOLO SWEEP',
                            color: AppTheme.purple,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const InspectorPortal(),
                                ),
                              );
                            },
                          ),
                          _RoleCard(
                            title: 'Resolution Operations Portal',
                            subtitle: 'Work Execution & SLA Resolution Dispatch',
                            description: 'Access assigned work orders, view initial defect evidence, capture guided before/after resolution proof, and log materials for physical issue resolution.',
                            icon: Icons.engineering_rounded,
                            badge: 'RESOLUTION CREW',
                            color: AppTheme.warning,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const CrewPortal(),
                                ),
                              );
                            },
                          ),
                          _RoleCard(
                            title: 'Command & Verification Portal',
                            subtitle: 'Operations Command & Multi-Factor Verification',
                            description: 'Audit physical issue lifecycle, manage correlation queues, verify resolution attempts via split-pane comparison, and monitor systemic operational health.',
                            icon: Icons.dashboard_customize_rounded,
                            badge: 'COMMAND CENTER',
                            color: AppTheme.primary,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const SupervisorPortal(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 50),
                      // Footnote / Standards compliance label
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.bgSurface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shield_rounded, color: AppTheme.success, size: 14),
                            SizedBox(width: 8),
                            Text(
                              'ISO-55000 / ASTM Asset Lifecycle Intelligence Framework',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatefulWidget {
  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.badge,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final String badge;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _isHovered ? AppTheme.bgSurfaceSubtle : AppTheme.bgSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isHovered ? widget.color : AppTheme.border,
              width: 1.5,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.15),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ]
                : AppTheme.shadowSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: widget.color.withValues(alpha: 0.2)),
                    ),
                    child: Icon(
                      widget.icon,
                      color: widget.color,
                      size: 26,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: widget.color.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      widget.badge,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: widget.color,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.subtitle,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: widget.color,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.description,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
