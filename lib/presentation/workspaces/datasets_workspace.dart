import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../vision/training/dataset_manager.dart';

/// Interactive Dataset Management & Annotation Studio.
class DatasetsWorkspace extends StatefulWidget {
  const DatasetsWorkspace({super.key});

  @override
  State<DatasetsWorkspace> createState() => _DatasetsWorkspaceState();
}

class _DatasetsWorkspaceState extends State<DatasetsWorkspace> {
  final DatasetManager _dataset = DatasetManager.instance;
  String _selectedClassId = 'all';
  bool _isImporting = false;

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);

    return ListenableBuilder(
      listenable: _dataset,
      builder: (context, _) {
        final classes = _dataset.classes;
        final items = _selectedClassId == 'all'
            ? _dataset.items
            : _dataset.items.where((it) => it.classId == _selectedClassId).toList();

        return SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header & Action Controls
              _buildTopBar(context),
              const SizedBox(height: 20),

              // 2. Class Filter Chips & Class Summary Cards
              _buildClassSelector(classes),
              const SizedBox(height: 20),

              // 3. Two-Column Studio Layout (Dataset Gallery + Augmentation Config)
              if (!isMobile)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: _buildGallery(items, classes),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 5,
                      child: _buildAugmentationStudio(context),
                    ),
                  ],
                )
              else ...[
                _buildGallery(items, classes),
                const SizedBox(height: 20),
                _buildAugmentationStudio(context),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
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
              color: AppTheme.purpleLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.folder_special_rounded, color: AppTheme.purple, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dataset Management & Label Studio',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_dataset.totalSamples} total labeled samples across ${_dataset.classes.length} infrastructure defect categories.',
                  style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _showAddClassDialog,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Class'),
              ),
              FilledButton.icon(
                onPressed: _isImporting ? null : _importImagesFromDisk,
                icon: _isImporting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.file_upload_outlined, size: 16),
                label: const Text('Import Images'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClassSelector(List<dynamic> classes) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip(
            id: 'all',
            name: 'All Categories (${_dataset.totalSamples})',
            color: AppTheme.primary,
          ),
          const SizedBox(width: 8),
          ...classes.map((cls) {
            final count = _dataset.getCountForClass(cls.id);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildFilterChip(
                id: cls.id,
                name: '${cls.name} ($count)',
                color: cls.color,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String id,
    required String name,
    required Color color,
  }) {
    final isSelected = _selectedClassId == id;
    return InkWell(
      onTap: () => setState(() => _selectedClassId = id),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : AppTheme.border,
          ),
          boxShadow: isSelected ? AppTheme.shadowSm : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isSelected)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                ),
              ),
            Text(
              name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGallery(List<DatasetItem> items, List<dynamic> classes) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Labeled Samples (${items.length})',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                'Showing ${items.take(30).length} of ${items.length} items',
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              alignment: Alignment.center,
              child: const Column(
                children: [
                  Icon(Icons.image_not_supported_rounded, size: 48, color: AppTheme.textMuted),
                  SizedBox(height: 12),
                  Text('No images found in this class.', style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.1,
              ),
              itemCount: items.take(24).length,
              itemBuilder: (context, idx) {
                final item = items[idx];
                return _buildSampleCard(item);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSampleCard(DatasetItem item) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgSurfaceSubtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            Positioned.fill(
              child: item.localFile != null
                  ? Image.file(item.localFile!, fit: BoxFit.cover)
                  : Container(
                      color: const Color(0xFF1E293B),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _getIconForClass(item.classId),
                              color: Colors.white70,
                              size: 28,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.id,
                              style: const TextStyle(fontSize: 10, color: Colors.white54),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: Colors.black.withValues(alpha: 0.7),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item.className,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${item.width}x${item.height}',
                      style: const TextStyle(color: Colors.white70, fontSize: 9),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAugmentationStudio(BuildContext context) {
    final aug = _dataset.augmentation;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: AppTheme.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Data Augmentation Pipeline',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Synthetically expands dataset variance during training epochs.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          _buildAugToggle(
            'Random Rotation (±15°)',
            'Rotates surface defects for angle invariance',
            aug.randomRotation,
            (v) => _dataset.updateAugmentation(randomRotation: v),
          ),
          _buildAugToggle(
            'Horizontal & Vertical Flip',
            'Mirrors defect patterns across axes',
            aug.horizontalFlip,
            (v) => _dataset.updateAugmentation(horizontalFlip: v),
          ),
          _buildAugToggle(
            'Brightness Jitter (±20%)',
            'Simulates sunny, shadowed & night conditions',
            aug.brightnessJitter,
            (v) => _dataset.updateAugmentation(brightnessJitter: v),
          ),
          _buildAugToggle(
            'Contrast & Histogram Stretch',
            'Enhances subtle micro-cracks on low-contrast concrete',
            aug.contrastAdjustment,
            (v) => _dataset.updateAugmentation(contrastAdjustment: v),
          ),
          _buildAugToggle(
            'Random Crop & Zoom (0.85x - 1.15x)',
            'Multi-scale edge zoom for small defects',
            aug.randomCrop,
            (v) => _dataset.updateAugmentation(randomCrop: v),
          ),
          _buildAugToggle(
            'Gaussian Blur & Noise Injection',
            'Improves resilience to motion blur and sensor noise',
            aug.gaussianNoise,
            (v) => _dataset.updateAugmentation(gaussianNoise: v),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.accentBlueLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: AppTheme.accentBlue, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Effective dataset multiplier: 4.8x (~5,400 augmented training frames generated per epoch).',
                    style: TextStyle(fontSize: 12, color: AppTheme.accentBlue),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAugToggle(String title, String desc, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                Text(desc, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }

  IconData _getIconForClass(String id) {
    switch (id) {
      case 'glass_fracture':
        return Icons.broken_image_rounded;
      case 'concrete_crack':
        return Icons.linear_scale_rounded;
      case 'pothole_asphalt':
        return Icons.grain_rounded;
      case 'corrosion_rust':
        return Icons.texture_rounded;
      case 'debris_hazard':
        return Icons.warning_amber_rounded;
      default:
        return Icons.check_circle_outline_rounded;
    }
  }

  Future<void> _importImagesFromDisk() async {
    setState(() => _isImporting = true);
    try {
      final result = await FilePickerPlatform.instance.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );

      if (result.isNotEmpty) {
        final files = result
            .where((f) => f.path != null)
            .map((f) => File(f.path!))
            .toList();

        if (files.isNotEmpty) {
          _dataset.addImportedItems(files, _selectedClassId == 'all' ? 'concrete_crack' : _selectedClassId);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Successfully imported ${files.length} labeled images.'),
                backgroundColor: AppTheme.success,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } catch (_) {
      // Ignored
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  void _showAddClassDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    Color selectedColor = AppTheme.primary;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.bgSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Add Custom Defect Category', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Category Name',
                      hintText: 'e.g. Paint Peeling, Cable Sagging',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText: 'Defect morphology and inspection criteria',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Category Badge Color:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      AppTheme.primary,
                      AppTheme.accentBlue,
                      AppTheme.success,
                      AppTheme.warning,
                      AppTheme.error,
                      AppTheme.purple,
                      AppTheme.cyan,
                    ].map((c) {
                      final isPicked = selectedColor == c;
                      return GestureDetector(
                        onTap: () => setDialogState(() => selectedColor = c),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c,
                            border: Border.all(
                              color: isPicked ? AppTheme.textPrimary : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (nameCtrl.text.trim().isNotEmpty) {
                    _dataset.addCustomClass(
                      name: nameCtrl.text.trim(),
                      description: descCtrl.text.trim(),
                      color: selectedColor,
                    );
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('Add Category'),
              ),
            ],
          );
        },
      ),
    );
  }
}
