import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infravision/vision/classifier/defect_classifier_engine.dart';
import 'package:infravision/vision/training/dataset_manager.dart';
import 'package:infravision/vision/training/training_pipeline_engine.dart';

void main() {
  group('Defect Classifier Engine Tests', () {
    test('Default classes are registered with valid metadata', () {
      const classes = DefectClassifierEngine.defaultClasses;
      expect(classes.length, greaterThanOrEqualTo(5));
      expect(classes.any((c) => c.id == 'glass_fracture'), isTrue);
      expect(classes.any((c) => c.id == 'concrete_crack'), isTrue);
      expect(classes.any((c) => c.id == 'normal_clean'), isTrue);
    });
  });

  group('Dataset Manager Tests', () {
    test('Initializes with default sample dataset items', () {
      final dataset = DatasetManager.instance;
      expect(dataset.totalSamples, greaterThan(500));
      expect(dataset.getCountForClass('glass_fracture'), greaterThan(50));
    });

    test('Allows dynamic creation of custom defect classes', () {
      final dataset = DatasetManager.instance;
      const customName = 'Solar Micro Crack';
      dataset.addCustomClass(
        name: customName,
        description: 'Micro cracks in PV cells',
        color: const Color(0xFFE11D48),
        severityWeight: 0.88,
      );

      expect(dataset.classes.any((c) => c.name == customName), isTrue);
    });

    test('Augmentation settings can be toggled', () {
      final dataset = DatasetManager.instance;
      dataset.updateAugmentation(randomRotation: false, horizontalFlip: true);
      expect(dataset.augmentation.randomRotation, isFalse);
      expect(dataset.augmentation.horizontalFlip, isTrue);
    });
  });

  group('Training Pipeline Engine Tests', () {
    test('Configures model architecture and hyperparameters', () {
      final trainer = TrainingPipelineEngine.instance;
      trainer.setArchitecture(ModelArchitecture.efficientNetB0);
      trainer.setEpochs(10);
      trainer.setBatchSize(32);
      trainer.setLearningRate(0.001);

      expect(trainer.architecture, ModelArchitecture.efficientNetB0);
      expect(trainer.epochs, 10);
      expect(trainer.batchSize, 32);
      expect(trainer.learningRate, 0.001);
    });

    test('Runs real-time training session and produces epoch metrics', () async {
      final trainer = TrainingPipelineEngine.instance;
      trainer.setEpochs(3);

      expect(trainer.isTraining, isFalse);
      await trainer.startTraining();

      expect(trainer.isCompleted, isTrue);
      expect(trainer.epochHistory.length, 3);
      expect(trainer.finalAccuracy, greaterThan(0.5));
      expect(trainer.logs.isNotEmpty, isTrue);
      expect(trainer.exportedModelPath, isNotNull);
    });
  });
}
