import 'package:flutter/material.dart';
import '../../camera/camera_service.dart';
import '../../config/app_theme.dart';
import '../../performance/telemetry_service.dart';
import '../../vision/vision_service.dart';
import '../navigation/workspace_navigation.dart';

/// Full-Width Global Top Bar (Spanning across sidebar and workspace).
class AppHeader extends StatefulWidget {
  const AppHeader({
    super.key,
    required this.currentTab,
    required this.cameraService,
    required this.visionService,
    this.onToggleCollapse,
    this.isCollapsed = false,
  });

  final AppTab currentTab;
  final CameraService cameraService;
  final VisionService visionService;
  final VoidCallback? onToggleCollapse;
  final bool isCollapsed;

  @override
  State<AppHeader> createState() => _AppHeaderState();
}

class _AppHeaderState extends State<AppHeader> {
  String _selectedCampusZone = 'West Campus Area';

  final List<String> _campusZones = [
    'West Campus Area',
    'Main Avenue & Gate',
    'Tech & Engineering Park',
    'Library & Central Circle',
    'Hostel & Residential Sector',
  ];

  @override
  Widget build(BuildContext context) {
    final telemetry = TelemetryService.instance;

    return Container(
      width: double.infinity,
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF0B1120),
        border: Border(
          bottom: BorderSide(color: Color(0xFF1E293B)),
        ),
      ),
      child: Row(
        children: [
          // Sidebar Toggle Button
          if (widget.onToggleCollapse != null)
            IconButton(
              icon: Icon(
                widget.isCollapsed ? Icons.menu_open_rounded : Icons.menu_rounded,
                color: Colors.white70,
                size: 19,
              ),
              tooltip: widget.isCollapsed ? 'Expand sidebar' : 'Collapse sidebar',
              onPressed: widget.onToggleCollapse,
            ),
          const SizedBox(width: 2),

          // Brand Logo & Title
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, Color(0xFF06B6D4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.hub_rounded, color: Colors.white, size: 17),
          ),
          const SizedBox(width: 8),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'InfraVision',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'AI Workstation',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF94A3B8),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),

          const SizedBox(width: 8),
          Container(width: 1, height: 20, color: const Color(0xFF1E293B)),
          const SizedBox(width: 8),

          // Campus Zone Dropdown Selector
          Container(
            constraints: const BoxConstraints(maxWidth: 130),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF131D31),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: DropdownButton<String>(
              value: _selectedCampusZone,
              underline: const SizedBox.shrink(),
              dropdownColor: const Color(0xFF131D31),
              isDense: true,
              isExpanded: true,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.cyan, size: 16),
              items: _campusZones
                  .map(
                    (zone) => DropdownMenuItem(
                      value: zone,
                      child: Text(zone, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedCampusZone = val);
              },
            ),
          ),

          const Spacer(),

          // Live Edge AI Engine Status Pill
          ListenableBuilder(
            listenable: telemetry,
            builder: (context, _) {
              final fps = telemetry.currentInferenceFps > 0 ? telemetry.currentInferenceFps : 28.4;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.success.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppTheme.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'AI: ${fps.toStringAsFixed(1)} FPS',
                      style: const TextStyle(
                        color: AppTheme.success,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(width: 10),

          // Notification Alert Bell
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.white70, size: 19),
            tooltip: 'System Alerts (3 Unresolved)',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {},
          ),

          const SizedBox(width: 10),

          // Switch Portal Button
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppTheme.textSecondary, size: 19),
            tooltip: 'Switch Operational Portal',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => Navigator.pop(context),
          ),

          const SizedBox(width: 10),

          // User Profile Avatar
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Center(
              child: Text(
                'AL',
                style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
