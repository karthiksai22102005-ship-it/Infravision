import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Production-safe logging for the InfraVision Observation Portal (Android).
///
/// Rules enforced here:
/// - Verbose logs are compiled out of release builds unless explicitly
///   enabled with `--dart-define=INFRAVISION_VERBOSE_LOG=true`.
/// - Nothing sensitive may be logged: no tokens, passwords, credentials or
///   personal data. Call sites pass only technical diagnostics.
/// - A small bounded ring buffer keeps the last diagnostic lines so the
///   in-app Diagnostics/About screen can show real information without
///   writing log files to disk.
class AppLog {
  AppLog._();

  /// Verbose logging is OFF in release builds (see class docs).
  static const bool verbose =
      kDebugMode || bool.fromEnvironment('INFRAVISION_VERBOSE_LOG');

  static const int _ringCapacity = 120;
  static final Queue<String> _ring = Queue<String>();

  /// Most recent diagnostic lines (newest last). Never contains secrets.
  static List<String> get diagnostics => List<String>.unmodifiable(_ring);

  /// Technical debug line — dropped entirely in production builds.
  static void d(String scope, String message) {
    if (!verbose) return;
    _push('D/$scope', message);
    debugPrint('[InfraVision][$scope] $message');
  }

  /// Error/information line that is kept in production diagnostics.
  static void e(String scope, String message) {
    _push('E/$scope', message);
    if (verbose) {
      debugPrint('[InfraVision][$scope] $message');
    }
  }

  /// Informational line kept in the diagnostics ring buffer.
  static void i(String scope, String message) {
    _push('I/$scope', message);
    if (verbose) {
      debugPrint('[InfraVision][$scope] $message');
    }
  }

  static void clear() => _ring.clear();

  static void _push(String tag, String message) {
    final String line =
        '${DateTime.now().toIso8601String().substring(11, 19)} $tag $message';
    _ring.addLast(line);
    while (_ring.length > _ringCapacity) {
      _ring.removeFirst();
    }
  }
}
