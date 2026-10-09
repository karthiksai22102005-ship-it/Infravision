import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/app_logger.dart';

/// Adaptive performance profile (§50-54).
enum PerformanceProfile {
  ultraLow('Ultra low'),
  low('Low'),
  balanced('Balanced'),
  high('High'),
  premium('Premium');

  const PerformanceProfile(this.label);
  final String label;

  static PerformanceProfile fromName(Object? name) {
    for (final PerformanceProfile v in PerformanceProfile.values) {
      if (v.name == name) return v;
    }
    return PerformanceProfile.balanced;
  }
}

/// Thermal pressure reported by Android (§59).
enum ThermalLevel { unknown, normal, warm, hot, critical }

/// Real numbers read from the device. Every field may be null when the OEM
/// does not expose it — the portal never guesses (§50).
class DeviceSystemStats {
  const DeviceSystemStats({
    this.totalRamMb,
    this.availableRamMb,
    this.totalStorageMb,
    this.availableStorageMb,
    this.batteryPercent,
    this.batteryCharging,
    this.thermalLevel,
    this.lowMemoryFlag,
    this.powerSaveMode,
    this.networkType,
    this.sdkInt,
    this.source = 'unknown',
  });

  final int? totalRamMb;
  final int? availableRamMb;
  final int? totalStorageMb;
  final int? availableStorageMb;
  final int? batteryPercent;
  final bool? batteryCharging;
  final ThermalLevel? thermalLevel;
  final bool? lowMemoryFlag;
  final bool? powerSaveMode;

  /// `wifi` | `cellular` | `none` | `unknown`
  final String? networkType;
  final int? sdkInt;
  final String source;

  static const DeviceSystemStats unknown = DeviceSystemStats();
}

/// Detects the real device capabilities and derives an adaptive profile.
///
/// Data sources, in order of preference:
/// 1. Android platform channel (`infravision/system`) — RAM, storage, battery,
///    thermal status, network type, SDK level.
/// 2. `/proc` and sysfs reads (guarded, may be restricted on some OEMs).
/// 3. CPU core count from Dart — always available.
/// Missing values stay null instead of being invented.
class DeviceCapabilityService extends ChangeNotifier {
  DeviceCapabilityService();

  static const MethodChannel _channel = MethodChannel('infravision/system');

  DeviceSystemStats _stats = DeviceSystemStats.unknown;
  int _cpuCores = Platform.numberOfProcessors;
  PerformanceProfile _profile = PerformanceProfile.balanced;
  bool _batterySaver = false;
  bool _syncPausedForBattery = false;
  bool _initialized = false;

  DeviceSystemStats get stats => _stats;
  int get cpuCores => _cpuCores;
  PerformanceProfile get profile => _profile;
  bool get batterySaver => _batterySaver;
  bool get syncPausedForBattery => _syncPausedForBattery;
  bool get isInitialized => _initialized;
  ThermalLevel get thermal => _stats.thermalLevel ?? ThermalLevel.unknown;
  int? get batteryPercent => _stats.batteryPercent;

  /// True when the app should throttle non-essential work (§58/§59).
  bool get shouldReduceWork =>
      _batterySaver ||
      _syncPausedForBattery ||
      thermal == ThermalLevel.hot ||
      thermal == ThermalLevel.critical;

  Future<void> initialize() async {
    _cpuCores = Platform.numberOfProcessors;
    DeviceSystemStats platformStats = DeviceSystemStats.unknown;
    try {
      final Map<Object?, Object?>? raw = await _channel.invokeMapMethod<Object?, Object?>('getSystemStats');
      if (raw != null) {
        platformStats = DeviceSystemStats(
          totalRamMb: (raw['totalRamMb'] as num?)?.toInt(),
          availableRamMb: (raw['availableRamMb'] as num?)?.toInt(),
          totalStorageMb: (raw['totalStorageMb'] as num?)?.toInt(),
          availableStorageMb: (raw['availableStorageMb'] as num?)?.toInt(),
          batteryPercent: (raw['batteryPercent'] as num?)?.toInt(),
          batteryCharging: raw['batteryCharging'] as bool?,
          thermalLevel: _thermalFromName('${raw['thermalLevel']}'),
          lowMemoryFlag: raw['lowMemory'] as bool?,
          powerSaveMode: raw['powerSaveMode'] as bool?,
          networkType: raw['networkType'] as String?,
          sdkInt: (raw['sdkInt'] as num?)?.toInt(),
          source: 'platform-channel',
        );
      }
    } on MissingPluginException {
      AppLog.d('Capability', 'System channel unavailable on this platform');
    } on PlatformException catch (e) {
      AppLog.e('Capability', 'System channel error: ${e.code}');
    }

    if (platformStats.source == 'unknown') {
      platformStats = _readFromProc();
    }

    _stats = platformStats;
    _applyProfile();
    _initialized = true;
    AppLog.i(
      'Capability',
      'Profile=${_profile.name} cores=$_cpuCores ram=${_stats.totalRamMb ?? '?'}MB '
      'battery=${_stats.batteryPercent ?? '?'}% thermal=${thermal.name} source=${_stats.source}',
    );
    notifyListeners();
  }

  ThermalLevel _thermalFromName(String value) {
    switch (value.toLowerCase()) {
      case 'normal':
        return ThermalLevel.normal;
      case 'warm':
        return ThermalLevel.warm;
      case 'hot':
        return ThermalLevel.hot;
      case 'critical':
        return ThermalLevel.critical;
      default:
        return ThermalLevel.unknown;
    }
  }
  /// Fallback reader for environments where the platform channel is absent.
  /// Returns only values that were really read; everything else stays null.
  DeviceSystemStats _readFromProc() {
    try {
      final File meminfo = File('/proc/meminfo');
      if (meminfo.existsSync()) {
        final String text = meminfo.readAsStringSync();
        final RegExpMatch? total = RegExp(r'MemTotal:\s+(\d+) kB').firstMatch(text);
        final RegExpMatch? avail = RegExp(r'MemAvailable:\s+(\d+) kB').firstMatch(text);
        return DeviceSystemStats(
          totalRamMb: total == null
              ? null
              : int.parse(total.group(1)!) ~/ 1024,
          availableRamMb: avail == null
              ? null
              : int.parse(avail.group(1)!) ~/ 1024,
          source: 'procfs',
        );
      }
    } catch (e) {
      AppLog.d('Capability', '/proc read unavailable: $e');
    }
    return DeviceSystemStats.unknown;
  }

  /// Recomputes the profile from the freshest available numbers (§50).
  void _applyProfile() {
    final int ram = _stats.totalRamMb ?? 0;
    final int cores = _cpuCores;
    final bool lowMemory = _stats.lowMemoryFlag == true;

    PerformanceProfile next;
    if (lowMemory || (ram > 0 && ram < 2500) || cores <= 3) {
      next = PerformanceProfile.ultraLow;
    } else if ((ram > 0 && ram < 4000) || cores <= 4) {
      next = PerformanceProfile.low;
    } else if (ram > 0 && ram >= 10000 && cores >= 8) {
      next = PerformanceProfile.premium;
    } else if (ram > 0 && ram >= 7000 && cores >= 8) {
      next = PerformanceProfile.high;
    } else {
      next = PerformanceProfile.balanced;
    }

    final int? battery = _stats.batteryPercent;
    final bool charging = _stats.batteryCharging == true;
    _batterySaver = _stats.powerSaveMode == true ||
        (battery != null && battery <= 15 && !charging);
    _syncPausedForBattery = battery != null && battery <= 5 && !charging;

    if (next != _profile) {
      _profile = next;
      AppLog.i('Capability', 'Profile changed to ${next.name}');
    }
  }

  /// Lightweight refresh triggered on app resume / explicit user action.
  Future<void> refresh() async {
    await initialize();
  }

  /// Camera resolution preset derived from the profile (§61).
  ResolutionPresetForCamera get cameraPreset {
    switch (_profile) {
      case PerformanceProfile.ultraLow:
        return ResolutionPresetForCamera.medium;
      case PerformanceProfile.low:
        return ResolutionPresetForCamera.high;
      case PerformanceProfile.balanced:
        return ResolutionPresetForCamera.high;
      case PerformanceProfile.high:
        return ResolutionPresetForCamera.veryHigh;
      case PerformanceProfile.premium:
        return ResolutionPresetForCamera.veryHigh;
    }
  }

  int get aiMaxDimension {
    final int base = switch (_profile) {
      PerformanceProfile.ultraLow => 320,
      PerformanceProfile.low => 480,
      PerformanceProfile.balanced => 640,
      PerformanceProfile.high => 640,
      PerformanceProfile.premium => 800,
    };
    if (thermal == ThermalLevel.hot || thermal == ThermalLevel.critical) {
      return (base * 0.6).round();
    }
    return base;
  }

  int get uploadConcurrency {
    final int base = switch (_profile) {
      PerformanceProfile.ultraLow => 1,
      PerformanceProfile.low => 1,
      PerformanceProfile.balanced => 2,
      PerformanceProfile.high => 3,
      PerformanceProfile.premium => 3,
    };
    return shouldReduceWork ? 1 : base;
  }

  int get cacheBudgetBytes => switch (_profile) {
        PerformanceProfile.ultraLow => 40 * 1024 * 1024,
        PerformanceProfile.low => 80 * 1024 * 1024,
        PerformanceProfile.balanced => 120 * 1024 * 1024,
        PerformanceProfile.high => 200 * 1024 * 1024,
        PerformanceProfile.premium => 300 * 1024 * 1024,
      };

  int get thumbnailDimension => switch (_profile) {
        PerformanceProfile.ultraLow => 240,
        PerformanceProfile.low => 280,
        PerformanceProfile.balanced => 320,
        PerformanceProfile.high => 320,
        PerformanceProfile.premium => 384,
      };

  bool get richAnimations => _profile != PerformanceProfile.ultraLow;

  bool get useSimplifiedMap => _profile == PerformanceProfile.ultraLow ||
      thermal == ThermalLevel.hot ||
      thermal == ThermalLevel.critical;

}

/// Camera resolution selection kept independent of `package:camera` so this
/// service can be unit-tested without platform plugins.
enum ResolutionPresetForCamera { medium, high, veryHigh }