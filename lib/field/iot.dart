/// GENERIC IoT ARCHITECTURE — devices, capabilities, readings, events and
/// the provider abstraction. Nothing here knows about roads or potholes.
/// REAL / SIMULATED / MOCK is explicit everywhere: simulated data is never
/// presented as real hardware data.
library;

import 'field_events.dart';

/// Explicit data provenance, surfaced end-to-end on every NormalizedEvent.
typedef FieldDataSourceMode = DataSourceMode;

enum ConnectionState { connected, connecting, disconnected, unavailable }

enum HealthStatus { healthy, degraded, failing, unknown }

class DeviceCapabilities {
  const DeviceCapabilities({
    this.supportsCamera = false,
    this.supportsGps = false,
    this.supportsVideo = false,
    this.supportsSensorData = false,
    this.supportsOfflineBuffer = false,
    this.supportsRealtimeStream = false,
    this.supportedSensors = const [],
    this.supportedProtocols = const [],
  });

  final bool supportsCamera;
  final bool supportsGps;
  final bool supportsVideo;
  final bool supportsSensorData;
  final bool supportsOfflineBuffer;
  final bool supportsRealtimeStream;
  final List<String> supportedSensors;
  final List<String> supportedProtocols;
}

class IoTDevice {
  IoTDevice({
    required this.deviceId,
    required this.deviceType,
    required this.capabilities,
    this.manufacturer,
    this.model,
    this.connectionState = ConnectionState.disconnected,
    this.healthStatus = HealthStatus.unknown,
    this.lastSeen,
    this.assignedContext,
    this.metadata = const {},
  });

  final String deviceId;
  final String deviceType;
  final DeviceCapabilities capabilities;
  final String? manufacturer;
  final String? model;
  ConnectionState connectionState;
  HealthStatus healthStatus;
  DateTime? lastSeen;
  final String? assignedContext;
  final Map<String, dynamic> metadata;
}

class SensorReading {
  SensorReading({
    required this.readingId,
    required this.deviceId,
    required this.sensorType,
    required this.value,
    required this.unit,
    required this.timestamp,
    this.quality = 'good',
    this.latitude,
    this.longitude,
    this.assetId,
    this.metadata = const {},
  });

  final String readingId;
  final String deviceId;
  final String sensorType;
  final double value;
  final String unit;
  final DateTime timestamp;
  final String quality;
  final double? latitude;
  final double? longitude;
  final String? assetId;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toAdapterMap(
          {bool anomaly = false,
          DataSourceMode mode = DataSourceMode.real}) =>
      {
        'deviceId': deviceId,
        'sensorType': sensorType,
        'value': value,
        'unit': unit,
        'timestamp': timestamp,
        'quality': quality,
        'latitude': latitude,
        'longitude': longitude,
        'assetId': assetId,
        'anomaly': anomaly,
        if (metadata['severity'] != null) 'severity': metadata['severity'],
        if (metadata['confidence'] != null) 'confidence': metadata['confidence'],
        if (metadata['manufacturer'] != null)
          'manufacturer': metadata['manufacturer'],
        'mode': mode,
      };
}

/// Transport abstraction — the app never cares HOW the data arrived.
abstract class DeviceProvider {
  String get providerId;
  DataSourceMode get mode;
  Future<List<IoTDevice>> discoverDevices();
  Stream<SensorReading> readings(List<IoTDevice> devices);
}

/// Explicitly-marked simulation provider: identical pipeline as real data,
/// deterministic, and every event is labelled DataSourceMode.simulated.
class SimulationDeviceProvider implements DeviceProvider {
  SimulationDeviceProvider({this.readingsPerDevice = 3});

  final int readingsPerDevice;

  @override
  String get providerId => 'simulation';

  @override
  DataSourceMode get mode => DataSourceMode.simulated;

  @override
  Future<List<IoTDevice>> discoverDevices() async => [
        IoTDevice(
          deviceId: 'SIM-VIB-001',
          deviceType: 'vibration-sensor',
          manufacturer: 'Simulated Instruments',
          model: 'VIB-SIM',
          capabilities: const DeviceCapabilities(
            supportsSensorData: true,
            supportedSensors: ['vibration'],
            supportsOfflineBuffer: true,
          ),
          connectionState: ConnectionState.connected,
          healthStatus: HealthStatus.healthy,
          lastSeen: DateTime.now(),
          metadata: {'assetId': 'ASSET-BRIDGE-7'},
        ),
        IoTDevice(
          deviceId: 'SIM-ENV-002',
          deviceType: 'environment-sensor',
          manufacturer: 'Simulated Instruments',
          model: 'ENV-SIM',
          capabilities: const DeviceCapabilities(
            supportsSensorData: true,
            supportedSensors: ['water-level'],
            supportsRealtimeStream: true,
          ),
          connectionState: ConnectionState.connected,
          healthStatus: HealthStatus.healthy,
          lastSeen: DateTime.now(),
          metadata: {'assetId': 'ASSET-DRAIN-3'},
        ),
      ];

  @override
  Stream<SensorReading> readings(List<IoTDevice> devices) async* {
    final now = DateTime.now();
    for (final device in devices) {
      for (var i = 0; i < readingsPerDevice; i++) {
        final isLast = i == readingsPerDevice - 1;
        // The final reading per device is an anomalous spike — it exercises
        // the anomaly path through the exact same pipeline as real data.
        yield SensorReading(
          readingId: 'SIMR-${device.deviceId}-$i',
          deviceId: device.deviceId,
          sensorType: device.capabilities.supportedSensors.first,
          value: isLast ? 99.5 : 10.0 + i,
          unit: device.deviceId.contains('VIB') ? 'mm/s' : 'cm',
          timestamp: now.subtract(Duration(minutes: 5 - i)),
          quality: 'good',
          assetId: device.metadata['assetId'] as String?,
          metadata: {
            'severity': isLast ? 'HIGH' : 'NORMAL',
            'confidence': isLast ? 0.9 : 0.6,
            'manufacturer': device.manufacturer,
          },
        );
      }
    }
  }
}

/// Real transport slots — same contract, ready for hardware without any core
/// change. Implementations stream decoded readings from their protocol.
abstract class HttpPollingProvider implements DeviceProvider {}

abstract class MqttProvider implements DeviceProvider {}

abstract class BluetoothProvider implements DeviceProvider {}

abstract class GatewayProvider implements DeviceProvider {}

