import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Token lives in encrypted storage; language, draft and cached summaries in prefs.
/// Cached data is display-only and never treated as authoritative.
class LocalStore {
  static const _secure = FlutterSecureStorage();
  late SharedPreferences _p;

  Future<void> init() async => _p = await SharedPreferences.getInstance();

  Future<String?> readToken() => _secure.read(key: 'token');
  Future<void> saveToken(String? t) => t == null
      ? _secure.delete(key: 'token')
      : _secure.write(key: 'token', value: t);

  String get language => _p.getString('lang') ?? 'en';
  set language(String v) => _p.setString('lang', v);
  String get themePreference => _p.getString('theme') ?? 'light';
  set themePreference(String v) => _p.setString('theme', v);
  bool get onboarded => _p.getBool('onboarded') ?? false;
  set onboarded(bool v) => _p.setBool('onboarded', v);

  Map<String, dynamic>? readDraft() {
    final s = _p.getString('draft');
    if (s == null) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      // Discard a damaged draft cache instead of preventing the entire app from
      // launching after an interrupted write or OS restore.
      return null;
    }
  }

  Future<void> saveDraft(Map<String, dynamic>? d) =>
      d == null ? _p.remove('draft') : _p.setString('draft', jsonEncode(d));

  /// Photos whose upload failed after the complaint was created: {reference: [paths]}
  Map<String, List<String>> readPending() {
    final s = _p.getString('pending');
    if (s == null) return {};
    try {
      return (jsonDecode(s) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, List<String>.from(v)));
    } catch (_) {
      return {};
    }
  }

  Future<void> savePending(Map<String, List<String>> m) =>
      _p.setString('pending', jsonEncode(m));

  /// Offline category cache so starting a complaint offline is never blocked.
  List<Map<String, dynamic>>? readCategories() {
    final s = _p.getString('cached_categories');
    if (s == null) return null;
    try {
      final list = jsonDecode(s) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCategories(List<Map<String, dynamic>> categories) =>
      _p.setString('cached_categories', jsonEncode(categories));

  /// Optional runtime override for the API base URL (useful for real phones on LAN).
  String? readCustomBaseUrl() => _p.getString('custom_api_base_url');
  Future<void> saveCustomBaseUrl(String? url) => url == null
      ? _p.remove('custom_api_base_url')
      : _p.setString('custom_api_base_url', url);
}
