import 'dart:async';

import 'package:flutter/material.dart';

import '../../citizen/repository/complaint_repository.dart';
import '../../config/app_theme.dart';
import 'citizen/community_hub_tab.dart';
import 'citizen/my_reports_tab.dart';
import 'citizen/nearby_issues_tab.dart';
import 'citizen/quick_report_tab.dart';

/// CITIZEN REPORTER PORTAL — the four-section citizen app shell.
///
/// Navigation is intentionally unchanged: Quick Report, My Reports,
/// Nearby Issues and Community Hub. Each section now runs on ONE shared
/// complaint lifecycle (ComplaintRepository + engines + real-time services):
/// Quick Report creates or joins cases -> they instantly appear in My Reports,
/// Nearby Issues and Community Hub -> every authority-side status update
/// flows back through live notifications to all sections at once.
class CitizenPortal extends StatefulWidget {
  const CitizenPortal({super.key});

  @override
  State<CitizenPortal> createState() => _CitizenPortalState();
}

class _CitizenPortalState extends State<CitizenPortal> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Boots the offline-first complaint engine: loads local storage,
    // primes the sync queue, SLA monitor and real-time event stream.
    unawaited(ComplaintRepository.instance.initialize());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgCanvas,
      appBar: AppBar(
        backgroundColor: AppTheme.bgSurface,
        title: Row(
          children: [
            const Icon(Icons.record_voice_over_rounded, color: AppTheme.cyan, size: 20),
            const SizedBox(width: 10),
            const Text(
              'Citizen Reporter Portal',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.cyan.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'PUBLIC PORTAL',
                style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppTheme.cyan),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppTheme.textSecondary),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Switch Portal',
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (idx) => setState(() => _currentIndex = idx),
        backgroundColor: AppTheme.bgSurface,
        selectedItemColor: AppTheme.cyan,
        unselectedItemColor: AppTheme.textSecondary,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.add_a_photo_rounded),
            label: 'Quick Report',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.playlist_add_check_rounded),
            label: 'My Reports',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_rounded),
            label: 'Nearby Issues',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.groups_rounded),
            label: 'Community Hub',
          ),
        ],
      ),
      body: switch (_currentIndex) {
        0 => const QuickReportTab(),
        1 => const MyReportsTab(),
        2 => const NearbyIssuesTab(),
        _ => const CommunityHubTab(),
      },
    );
  }
}
