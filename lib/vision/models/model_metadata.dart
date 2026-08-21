enum ModelStatus {
  loading,
  ready,
  error,
  disabled,
}

/// Metadata configuration for a vision model in the multi-model ensemble.
class ModelMetadata {
  const ModelMetadata({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    this.weight = 1.0,
    this.enabled = true,
    this.inputWidth = 320,
    this.inputHeight = 320,
    this.supportedClasses = const [],
  });

  final String id;
  final String name;
  final String description;
  final String version;
  final double weight;
  final bool enabled;
  final int inputWidth;
  final int inputHeight;
  final List<String> supportedClasses;

  ModelMetadata copyWith({
    String? id,
    String? name,
    String? description,
    String? version,
    double? weight,
    bool? enabled,
    int? inputWidth,
    int? inputHeight,
    List<String>? supportedClasses,
  }) {
    return ModelMetadata(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      version: version ?? this.version,
      weight: weight ?? this.weight,
      enabled: enabled ?? this.enabled,
      inputWidth: inputWidth ?? this.inputWidth,
      inputHeight: inputHeight ?? this.inputHeight,
      supportedClasses: supportedClasses ?? this.supportedClasses,
    );
  }
}
