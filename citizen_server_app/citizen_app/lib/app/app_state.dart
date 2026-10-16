import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/foundation.dart' hide Category;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/config/app_config.dart';
import '../core/localization/strings.dart';
import '../core/network/api_client.dart';
import '../core/network/models.dart';
import '../core/ml/pothole_detector.dart';
import '../core/storage/local_store.dart';

class Draft {
  String? categoryCode;
  String description = '';
  double? lat, lng, accuracy;
  String? address;
  List<String> photos = [];
  List<String> videos = [];
  Map<String, Map<String, dynamic>> photoAnalyses = {};
  String idempotencyKey =
      const Uuid().v4(); // stable across retries of the same report
  List<Detection> aiDetections = [];

  bool get hasLocation => lat != null && lng != null;
  bool get isEmpty =>
      categoryCode == null &&
      description.isEmpty &&
      photos.isEmpty &&
      videos.isEmpty &&
      !hasLocation;

  Map<String, dynamic> toJson() => {
        'cat': categoryCode,
        'desc': description,
        'lat': lat,
        'lng': lng,
        'acc': accuracy,
        'addr': address,
        'photos': photos,
        'videos': videos,
        'key': idempotencyKey,
        'photoAnalyses': photoAnalyses,
        'ai': aiDetections.map((d) => d.toJson()).toList(),
      };

  static Draft fromJson(Map<String, dynamic> j) => Draft()
    ..categoryCode = j['cat']
    ..description = j['desc'] ?? ''
    ..lat = (j['lat'] as num?)?.toDouble()
    ..lng = (j['lng'] as num?)?.toDouble()
    ..accuracy = (j['acc'] as num?)?.toDouble()
    ..address = j['addr']
    ..photos = List<String>.from(j['photos'] ?? [])
    ..videos = List<String>.from(j['videos'] ?? [])
    ..photoAnalyses = (j['photoAnalyses'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)))
    ..idempotencyKey = j['key'] ?? const Uuid().v4()
    ..aiDetections = (j['ai'] as List?)
            ?.map((e) => Detection(
                  x1: (e['x1'] as num).toDouble(),
                  y1: (e['y1'] as num).toDouble(),
                  x2: (e['x2'] as num).toDouble(),
                  y2: (e['y2'] as num).toDouble(),
                  confidence: (e['confidence'] as num).toDouble(),
                  label: e['label'] ?? 'pothole',
                ))
            .toList() ??
        [];
}

class AppState extends ChangeNotifier {
  AppState(this.api, this.store);
  final ApiClient api;
  final LocalStore store;
  final PotholeDetector detector = PotholeDetector();

  String lang = 'en';
  String themePreference = 'light';
  ThemeMode get themeMode => switch (themePreference) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  S get s => S(lang);
  bool signedIn = false;
  bool initialized = false;
  String? startupError;
  bool loading = false;
  String? error;
  bool offline = false;

  List<Category> categories = Category.defaultMunicipalCategories;
  List<Complaint> complaints = [];
  List<AppNotification> notifications = [];
  Draft draft = Draft();
  Map<String, List<String>> pendingUploads = {};
  Complaint? lastSubmitted;
  String? submitWarning;

  @override
  void dispose() {
    detector.dispose();
    super.dispose();
  }

  Future<void> init() async {
    await store.init();
    lang = store.language;
    themePreference = store.themePreference;
    pendingUploads = store.readPending();

    // Load custom server URL if configured
    final customUrl = store.readCustomBaseUrl();
    if (customUrl != null) AppConfig.customApiBaseUrl = customUrl;

    // Load cached categories or fallback to municipal defaults
    try {
      final cachedCats = store.readCategories();
      if (cachedCats != null && cachedCats.isNotEmpty) {
        categories = cachedCats.map((c) => Category.fromJson(c)).toList();
      } else {
        categories = Category.defaultMunicipalCategories;
      }
    } catch (error) {
      debugPrint('Ignoring invalid cached categories: $error');
      categories = Category.defaultMunicipalCategories;
    }

    try {
      final savedDraft = store.readDraft();
      if (savedDraft != null) draft = Draft.fromJson(savedDraft);
    } catch (error) {
      debugPrint('Discarding invalid cached draft: $error');
      draft = Draft();
      await store.saveDraft(null);
    }
    api.onUnauthorized = () => signOut();
    // Android secure-storage implementations can fail on device/OS variants
    // (for example after a restore or key invalidation). Treat that as a signed-
    // out session so the citizen can still reach the app and sign in again.
    try {
      api.token = await store.readToken();
    } catch (error) {
      debugPrint(
          'Could not restore saved session; starting signed out: $error');
      api.token = null;
    }
    signedIn = api.token != null;
    initialized = true;
    startupError = null;
    notifyListeners();
  }

  /// Keep Flutter visible even if local OS storage fails during app startup.
  Future<void> initialize() async {
    initialized = false;
    startupError = null;
    try {
      await init();
    } catch (error, stack) {
      debugPrint('InfraVision startup initialization failed: $error\n$stack');
      startupError = error.toString();
      notifyListeners();
    }
  }

  void setLanguage(String l) {
    lang = l;
    store.language = l;
    notifyListeners();
  }

  void setTheme(String pref) {
    themePreference = pref;
    store.themePreference = pref;
    notifyListeners();
  }

  Future<void> setServerUrl(String? value) async {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      AppConfig.customApiBaseUrl = null;
      await store.saveCustomBaseUrl(null);
      notifyListeners();
      return;
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
          'Enter a server URL such as http://192.168.1.20:8000');
    }
    final baseUrl = normalized.replaceAll(RegExp(r'/+$'), '');
    AppConfig.customApiBaseUrl = baseUrl;
    await store.saveCustomBaseUrl(baseUrl);
    notifyListeners();
  }

  Future<T?> _guard<T>(Future<T> Function() fn) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final r = await fn();
      offline = false;
      return r;
    } on ApiException catch (e) {
      error = e.message;
      offline = e.offline;
      return null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> authenticate(String email, String password,
      {String? name}) async {
    final t = await _guard(() => name == null
        ? api.login(email, password)
        : api.register(email, name, password));
    if (t == null) return false;
    api.token = t;
    await store.saveToken(t);
    signedIn = true;
    await refreshAll();
    return true;
  }

  Future<void> signOut() async {
    api.token = null;
    await store.saveToken(null);
    signedIn = false;
    complaints = [];
    notifications = [];
    notifyListeners();
  }

  /// Server is authoritative: always re-fetch; cache is never trusted.
  Future<void> refreshAll() async {
    await _guard(() async {
      final freshCats = await api.categories();
      if (freshCats.isNotEmpty) {
        categories = freshCats;
        await store.saveCategories(categories.map((c) => c.toJson()).toList());
      }
      complaints = await api.complaints();
      notifications = await api.notifications();
    });
    await retryPendingUploads();
  }

  Future<void> refreshComplaint(String ref) async {
    final c = await _guard(() => api.complaint(ref));
    if (c != null) {
      final i = complaints.indexWhere((x) => x.reference == ref);
      i >= 0 ? complaints[i] = c : complaints.insert(0, c);
      notifyListeners();
    }
  }

  // ---------------- draft ----------------
  Future<void> updateDraft(void Function(Draft d) fn) async {
    fn(draft);
    await store.saveDraft(draft.isEmpty ? null : draft.toJson());
    notifyListeners();
  }

  /// Copies media to persistent app storage so OS cache cleans never delete drafts.
  Future<String> _persistMedia(String srcPath, String prefix) async {
    try {
      final file = File(srcPath);
      if (!await file.exists()) {
        throw ApiException(
            'Selected evidence is no longer available. Add it again.');
      }
      final appDir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory('${appDir.path}/infravision_draft_media');
      if (!await mediaDir.exists()) await mediaDir.create(recursive: true);
      final ext = srcPath.contains('.')
          ? srcPath.split('.').last
          : (prefix == 'video' ? 'mp4' : 'jpg');
      final destPath =
          '${mediaDir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}_${const Uuid().v4().substring(0, 8)}.$ext';
      final saved = await file.copy(destPath);
      return saved.path;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
          'Could not save evidence to this device. Check free storage and try again.');
    }
  }

  Future<String> addPhoto(String path) async {
    final size = await File(path).length();
    if (size > AppConfig.maxPhotoBytes) {
      throw ApiException('Photo is larger than 8 MB');
    }
    if (draft.photos.length >= AppConfig.maxPhotos) {
      throw ApiException('Maximum ${AppConfig.maxPhotos} photos');
    }
    final durablePath = await _persistMedia(path, 'photo');
    await updateDraft((d) => d.photos.add(durablePath));
    return durablePath;
  }

  Future<void> addVideo(String path) async {
    final size = await File(path).length();
    if (size > 50 * 1024 * 1024) {
      throw ApiException('Video is larger than 50 MB');
    }
    if (draft.videos.length >= 2) {
      throw ApiException('Maximum 2 videos per report');
    }
    final durablePath = await _persistMedia(path, 'video');
    await updateDraft((d) => d.videos.add(durablePath));
  }

  Future<void> savePhotoAnalysis(
      String path, Map<String, dynamic> analysis) async {
    draft.photoAnalyses[path] = analysis;
    final detections = analysis['detections'] as List?;
    if (detections != null && detections.isNotEmpty) {
      final hasPothole = detections.any((d) => d['label'] == 'pothole');
      if (hasPothole && draft.categoryCode == null) {
        draft.categoryCode = 'pothole';
      }
    }
    await store.saveDraft(draft.isEmpty ? null : draft.toJson());
    notifyListeners();
  }

  Future<void> removePhoto(int index) async {
    if (index >= 0 && index < draft.photos.length) {
      final removed = draft.photos.removeAt(index);
      draft.photoAnalyses.remove(removed);
      await store.saveDraft(draft.isEmpty ? null : draft.toJson());
      notifyListeners();
    }
  }

  Future<void> removePhotoPath(String path) async {
    final index = draft.photos.indexOf(path);
    if (index >= 0) await removePhoto(index);
  }

  // ---------------- submit ----------------
  /// Success is reported ONLY after the server confirms persistence.
  Future<bool> submit() async {
    submitWarning = null;
    final d = draft;
    final c = await _guard(() => api.createComplaint({
          'category_code': d.categoryCode,
          'description': d.description.trim(),
          'latitude': d.lat,
          'longitude': d.lng,
          'accuracy_m': d.accuracy,
          'address': d.address,
        }, d.idempotencyKey));
    if (c == null) {
      return false; // same idempotency key is reused when the user retries
    }

    // The complaint reference is authoritative once createComplaint returns.
    // Persist the evidence queue before navigating, then upload in the
    // background so a slow media transfer cannot make Submit appear stuck.
    final evidence = [...d.photos, ...d.videos];
    if (evidence.isNotEmpty) {
      pendingUploads[c.reference] = evidence;
      await store.savePending(pendingUploads);
    }
    lastSubmitted = c;
    draft = Draft();
    await store.saveDraft(null);
    // Refresh counts/status without holding the success transition open.
    unawaited(refreshAll());
    return true;
  }

  Future<void> retryPendingUploads() async {
    if (pendingUploads.isEmpty) return;
    for (final ref in pendingUploads.keys.toList()) {
      final still = <String>[];
      for (final p in pendingUploads[ref]!) {
        try {
          await api.uploadEvidence(ref, File(p));
        } on ApiException catch (e) {
          if (e.statusCode == null || e.statusCode! >= 500) {
            still.add(p); // keep only transient failures
          }
        }
      }
      still.isEmpty ? pendingUploads.remove(ref) : pendingUploads[ref] = still;
      if (still.isNotEmpty) {
        submitWarning = '${still.length} evidence file(s) are still uploading.';
      }
    }
    await store.savePending(pendingUploads);
  }

  int get unread => notifications.where((n) => !n.isRead).length;
}
