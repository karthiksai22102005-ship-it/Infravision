/// ISSUE MATCHING ENGINE — decides whether a new Observation belongs to an
/// existing PhysicalIssue or starts a new one. Pure, config-driven, and
/// domain-independent: no GPS-only shortcuts, no hard-coded domain logic.
library;

import 'dart:math' as math;

import 'candidate_search_service.dart';
import '../domain/domain_config.dart';
import '../models/match_result.dart';
import '../models/observation.dart';
import '../models/physical_issue.dart';
import 'visual_similarity_provider.dart';

class IssueMatchingEngine {
  IssueMatchingEngine({
    MatchThresholds? thresholds,
    VisualSimilarityProvider? visualProvider,
    CandidateSearchService? candidateSearchService,
  })  : thresholds = thresholds ?? const MatchThresholds(),
        visualProvider = visualProvider ?? const NoVisualSimilarityProvider(),
        candidateSearchService =
            candidateSearchService ?? const CandidateSearchService();

  MatchThresholds thresholds;
  VisualSimilarityProvider visualProvider;
  CandidateSearchService candidateSearchService;

  /// Evaluates [obs] against issues (using [candidateSearchService] pre-filtering).
  MatchResult evaluate(Observation obs, List<PhysicalIssue> issues) {
    final candidates = candidateSearchService.findCandidates(
      obs,
      issues,
      searchRadiusMeters: thresholds.spatialRadiusMeters * 3.0,
      includeClosed: true,
    );

    MatchResult? best;
    var bestScore = -1.0;

    for (final issue in candidates) {
      final r = _scoreAgainst(obs, issue);
      if (r.overallConfidence > bestScore) {
        bestScore = r.overallConfidence;
        best = r;
      }
    }

    if (best == null) {
      return const MatchResult(
        resultType: MatchResultType.newIssue,
        spatialScore: 0,
        temporalScore: 0,
        classificationScore: 0,
        overallConfidence: 0,
        reasons: ['No open candidate issues to correlate against.'],
      );
    }

    final type = bestScore >= thresholds.autoMatchAbove
        ? MatchResultType.matched
        : bestScore >= thresholds.uncertainAbove
            ? MatchResultType.uncertain
            : MatchResultType.newIssue;

    return MatchResult(
      resultType: type,
      physicalIssueId:
          type == MatchResultType.newIssue ? null : best.physicalIssueId,
      spatialScore: best.spatialScore,
      temporalScore: best.temporalScore,
      classificationScore: best.classificationScore,
      visualScore: best.visualScore,
      contextScore: best.contextScore,
      overallConfidence: bestScore,
      reasons: best.reasons,
    );
  }

    MatchResult _scoreAgainst(Observation obs, PhysicalIssue issue) {
    final reasons = <String>[];

    // ── Factors 1+2: spatial proximity adjusted by location accuracies ──
    final distMeters = _haversine(
        obs.latitude, obs.longitude, issue.primaryLat, issue.primaryLng);
    final accuracySlack =
        (obs.locationAccuracy ?? 10) + (issue.identityConfidence * 20);
    final effectiveRadius = thresholds.spatialRadiusMeters + accuracySlack;
    final spatial = (1.0 - distMeters / effectiveRadius).clamp(0.0, 1.0);
    if (spatial > 0.6) {
      reasons.add(
          '${distMeters.round()} m away (within ${effectiveRadius.round()} m radius)');
    }

    // ── Factor 3: temporal distance with window decay ──
    final ageHours =
        obs.timestamp.difference(issue.updatedAt).inMinutes.abs() / 60.0;
    final temporal = (1.0 -
            ageHours / (thresholds.temporalWindowDays * 24.0))
        .clamp(0.0, 1.0);

    // ── Factors 4+5: issue type / AI classification compatibility ──
    final obsType = obs.detectedIssueType ?? obs.classification ?? '';
    final classification = _typeCompatibility(obsType, issue.issueType);

    // ── Factor 6: visual similarity (only when a provider is installed) ──
    double? visual;
    if (visualProvider is! NoVisualSimilarityProvider &&
        obs.visualFeatures.isNotEmpty) {
      // Future: anchor features cached from the issue's own observations
      // would be passed here; today the provider sees the incoming obs.
      visual = visualProvider.similarity(obs, obs);
    }

    // ── Factors 8+9: context overlap (address / description hints) ──
    final context = _contextScore(obs, issue);

    // ── Factor 10: weighted fusion (renormalised when visual is absent) ──
    var overall = spatial * thresholds.wSpatial +
        temporal * thresholds.wTemporal +
        classification * thresholds.wClassification +
        context * thresholds.wContext;
    if (visual != null) {
      overall += visual * thresholds.wVisual;
    } else {
      overall /= (1.0 - thresholds.wVisual);
    }
    overall = overall.clamp(0.0, 1.0);

    if (classification >= 0.99) reasons.add('same issue type');
    if (context >= 0.9) reasons.add('matching location context');

    return MatchResult(
      resultType: MatchResultType.uncertain, // caller re-classifies by score
      physicalIssueId: issue.physicalIssueId,
      spatialScore: spatial,
      temporalScore: temporal,
      classificationScore: classification,
      visualScore: visual,
      contextScore: context,
      overallConfidence: overall,
      reasons: reasons,
    );
  }

  double _typeCompatibility(String obsType, String issueType) {
    if (obsType.isEmpty || issueType.isEmpty) return 0.5;
    if (obsType.toLowerCase().trim() == issueType.toLowerCase().trim()) {
      return 1.0;
    }
    // Domain configs may alias several detection labels to one issue type.
    if (DomainRegistry.instance.aliasesMatch(obsType, issueType)) return 0.95;
    return 0.0;
  }

  double _contextScore(Observation obs, PhysicalIssue issue) {
    final ctx = obs.contextData['address'] ?? obs.userDescription;
    if (ctx is String &&
        ctx.isNotEmpty &&
        issue.address.isNotEmpty &&
        (ctx.toLowerCase().contains(issue.address.toLowerCase()) ||
            issue.address.toLowerCase().contains(ctx.toLowerCase()))) {
      return 1.0;
    }
    return 0.3;
  }

  static double _haversine(lat1, lon1, lat2, lon2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double d) => d * math.pi / 180.0;
}

