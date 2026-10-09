import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../engines/notification_engine.dart';
import '../models/complaint.dart';

/// Local-first persistent storage for the citizen complaint lifecycle.
///
/// This deliberately works alongside (not instead of) `AppStorage`: evidence
/// image files are still persisted through `AppStorage.saveEvidenceFile`,
/// while the structured complaint records + notifications live in their own
/// JSON files here for the offline-first shared repository.
class LocalComplaintDataSource {
  LocalComplaintDataSource();

  /// Test-only redirection of the JSON store (hermetic test suites).
  @visibleForTesting
  static Directory? baseDirectoryOverride;

  Directory get _baseDir {
    final override = baseDirectoryOverride;
    if (override != null) return override;
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['APPDATA'] ??
          'C:/Users/Dell/AppData/Local';
      return Directory('$localAppData/InfraVision/citizen');
    }
    final appDir = Directory('${Directory.systemTemp.parent.path}/app_flutter/InfraVision/citizen');
    if (!appDir.existsSync()) {
      try {
        appDir.createSync(recursive: true);
        return appDir;
      } catch (_) {}
    } else {
      return appDir;
    }
    return Directory('${Directory.systemTemp.path}/infravision_citizen');
  }

  File get _complaintsFile => File('${_baseDir.path}/complaints.json');
  File get _notificationsFile => File('${_baseDir.path}/notifications.json');

  Future<void> prepare() async {
    await _baseDir.create(recursive: true);
  }

  Future<List<Complaint>> loadComplaints() async {
    try {
      if (!await _complaintsFile.exists()) return [];
      final content = await _complaintsFile.readAsString();
      final list = jsonDecode(content) as List<dynamic>;
      return list
          .map((e) => Complaint.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LocalComplaintDataSource load error: $e');
      return [];
    }
  }

  Future<void> saveComplaints(List<Complaint> complaints) async {
    try {
      await prepare();
      await _complaintsFile.writeAsString(
          jsonEncode(complaints.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('LocalComplaintDataSource save error: $e');
    }
  }

  Future<List<NotificationItem>> loadNotifications() async {
    try {
      if (!await _notificationsFile.exists()) return [];
      final content = await _notificationsFile.readAsString();
      final list = jsonDecode(content) as List<dynamic>;
      return list
          .map((e) => NotificationItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveNotifications(List<NotificationItem> items) async {
    try {
      await prepare();
      await _notificationsFile.writeAsString(
          jsonEncode(items.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }
}
