/// DOMAIN CONFIGURATION LAYER.
///
/// The core platform (observations, physical issues, matching, lifecycle)
/// contains zero domain vocabulary. Everything municipality/road-specific
/// lives here as configuration, so future domains (industrial maintenance,
/// facility management, telecom…) require only a new [DomainConfig] entry.
library;

class DomainRoleLabels {
  const DomainRoleLabels({
    required this.reporter,
    required this.fieldAgent,
    required this.resolutionTeam,
    required this.operationsManager,
  });

  final String reporter;
  final String fieldAgent;
  final String resolutionTeam;
  final String operationsManager;
}

class DomainWorkflowRules {
  const DomainWorkflowRules({
    this.requireFieldVerification = true,
    this.requireResolutionEvidence = true,
    this.autoEscalateAfterFailedVerifications = 2,
    this.verificationNeedsManagerApproval = false,
  });

  final bool requireFieldVerification;
  final bool requireResolutionEvidence;
  final int autoEscalateAfterFailedVerifications;
  final bool verificationNeedsManagerApproval;
}

class DomainConfig {
  const DomainConfig({
    required this.domainId,
    required this.displayName,
    required this.assetTypes,
    required this.issueTypes,
    required this.roles,
    required this.workflowRules,
    required this.slaHoursBySeverity,
    required this.minAiConfidence,
    this.issueTypeAliases = const {},
    this.zoneLabel = 'Zone',
  });

  final String domainId;
  final String displayName;
  final List<String> assetTypes;
  final List<String> issueTypes;
  final DomainRoleLabels roles;
  final DomainWorkflowRules workflowRules;

  /// key: severity label ('critical'|'high'|'moderate'|'low') → SLA hours.
  final Map<String, int> slaHoursBySeverity;

  /// Minimum AI confidence for a detection to become an Observation.
  final double minAiConfidence;

  /// Maps domain-specific detection labels onto canonical issue types, e.g.
  /// {'pothole': 'Road Surface Damage', 'cracked asphalt': 'Road Surface Damage'}.
  final Map<String, String> issueTypeAliases;

  final String zoneLabel;

  String canonicalIssueType(String? detectionLabel) {
    if (detectionLabel == null) return 'Unclassified';
    return issueTypeAliases[detectionLabel.toLowerCase().trim()] ??
        issueTypes.firstWhere(
          (t) => t.toLowerCase() == detectionLabel.toLowerCase().trim(),
          orElse: () => detectionLabel,
        );
  }
}

class DomainRegistry {
  DomainRegistry._();
  static final DomainRegistry instance = DomainRegistry._();

  final Map<String, DomainConfig> _domains = {};
  String _activeId = DomainCatalog.infrastructure.domainId;

  DomainConfig get active => byId(_activeId);

  DomainConfig byId(String id) =>
      _domains[id] ?? DomainCatalog.infrastructure;

  void register(DomainConfig config) => _domains[config.domainId] = config;

  void activate(String domainId) {
    if (_domains.containsKey(domainId)) _activeId = domainId;
  }

  bool aliasesMatch(String a, String b) {
    final ca = active.canonicalIssueType(a).toLowerCase();
    final cb = active.canonicalIssueType(b).toLowerCase();
    return ca == cb;
  }
}

/// Built-in demonstration domain — the existing road/municipality app.
class DomainCatalog {
  DomainCatalog._();

  static const infrastructure = DomainConfig(
    domainId: 'infrastructure',
    displayName: 'Infrastructure & Public Works',
    assetTypes: [
      'Road',
      'Footpath',
      'Streetlight',
      'Drainage',
      'Water Line',
      'Traffic Signal',
      'Public Building',
    ],
    issueTypes: [
      'Road Surface Damage',
      'Structural Damage',
      'Water Accumulation',
      'Lighting Failure',
      'Signal Fault',
      'Blockage',
      'Debris',
      'Graffiti',
    ],
    roles: DomainRoleLabels(
      reporter: 'Citizen Reporter',
      fieldAgent: 'Field Inspector',
      resolutionTeam: 'Repair Crew',
      operationsManager: 'Supervisor',
    ),
    workflowRules: DomainWorkflowRules(),
    slaHoursBySeverity: {
      'critical': 24,
      'high': 48,
      'moderate': 168,
      'low': 336,
    },
    minAiConfidence: 0.60,
    issueTypeAliases: {
      'pothole': 'Road Surface Damage',
      'pothole & asphalt degradation': 'Road Surface Damage',
      'crack': 'Road Surface Damage',
      'asphalt degradation': 'Road Surface Damage',
      'concrete & structural': 'Structural Damage',
      'drainage & public health': 'Water Accumulation',
      'streetlight & traffic signal': 'Lighting Failure',
      'manhole / drainage': 'Blockage',
      'water logging': 'Water Accumulation',
      'debris': 'Debris',
    },
    zoneLabel: 'Zone',
  );
}
