/// VISUAL SIMILARITY ABSTRACTION for the IssueMatchingEngine.
///
/// The engine NEVER fakes visual AI: when no provider is installed, visual
/// scoring is simply absent from the match result. Plug the existing on-device
/// defect-classifier embeddings (or any future model) in here later:
///
///   IssueIntelligenceEngine.instance.visualProvider =
///       DefectEmbeddingSimilarityProvider(...);
library;

import '../models/observation.dart';

abstract class VisualSimilarityProvider {
  /// Returns 0..1 similarity, or null when the provider cannot compare the
  /// pair (missing embeddings, unsupported media…).
  double? similarity(Observation a, Observation b);
}

/// Honest default: no visual correlation available.
class NoVisualSimilarityProvider implements VisualSimilarityProvider {
  const NoVisualSimilarityProvider();

  @override
  double? similarity(Observation a, Observation b) => null;
}

/// Simple deterministic feature-vector provider: usable when an upstream AI
/// module has populated [Observation.visualFeatures]. Cosine-like overlap of
/// keyed features; returns null when either side lacks features.
class FeatureVectorSimilarityProvider implements VisualSimilarityProvider {
  const FeatureVectorSimilarityProvider();

  @override
  double? similarity(Observation a, Observation b) {
    if (a.visualFeatures.isEmpty || b.visualFeatures.isEmpty) return null;
    var dot = 0.0, na = 0.0, nb = 0.0;
    a.visualFeatures.forEach((k, va) {
      na += va * va;
      final vb = b.visualFeatures[k];
      if (vb != null) dot += va * vb;
    });
    b.visualFeatures.forEach((_, vb) => nb += vb * vb);
    if (na == 0 || nb == 0) return null;
    final cos = dot / (_sqrt(na) * _sqrt(nb));
    return cos.clamp(0.0, 1.0);
  }

  static double _sqrt(double x) {
    var r = x;
    for (var i = 0; i < 24; i++) {
      r = 0.5 * (r + x / r);
    }
    return r;
  }
}
