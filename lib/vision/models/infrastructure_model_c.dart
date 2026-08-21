import 'package:infravision_camera/infravision_camera.dart';

import 'model_metadata.dart';
import 'vision_model.dart';

/// Model C: Specialized Infrastructure Defect Model Hook (Level-2 Architecture Hook).
///
/// Designed to load fine-tuned RDD2022/infrastructure defect models in Level 3.
/// Configured by default as an architectural slot with independent state management.
class InfrastructureModelC implements VisionModel {
  InfrastructureModelC({ModelMetadata? metadata})
      : _metadata = metadata ??
            const ModelMetadata(
              id: 'model_c_infra',
              name: 'Model C (Infra Defect Hook)',
              description: 'Specialized road defect & crack classifier (Level-3 Slot)',
              version: 'v1.0-hook',
              weight: 1.0,
              enabled: false, // Disabled by default until custom model weights are attached
              supportedClasses: [
                'pothole',
                'longitudinal_crack',
                'transverse_crack',
                'alligator_crack',
              ],
            );

  ModelMetadata _metadata;
  ModelStatus _status = ModelStatus.disabled;
  String? _errorMessage;

  @override
  ModelMetadata get metadata => _metadata;

  @override
  ModelStatus get status => _status;

  @override
  String? get errorMessage => _errorMessage;

  @override
  bool get isReady => _status == ModelStatus.ready;

  void updateMetadata(ModelMetadata newMetadata) {
    _metadata = newMetadata;
    _status = newMetadata.enabled ? ModelStatus.ready : ModelStatus.disabled;
  }

  @override
  Future<void> load() async {
    if (!_metadata.enabled) {
      _status = ModelStatus.disabled;
      return;
    }
    _status = ModelStatus.ready;
    _errorMessage = null;
  }

  @override
  List<RawModelDetection> infer(CameraFrame frame, {double minConfidence = 0.45}) {
    if (_status != ModelStatus.ready || !_metadata.enabled) {
      return const [];
    }
    // Level 3 custom weights hook
    return const [];
  }

  @override
  void dispose() {}
}
