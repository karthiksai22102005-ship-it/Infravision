import 'dart:io';
import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/evidence_item.dart';
import '../../repositories/app_storage.dart';

class EvidenceWorkspace extends StatelessWidget {
  const EvidenceWorkspace({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);

    return ListenableBuilder(
      listenable: AppStorage.instance,
      builder: (context, _) {
        final evidence = AppStorage.instance.evidenceList;

        return SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 14 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header
              _buildHeader(context, evidence.length),
              const SizedBox(height: 18),

              // 2. Evidence Grid
              if (evidence.isEmpty)
                _buildEmptyState(context)
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: isMobile ? 1 : 3,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    mainAxisExtent: 260,
                  ),
                  itemCount: evidence.length,
                  itemBuilder: (context, idx) => _buildEvidenceCard(context, evidence[idx]),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.cyanLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.perm_media_rounded, color: AppTheme.cyan, size: 24),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Local Evidence Vault & Media Gallery',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
                SizedBox(height: 2),
                Text(
                  'Tamper-evident raw visual evidence repository stored at AppData/evidence/ with SHA-256 integrity hashes.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count Captured Items',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEvidenceCard(BuildContext context, EvidenceItem item) {
    final file = File(item.filePath);
    final exists = file.existsSync();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image surface
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: exists
                  ? Image.file(file, width: double.infinity, fit: BoxFit.cover)
                  : Container(
                      color: const Color(0xFF0F172A),
                      child: const Center(
                        child: Icon(Icons.broken_image_rounded, color: Colors.white30, size: 36),
                      ),
                    ),
            ),
          ),

          // Metadata footer
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.id,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.successLight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.qualityGrade,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.successDark),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.resolution} • ${item.source}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  'SHA: ${item.sha256Hash.substring(0, 12)}…',
                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library_outlined, size: 48, color: AppTheme.textMuted),
          SizedBox(height: 14),
          Text('Evidence Vault Empty', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
          SizedBox(height: 4),
          Text('Snapshots captured during live inspection or image analysis are permanently stored here.', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}
