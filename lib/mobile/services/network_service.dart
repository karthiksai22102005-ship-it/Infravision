import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/mobile_config.dart';
import '../core/app_logger.dart';

enum NetworkState {
  /// Not checked yet.
  unknown,
  /// No usable network interface at all.
  offline,
  /// The device has a network interface, internet path not verified yet.
  deviceConnected,
  /// The configured backend answered a reachability probe.
  backendReachable,
  /// Interfaces exist but the backend did not answer.
  backendUnreachable,
}

/// Lightweight network intelligence (§26/§27).
///
/// Three distinct questions are answered separately:
/// device connected -> internet available -> backend reachable.
/// There is no continuous polling: `refresh()` runs on demand (app resume,
/// sync start, manual pull-to-refresh) so the radio stays idle (§57).
class NetworkService extends ChangeNotifier {
  NetworkService();

  NetworkState _state = NetworkState.unknown;
  String _connectionType = 'unknown';
  DateTime? _lastChecked;
  String? _lastError;
  bool _checking = false;

  NetworkState get state => _state;
  String get connectionType => _connectionType;
  DateTime? get lastChecked => _lastChecked;
  String? get lastError => _lastError;
  bool get isChecking => _checking;

  bool get isOffline =>
      _state == NetworkState.offline || _state == NetworkState.unknown;
  bool get deviceConnected =>
      _state == NetworkState.deviceConnected ||
      _state == NetworkState.backendReachable;
  bool get backendReachable => _state == NetworkState.backendReachable;

  String get label {
    switch (_state) {
      case NetworkState.offline:
        return 'Offline';
      case NetworkState.deviceConnected:
        return 'Online';
      case NetworkState.backendReachable:
        return 'Online';
      case NetworkState.backendUnreachable:
        return 'Backend unreachable';
      case NetworkState.unknown:
        return 'Checking…';
    }
  }

  /// Runs one on-demand check. Never throws (§84).
  Future<NetworkState> refresh({String? baseUrl}) async {
    if (_checking) return _state;
    _checking = true;
    notifyListeners();

    try {
      // 1. Does the device have any usable interface?
      final List<NetworkInterface> interfaces = await NetworkInterface.list(
        type: InternetAddressType.any,
        includeLoopback: false,
      ).timeout(MobileConfig.reachabilityTimeout);
      final bool hasInterface = interfaces
          .any((NetworkInterface i) => i.addresses.isNotEmpty);

      _connectionType = await _probeConnectionType();

      if (!hasInterface) {
        _state = NetworkState.offline;
        _lastError = null;
      } else {
        _state = NetworkState.deviceConnected;

        // 2. Can the configured backend actually be reached?
        final String url = (baseUrl ?? '').trim();
        if (url.isNotEmpty && Uri.tryParse(url) != null) {
          final Uri probe = Uri.parse('$url${MobileConfig.apiPathPrefix}/app/version');
          final HttpClient client = HttpClient()
            ..connectionTimeout = MobileConfig.reachabilityTimeout;
          try {
            final HttpClientRequest request = await client
                .getUrl(probe)
                .timeout(MobileConfig.reachabilityTimeout);
            final HttpClientResponse response = await request
                .close()
                .timeout(MobileConfig.reachabilityTimeout);
            if (response.statusCode < 500) {
              _state = NetworkState.backendReachable;
              _lastError = null;
            } else {
              _state = NetworkState.backendUnreachable;
              _lastError = 'Backend returned ${response.statusCode}';
            }
          } finally {
            client.close(force: true);
          }
        }
      }
    } on TimeoutException {
      _state = NetworkState.deviceConnected;
      _lastError = 'Network check timed out.';
    } catch (e) {
      AppLog.e('Network', 'Refresh failed: $e');
      _lastError = 'Network check failed.';
      _state = NetworkState.offline;
    }

    _lastChecked = DateTime.now();
    _checking = false;
    notifyListeners();
    AppLog.d('Network', 'state=${_state.name} type=$_connectionType');
    return _state;
  }

  /// Reads the active transport type from the Android platform channel, with
  /// an honest `unknown` fallback when it is unavailable.
  Future<String> _probeConnectionType() async {
    try {
      final String? value = await const MethodChannel('infravision/system')
          .invokeMethod<String>('getNetworkType');
      return value ?? 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }
}