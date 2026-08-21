import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../navigation/workspace_navigation.dart';

/// Top-notch Pro Sidebar categorized with live badge counters & user profile.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.currentTab,
    required this.onTabSelected,
    this.isCollapsed = false,
  });

  final AppTab currentTab;
  final ValueChanged<AppTab> onTabSelected;
  final bool isCollapsed;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: isCollapsed ? 76 : 255,
      decoration: const BoxDecoration(
        color: Color(0xFF0B1120),
        border: Border(
          right: BorderSide(color: Color(0xFF1E293B)),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),

          // Glowing System Ready Status Strip
          if (!isCollapsed)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF131D31),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded, color: AppTheme.cyan, size: 15),
                  SizedBox(width: 8),
                  Text(
                    'SYSTEM READY',
                    style: TextStyle(
                      color: AppTheme.cyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // Scrollable Categorized Tabs List
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isCollapsed ? 8 : 12,
                vertical: 4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final category in WorkspaceCategory.values) ...[
                    if (!isCollapsed)
                      _SectionHeader(title: category.title)
                    else
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Divider(height: 1, color: Color(0xFF1E293B)),
                      ),
                    for (final tab in AppTab.values.where((t) => t.category == category))
                      _SidebarItem(
                        icon: currentTab == tab ? tab.selectedIcon : tab.icon,
                        label: tab.label,
                        badgeText: tab.badgeText,
                        isSelected: currentTab == tab,
                        isCollapsed: isCollapsed,
                        onTap: () => onTabSelected(tab),
                      ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),

          // Bottom Inspector Lead Profile Card
          _buildUserProfileFooter(context),
        ],
      ),
    );
  }

  Widget _buildUserProfileFooter(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(isCollapsed ? 10 : 14),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        mainAxisAlignment: isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.person_rounded, color: Colors.white, size: 20),
          ),
          if (!isCollapsed) ...[
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Inspector Alex',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Senior Lead Engineer',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Color(0xFF94A3B8), size: 18),
              onPressed: () {},
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Color(0xFF64748B),
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isCollapsed,
    required this.onTap,
    this.badgeText,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isCollapsed;
  final VoidCallback onTap;
  final String? badgeText;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2.5),
      child: Tooltip(
        message: isCollapsed ? label : '',
        waitDuration: const Duration(milliseconds: 300),
        child: Material(
          color: isSelected ? const Color(0xFF1E293B) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? AppTheme.primary.withValues(alpha: 0.7) : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisAlignment: isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: isSelected ? AppTheme.cyan : const Color(0xFF94A3B8),
                  ),
                  if (!isCollapsed) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                        ),
                      ),
                    ),
                    if (badgeText != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primary : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Text(
                          badgeText!,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
