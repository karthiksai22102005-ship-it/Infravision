import 'dart:io';
import 'package:flutter/material.dart';
import '../classifier/defect_classifier_engine.dart';

/// Represents a labeled dataset item.
class DatasetItem {
  DatasetItem({
    required this.id,
    required this.className,
    required this.classId,
    required this.source,
    this.localFile,
    this.width = 640,
    this.height = 480,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String className;
  final String classId;
  final String source; // 'builtin', 'imported', 'webcam_capture'
  final File? localFile;
  final int width;
  final int height;
  final DateTime createdAt;
}

/// Data Augmentation Settings for Training.
class AugmentationConfig {
  AugmentationConfig({
    this.randomRotation = true,
    this.horizontalFlip = true,
    this.brightnessJitter = true,
    this.contrastAdjustment = true,
    this.randomCrop = false,
    this.gaussianNoise = false,
  });

  bool randomRotation;
  bool horizontalFlip;
  bool brightnessJitter;
  bool contrastAdjustment;
  bool randomCrop;
  bool gaussianNoise;
}

/// Central Dataset Management and Label Studio Service.
class DatasetManager extends ChangeNotifier {
  DatasetManager._() {
    _initializeDefaultDataset();
  }
  static final DatasetManager instance = DatasetManager._();

  final List<DefectClass> _classes = List.from(DefectClassifierEngine.defaultClasses);
  final List<DatasetItem> _items = [];
  final AugmentationConfig _augmentation = AugmentationConfig();

  List<DefectClass> get classes => List.unmodifiable(_classes);
  List<DatasetItem> get items => List.unmodifiable(_items);
  AugmentationConfig get augmentation => _augmentation;

  int get totalSamples => _items.length;

  int getCountForClass(String classId) =>
      _items.where((it) => it.classId == classId).length;

  void _initializeDefaultDataset() {
    // Add realistic seed samples for each standard class
    const seedCounts = {
      'glass_fracture': 142,
      'concrete_crack': 210,
      'pothole_asphalt': 185,
      'corrosion_rust': 160,
      'debris_hazard': 98,
      'normal_clean': 320,
    };

    for (final c in _classes) {
      final count = seedCounts[c.id] ?? 80;
      for (int i = 1; i <= count; i++) {
        _items.add(
          DatasetItem(
            id: '${c.id}_$i',
            className: c.name,
            classId: c.id,
            source: 'builtin',
          ),
        );
      }
    }
  }

  void addCustomClass({
    required String name,
    required String description,
    required Color color,
    double severityWeight = 0.5,
  }) {
    final id = name.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    if (_classes.any((c) => c.id == id)) return;

    final newClass = DefectClass(
      id: id,
      name: name,
      description: description,
      color: color,
      severityWeight: severityWeight,
    );

    _classes.add(newClass);
    notifyListeners();
  }

  void addImportedItems(List<File> files, String classId) {
    final matchedClass = _classes.firstWhere(
      (c) => c.id == classId,
      orElse: () => _classes.first,
    );

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      _items.add(
        DatasetItem(
          id: 'imported_${DateTime.now().millisecondsSinceEpoch}_$i',
          className: matchedClass.name,
          classId: matchedClass.id,
          source: 'imported',
          localFile: file,
        ),
      );
    }
    notifyListeners();
  }

  void removeClass(String classId) {
    _classes.removeWhere((c) => c.id == classId);
    _items.removeWhere((it) => it.classId == classId);
    notifyListeners();
  }

  void clearImported() {
    _items.removeWhere((it) => it.source == 'imported');
    notifyListeners();
  }

  void updateAugmentation({
    bool? randomRotation,
    bool? horizontalFlip,
    bool? brightnessJitter,
    bool? contrastAdjustment,
    bool? randomCrop,
    bool? gaussianNoise,
  }) {
    if (randomRotation != null) _augmentation.randomRotation = randomRotation;
    if (horizontalFlip != null) _augmentation.horizontalFlip = horizontalFlip;
    if (brightnessJitter != null) _augmentation.brightnessJitter = brightnessJitter;
    if (contrastAdjustment != null) _augmentation.contrastAdjustment = contrastAdjustment;
    if (randomCrop != null) _augmentation.randomCrop = randomCrop;
    if (gaussianNoise != null) _augmentation.gaussianNoise = gaussianNoise;
    notifyListeners();
  }
}
