import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/mobile_config.dart';
import '../core/app_logger.dart';
import '../core/result.dart';

/// API paths (§70). The base URL is never hard-coded — it comes from build
/// config or the Settings screen.
class ApiEndpoints {
  ApiEndpoints._();

  static const String observations = '${MobileConfig.apiPathPrefix}/observations';
  static String observationById(String id) =>
      '${MobileConfig.apiPathPrefix}/observations/$id';
  static const String myObservations =
      '${MobileConfig.apiPathPrefix}/observations/my';
  static const String nearby = '${MobileConfig.apiPathPrefix}/observations/nearby';
  static String timeline(String id) =>
      '${MobileConfig.apiPathPrefix}/observations/$id/timeline';
  static const String evidence = '${MobileConfig.apiPathPrefix}/evidence';
  static const String videos = '${MobileConfig.apiPathPrefix}/videos';
  static const String sync = '${MobileConfig.apiPathPrefix}/sync';
  static const String appVersion = '${MobileConfig.apiPathPrefix}/app/version';
  static const String appConfig = '${MobileConfig.apiPathPrefix}/app/config';
  static const String models = '${MobileConfig.apiPathPrefix}/models';
}

/// Typed API failure — never a raw exception reaches the UI (§69/§84).
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  /// Network/5xx failures are worth retrying; 4xx are not (§30).
  bool get isTransient =>
      code == 'network' || code == 'timeout' || (statusCode ?? 500) >= 500;

  @override
  String toString() => 'ApiException($code, status=$statusCode)';
}

/// Thin HTTP wrapper: timeouts, request ids, API version header, JSON and
/// multipart upload, uniform error mapping (§69).
class ApiClient {
  ApiClient({http.Client? client, required this.baseUrl, this.authToken})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String? authToken;

  /// Configured backend base URL ("" means backend not configured).
  final String baseUrl;

  String get _newRequestId => 'req-${DateTime.now().millisecondsSinceEpoch}';

  bool get isConfigured {
    final Uri? uri = Uri.tryParse(baseUrl);
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  Uri? _uri(String path) => isConfigured ? Uri.parse('$baseUrl$path') : null;

  Map<String, String> _headers({String? idempotencyKey}) => <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-API-Version': '${MobileConfig.apiVersion}',
        'X-Request-Id': _newRequestId,
        if (authToken != null && authToken!.isNotEmpty)
          'Authorization': 'Bearer $authToken',
        if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
      };

  Future<Result<Map<String, dynamic>>> getJson(String path) async {
    final Uri? uri = _uri(path);
    if (uri == null) {
      return const Err<Map<String, dynamic>>(
        Failure('backend_not_configured', 'Backend is not configured.'),
      );
    }
    try {
      final http.Response response = await _client
          .get(uri, headers: _headers())
          .timeout(MobileConfig.readTimeout);
      return _decode(response);
    } on TimeoutException {
      return const Err<Map<String, dynamic>>(
        Failure('timeout', 'Request timed out.'),
      );
    } on SocketException {
      return const Err<Map<String, dynamic>>(
        Failure('network', 'No internet connection.'),
      );
    } catch (e) {
      AppLog.e('Api', 'GET $path failed: $e');
      return const Err<Map<String, dynamic>>(
        Failure('network', 'Could not reach the server.'),
      );
    }
  }

  Future<Result<Map<String, dynamic>>> postJson(
    String path,
    Map<String, dynamic> body, {
    String? idempotencyKey,
  }) async {
    final Uri? uri = _uri(path);
    if (uri == null) {
      return const Err<Map<String, dynamic>>(
        Failure('backend_not_configured', 'Backend is not configured.'),
      );
    }
    try {
      final http.Response response = await _client
          .post(
            uri,
            headers: _headers(idempotencyKey: idempotencyKey),
            body: jsonEncode(body),
          )
          .timeout(MobileConfig.readTimeout);
      return _decode(response);
    } on TimeoutException {
      return const Err<Map<String, dynamic>>(
        Failure('timeout', 'Request timed out.'),
      );
    } on SocketException {
      return const Err<Map<String, dynamic>>(
        Failure('network', 'No internet connection.'),
      );
    } catch (e) {
      AppLog.e('Api', 'POST $path failed: $e');
      return const Err<Map<String, dynamic>>(
        Failure('network', 'Could not reach the server.'),
      );
    }
  }
  /// Multipart upload with progress reporting (§16/§31/§32).
  Future<Result<Map<String, dynamic>>> uploadEvidence({
    required String path,
    required File file,
    required String field,
    required Map<String, String> fields,
    void Function(double progress)? onProgress,
  }) async {
    final Uri? uri = _uri(path);
    if (uri == null) {
      return const Err<Map<String, dynamic>>(
        Failure('backend_not_configured', 'Backend is not configured.'),
      );
    }
    try {
      final http.MultipartRequest request = http.MultipartRequest('POST', uri)
        ..headers.addAll(_headers(idempotencyKey: fields['idempotencyKey']))
        ..files.add(await http.MultipartFile.fromPath(field, file.path));
      fields.forEach((String key, String value) {
        if (key != 'idempotencyKey') request.fields[key] = value;
      });

      final http.StreamedResponse streamed =
          await _client.send(request).timeout(MobileConfig.uploadTimeout);
      final List<int> bytes = <int>[];
      final int? total = streamed.contentLength;
      await for (final List<int> chunk in streamed.stream) {
        bytes.addAll(chunk);
        if (total != null && total > 0 && onProgress != null) {
          onProgress((bytes.length / total).clamp(0.0, 1.0));
        }
      }
      return _decode(
        http.Response.bytes(bytes, streamed.statusCode),
      );
    } on TimeoutException {
      return const Err<Map<String, dynamic>>(
        Failure('timeout', 'Upload timed out.'),
      );
    } on SocketException {
      return const Err<Map<String, dynamic>>(
        Failure('network', 'Connection lost during upload.'),
      );
    } catch (e) {
      AppLog.e('Api', 'Upload failed: $e');
      return const Err<Map<String, dynamic>>(
        Failure('network', 'Upload failed.'),
      );
    }
  }

  Result<Map<String, dynamic>> _decode(http.Response response) {
    final String body = utf8.decode(response.bodyBytes, allowMalformed: true);
    Map<String, dynamic> json = <String, dynamic>{};
    if (body.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(body);
        if (decoded is Map) json = Map<String, dynamic>.from(decoded);
      } catch (_) {
        // Non-JSON body — only an issue when the status is an error below.
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Ok<Map<String, dynamic>>(json);
    }

    final String message =
        '${json['message'] ?? json['error'] ?? 'Request was rejected.'}';
    return Err<Map<String, dynamic>>(
      Failure('http_${response.statusCode}', message),
    );
  }

  void dispose() => _client.close();
}