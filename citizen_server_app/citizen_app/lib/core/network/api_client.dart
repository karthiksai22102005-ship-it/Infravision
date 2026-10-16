import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'models.dart';

/// Single shared HTTP client. Talks only to the Citizen backend, never to SQL Server.
class ApiClient {
  ApiClient({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;
  String? token;
  void Function()? onUnauthorized;

  Uri _u(String p, [Map<String, String>? q]) =>
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1$p').replace(queryParameters: q);

  Map<String, String> _h([Map<String, String>? extra]) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
        ...?extra,
      };

  Future<dynamic> _send(
    Future<http.Response> Function() call, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final r = await call().timeout(timeout);
      if (r.statusCode == 401) onUnauthorized?.call();
      if (r.statusCode >= 400) {
        String msg = 'Request failed (${r.statusCode})';
        try {
          final d = jsonDecode(utf8.decode(r.bodyBytes))['detail'];
          msg = d is String ? d : 'Please check the entered details';
        } catch (_) {}
        throw ApiException(msg, statusCode: r.statusCode);
      }
      return r;
    } on SocketException {
      throw ApiException('No connection to server', offline: true);
    } on TimeoutException {
      throw ApiException('Server took too long to respond', offline: true);
    } on http.ClientException {
      throw ApiException('No connection to server', offline: true);
    }
  }

  dynamic _json(http.Response r) => jsonDecode(utf8.decode(r.bodyBytes));

  Future<String> login(String email, String password) async {
    final r = await _send(() => _http.post(_u('/auth/login'),
        headers: _h(),
        body: jsonEncode({'email': email, 'password': password})));
    return _json(r)['access_token'];
  }

  Future<String> register(String email, String name, String password) async {
    final r = await _send(() => _http.post(_u('/auth/register'),
        headers: _h(),
        body: jsonEncode(
            {'email': email, 'full_name': name, 'password': password})));
    return _json(r)['access_token'];
  }

  Future<Map<String, dynamic>> me() async => Map<String, dynamic>.from(
      _json(await _send(() => _http.get(_u('/me'), headers: _h()))));

  Future<bool> aiReady() async {
    final r = await _send(() => _http.get(_u('/ai/status'), headers: _h()));
    return _json(r)['status'] == 'READY';
  }

  Future<String> askAI(String message, String language) async {
    final r = await _send(() => _http.post(_u('/ai/chat'),
        headers: _h(),
        body: jsonEncode({'message': message, 'language': language})));
    return _json(r)['reply'] as String;
  }

  Future<List<Category>> categories() async => [
        for (final c in _json(
                await _send(() => _http.get(_u('/categories'), headers: _h())))
            as List)
          Category.fromJson(c)
      ];

  Future<Complaint> createComplaint(
      Map<String, dynamic> body, String idempotencyKey) async {
    final r = await _send(() => _http.post(_u('/complaints'),
        headers: _h({'Idempotency-Key': idempotencyKey}),
        body: jsonEncode(body)));
    return Complaint.fromJson(_json(r));
  }

  Future<List<Complaint>> complaints({String? status}) async => [
        for (final c in _json(await _send(() => _http.get(
            _u('/complaints', status == null ? null : {'status': status}),
            headers: _h()))) as List)
          Complaint.fromJson(c)
      ];

  Future<Complaint> complaint(String ref) async => Complaint.fromJson(_json(
      await _send(() => _http.get(_u('/complaints/$ref'), headers: _h()))));

  Future<List<NearbyIssue>> nearby(double lat, double lng) async => [
        for (final c in _json(await _send(() => _http.get(
            _u('/complaints/nearby',
                {'lat': '$lat', 'lng': '$lng', 'radius_m': '3000'}),
            headers: _h()))) as List)
          NearbyIssue.fromJson(c)
      ];

  Future<void> uploadEvidence(String ref, File file) async {
    final req = http.MultipartRequest('POST', _u('/complaints/$ref/evidence'))
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(await http.MultipartFile.fromPath('file', file.path));
    await _send(
      () async => http.Response.fromStream(await _http.send(req)),
      timeout: const Duration(minutes: 3),
    );
  }

  Future<List<int>> evidenceBytes(String ref, int id) async =>
      (await _send(() =>
                  _http.get(_u('/complaints/$ref/evidence/$id'), headers: _h()))
              as http.Response)
          .bodyBytes;

  Future<List<int>> reportPdf(String ref) async => (await _send(
              () => _http.get(_u('/complaints/$ref/report.pdf'), headers: _h()))
          as http.Response)
      .bodyBytes;

  Future<List<AppNotification>> notifications() async => [
        for (final n in _json(await _send(
            () => _http.get(_u('/notifications'), headers: _h()))) as List)
          AppNotification.fromJson(n)
      ];
}
