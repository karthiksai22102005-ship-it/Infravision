import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../config/app_theme.dart';
import '../../models/complaint_item.dart';
import '../../repositories/app_storage.dart';

/// Geo-cluster grouping nearby defect markers on the real-world map.
class _GeoCluster {
  LatLng center;
  final List<ComplaintItem> items;
  _GeoCluster({required this.center, required this.items});
  bool get isSingle => items.length == 1;
  ComplaintItem get primary => items.first;

  ComplaintSeverity get maxSeverity {
    if (items.any((e) => e.severity == ComplaintSeverity.critical)) return ComplaintSeverity.critical;
    if (items.any((e) => e.severity == ComplaintSeverity.high)) return ComplaintSeverity.high;
    if (items.any((e) => e.severity == ComplaintSeverity.moderate)) return ComplaintSeverity.moderate;
    return ComplaintSeverity.low;
  }
}

/// Full Real-World GPS Map Workspace — OpenStreetMap tiles, device GPS, global defect tracking.
class CampusMapWorkspace extends StatefulWidget {
  const CampusMapWorkspace({super.key});

  @override
  State<CampusMapWorkspace> createState() => _CampusMapWorkspaceState();
}

class _CampusMapWorkspaceState extends State<CampusMapWorkspace> with TickerProviderStateMixin {
  // ─── Map Controller ───
  final MapController _mapController = MapController();

  // ─── GPS State ───
  LatLng _deviceLocation = const LatLng(17.3850, 78.4867); // Default: Hyderabad
  bool _gpsLocked = false;
  bool _gpsLoading = true;
  String _gpsStatusText = 'Acquiring GPS fix…';
  double _gpsAccuracy = 0;
  StreamSubscription<Position>? _positionStream;

  // ─── UI State ───
  ComplaintItem? _selectedComplaint;
  String _selectedCategoryFilter = 'All Categories';
  bool _isPinDropMode = false;
  String _searchQuery = '';
  double _currentZoom = 16.0;
  bool _followDevice = true;

  // ─── Map Style ───
  int _tileStyleIndex = 0;
  static const List<_TileStyle> _tileStyles = [
    _TileStyle('Dark', 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png', Icons.dark_mode_rounded),
    _TileStyle('Street', 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', Icons.map_rounded),
    _TileStyle('Satellite', 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', Icons.satellite_alt_rounded),
    _TileStyle('Political', 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png', Icons.public_rounded),
    _TileStyle('Topo', 'https://tile.opentopomap.org/{z}/{x}/{y}.png', Icons.terrain_rounded),
  ];

  final List<String> _categories = [
    'All Categories',
    'Road & Pavement Hazards',
    'Concrete & Structural',
    'Drainage & Public Health',
    'Road Infrastructure',
    'Public Works & Utilities',
  ];

  // ─── Pulse animation for GPS marker ───
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _initGps();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LIVE GPS ENGINE — Geolocator
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _initGps() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _gpsLoading = false;
          _gpsStatusText = 'Location services disabled';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _gpsLoading = false;
            _gpsStatusText = 'GPS permission denied';
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _gpsLoading = false;
          _gpsStatusText = 'GPS permanently denied — enable in settings';
        });
        return;
      }

      // Get initial position
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _applyPosition(pos);

      // Start continuous stream
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3, // Update every 3 meters movement
        ),
      ).listen(_applyPosition);
    } catch (e) {
      debugPrint('GPS init error: $e');
      setState(() {
        _gpsLoading = false;
        _gpsStatusText = 'GPS error: $e';
      });
    }
  }

  void _applyPosition(Position pos) {
    if (!mounted) return;
    setState(() {
      _deviceLocation = LatLng(pos.latitude, pos.longitude);
      _gpsLocked = true;
      _gpsLoading = false;
      _gpsAccuracy = pos.accuracy;
      _gpsStatusText =
          'GPS LOCK: ${pos.latitude.toStringAsFixed(6)}°, ${pos.longitude.toStringAsFixed(6)}° | '
          'ALT: ${pos.altitude.toStringAsFixed(0)}m | ACC: ±${pos.accuracy.toStringAsFixed(1)}m';
    });
    if (_followDevice) {
      _mapController.move(_deviceLocation, _currentZoom);
    }
  }

  void _centerOnDevice() {
    setState(() => _followDevice = true);
    _mapController.move(_deviceLocation, math.max(_currentZoom, 17.0));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  COMPLAINT → LAT/LNG MAPPING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Parse a complaint's GPS string into a real LatLng, or generate a plausible
  /// offset near the device's current location.
  LatLng _complaintToLatLng(ComplaintItem c, int index) {
    final gps = c.gpsCoordinates;
    if (gps != null && gps.isNotEmpty) {
      final parsed = _parseGpsString(gps);
      if (parsed != null) return parsed;
    }
    // Scatter around device position with deterministic jitter from complaint ID
    final hash = c.id.hashCode.abs();
    final dLat = ((hash % 200) - 100) * 0.00005; // ±~5m
    final dLng = (((hash ~/ 200) % 200) - 100) * 0.00005;
    return LatLng(_deviceLocation.latitude + dLat, _deviceLocation.longitude + dLng);
  }

  LatLng? _parseGpsString(String gps) {
    try {
      // Handle "17.3850° N, 78.4867° E" format
      final cleaned = gps.replaceAll('°', '').replaceAll('N', '').replaceAll('S', '').replaceAll('E', '').replaceAll('W', '');
      final parts = cleaned.split(',').map((s) => s.trim()).toList();
      if (parts.length >= 2) {
        final lat = double.tryParse(parts[0]);
        final lng = double.tryParse(parts[1]);
        if (lat != null && lng != null) {
          final latSign = gps.contains('S') ? -1.0 : 1.0;
          final lngSign = gps.contains('W') ? -1.0 : 1.0;
          return LatLng(lat * latSign, lng * lngSign);
        }
      }
    } catch (_) {}
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  GEO-CLUSTERING — Groups nearby defects at current zoom level
  // ═══════════════════════════════════════════════════════════════════════════

  List<_GeoCluster> _computeGeoClusters(List<ComplaintItem> items) {
    const double clusterRadiusDeg = 0.0004; // ~44m at equator
    final clusters = <_GeoCluster>[];

    for (int i = 0; i < items.length; i++) {
      final pos = _complaintToLatLng(items[i], i);
      _GeoCluster? bestCluster;
      double minDist = double.infinity;

      for (final cl in clusters) {
        final dist = _haversineDistance(cl.center, pos);
        if (dist < clusterRadiusDeg && dist < minDist) {
          minDist = dist;
          bestCluster = cl;
        }
      }

      if (bestCluster != null) {
        bestCluster.items.add(items[i]);
        // Recalculate centroid
        double avgLat = 0, avgLng = 0;
        for (final item in bestCluster.items) {
          final p = _complaintToLatLng(item, items.indexOf(item));
          avgLat += p.latitude;
          avgLng += p.longitude;
        }
        bestCluster.center = LatLng(avgLat / bestCluster.items.length, avgLng / bestCluster.items.length);
      } else {
        clusters.add(_GeoCluster(center: pos, items: [items[i]]));
      }
    }
    return clusters;
  }

  double _haversineDistance(LatLng a, LatLng b) {
    return math.sqrt(
      math.pow(a.latitude - b.latitude, 2) + math.pow(a.longitude - b.longitude, 2),
    );
  }

  double _realDistanceMeters(LatLng a, LatLng b) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Meter, a, b);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  PIN DROP — Tap on map to create a new defect at exact GPS coordinates
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _handleMapTap(TapPosition tapPosition, LatLng latlng) async {
    if (!_isPinDropMode) return;

    setState(() => _followDevice = false);

    final computedGps = '${latlng.latitude.toStringAsFixed(6)}° N, ${latlng.longitude.toStringAsFixed(6)}° E';

    final titleCtrl = TextEditingController(text: 'Road Pothole Cavity (Field Survey)');
    final zoneCtrl = TextEditingController(text: 'GPS: ${latlng.latitude.toStringAsFixed(4)}, ${latlng.longitude.toStringAsFixed(4)}');
    final notesCtrl = TextEditingController(text: 'Identified via live GPS map tap.');
    String category = 'Road & Pavement Hazards';
    ComplaintSeverity severity = ComplaintSeverity.high;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF131D31),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF1E293B))),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.add_location_alt_rounded, color: AppTheme.cyan, size: 20),
              ),
              const SizedBox(width: 10),
              const Text('Drop Defect Pin', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // GPS Coordinate Lock
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.gps_fixed_rounded, color: AppTheme.cyan, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('📍 $computedGps', style: const TextStyle(color: AppTheme.cyan, fontSize: 11.5, fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Defect Title', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: titleCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Zone / Landmark', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: zoneCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Category', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    dropdownColor: const Color(0xFF0F172A),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                    ),
                    items: _categories.where((c) => c != 'All Categories').map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (val) {
                      if (val != null) setDlgState(() => category = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('Severity Level', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Row(
                    children: ComplaintSeverity.values.map((s) {
                      final isSelected = severity == s;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: ChoiceChip(
                            label: Text(s.name.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: isSelected ? Colors.white : const Color(0xFF94A3B8))),
                            selected: isSelected,
                            selectedColor: AppTheme.primary,
                            backgroundColor: const Color(0xFF0F172A),
                            onSelected: (_) => setDlgState(() => severity = s),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Confirm Pin'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final dept = category.contains('Road')
          ? 'Public Works Department'
          : category.contains('Drainage')
              ? 'Drainage Division'
              : 'Civil Maintenance';
      final score = switch (severity) {
        ComplaintSeverity.critical => 0.94,
        ComplaintSeverity.high => 0.78,
        ComplaintSeverity.moderate => 0.55,
        ComplaintSeverity.low => 0.28,
      };

      await AppStorage.instance.logComplaint(
        title: titleCtrl.text.trim(),
        category: category,
        zone: zoneCtrl.text.trim(),
        severity: severity,
        severityScore: score,
        inspectorNotes: notesCtrl.text.trim(),
        gpsCoordinates: computedGps,
        department: dept,
      );

      setState(() => _isPinDropMode = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.success,
            content: Text('📍 Defect pin dropped at $computedGps!'),
          ),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  CLUSTER BOTTOM SHEET
  // ═══════════════════════════════════════════════════════════════════════════

  void _showClusterSheet(BuildContext context, _GeoCluster cluster) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131D31),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Color(0xFF1E293B)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.hub_rounded, color: AppTheme.cyan, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Defect Cluster • ${cluster.items.length} Hazards',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: cluster.items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (c, idx) {
                    final item = cluster.items[idx];
                    final color = _severityColor(item.severity);
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1E293B)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: color.withValues(alpha: 0.4)),
                            ),
                            child: Text(item.id, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text('📍 ${item.zone} • ${(item.severityScore * 100).toInt()}%', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                              ],
                            ),
                          ),
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              setState(() => _selectedComplaint = item);
                            },
                            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                            child: const Text('Inspect', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _severityColor(ComplaintSeverity s) => switch (s) {
        ComplaintSeverity.critical => AppTheme.error,
        ComplaintSeverity.high => AppTheme.warning,
        ComplaintSeverity.moderate => const Color(0xFF06B6D4),
        ComplaintSeverity.low => AppTheme.success,
      };

  // ═══════════════════════════════════════════════════════════════════════════
  //  BUILD — Full Map UI
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return ListenableBuilder(
      listenable: AppStorage.instance,
      builder: (context, _) {
        final allComplaints = AppStorage.instance.complaintsList;

        final complaints = allComplaints.where((c) {
          if (_selectedCategoryFilter != 'All Categories' && c.category != _selectedCategoryFilter) return false;
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            return c.title.toLowerCase().contains(q) || c.zone.toLowerCase().contains(q) || c.id.toLowerCase().contains(q);
          }
          return true;
        }).toList();

        final clusters = _computeGeoClusters(complaints);

        return Container(
          color: const Color(0xFF0B1120),
          child: Column(
            children: [
              // ── Top Toolbar ──
              _buildTopToolbar(context, isMobile),

              // ── Map ──
              Expanded(
                child: Stack(
                  children: [
                    // ── FlutterMap with real OSM tiles ──
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _deviceLocation,
                        initialZoom: _currentZoom,
                        minZoom: 3,
                        maxZoom: 19,
                        onTap: _handleMapTap,
                        onPositionChanged: (pos, hasGesture) {
                          if (hasGesture) _followDevice = false;
                          _currentZoom = pos.zoom;
                        },
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all,
                        ),
                      ),
                      children: [
                        // Tile Layer (real map)
                        TileLayer(
                          urlTemplate: _tileStyles[_tileStyleIndex].url,
                          userAgentPackageName: 'com.infravision.app',
                          maxZoom: 19,
                        ),

                        // GPS Accuracy Circle
                        if (_gpsLocked)
                          CircleLayer(
                            circles: [
                              CircleMarker(
                                point: _deviceLocation,
                                radius: _gpsAccuracy > 0 ? _gpsAccuracy : 15,
                                useRadiusInMeter: true,
                                color: AppTheme.cyan.withValues(alpha: 0.08),
                                borderColor: AppTheme.cyan.withValues(alpha: 0.3),
                                borderStrokeWidth: 1.5,
                              ),
                            ],
                          ),

                        // Route Line from device to selected defect
                        if (_selectedComplaint != null)
                          _buildRouteLine(complaints),

                        // Defect Markers (Clusters + Singles)
                        MarkerLayer(
                          markers: [
                            // Cluster / Single markers
                            for (final cluster in clusters)
                              _buildClusterMapMarker(cluster),

                            // Device GPS Marker
                            Marker(
                              point: _deviceLocation,
                              width: 50,
                              height: 50,
                              child: _buildDeviceMarkerWidget(),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // Pin Mode Banner
                    if (_isPinDropMode)
                      Positioned(
                        top: 16,
                        left: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: AppTheme.shadowMd,
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.touch_app_rounded, color: Colors.black, size: 18),
                              SizedBox(width: 8),
                              Text('TAP ANYWHERE ON THE MAP TO DROP DEFECT PIN', style: TextStyle(color: Colors.black, fontSize: 11.5, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ),

                    // Map Controls (Right side)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: _buildMapControls(),
                    ),

                    // Floating Layer Switcher Panel (Left side)
                    Positioned(
                      top: 16,
                      left: _isPinDropMode ? 20 : 16,
                      child: _isPinDropMode ? const SizedBox.shrink() : _buildLayerSwitcher(),
                    ),

                    // Floating Defect Detail Pop-up
                    if (_selectedComplaint != null)
                      Positioned(
                        bottom: 16,
                        left: 20,
                        right: 20,
                        child: _buildFloatingDetailCard(context, _selectedComplaint!, complaints),
                      ),

                    // Bottom GPS Telemetry
                    Positioned(
                      bottom: _selectedComplaint != null ? 140 : 12,
                      left: 20,
                      child: _buildGpsTelemetryBadge(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  WIDGET BUILDERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Device GPS pulsing marker widget
  Widget _buildDeviceMarkerWidget() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final pulse = _pulseController.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            // Pulse ring
            Container(
              width: 44 + (pulse * 14),
              height: 44 + (pulse * 14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.cyan.withValues(alpha: (1.0 - pulse) * 0.5),
                  width: 2,
                ),
              ),
            ),
            // Core dot
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.cyan.withValues(alpha: 0.25),
                border: Border.all(color: AppTheme.cyan, width: 2.5),
                boxShadow: [
                  BoxShadow(color: AppTheme.cyan.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2),
                ],
              ),
              child: const Center(
                child: Icon(Icons.person_pin_circle_rounded, color: Colors.white, size: 16),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Build a flutter_map Marker for a geo-cluster
  Marker _buildClusterMapMarker(_GeoCluster cluster) {
    final color = _severityColor(cluster.maxSeverity);
    final isSelected = cluster.items.any((c) => c.id == _selectedComplaint?.id);

    if (cluster.isSingle) {
      final complaint = cluster.primary;
      return Marker(
        point: cluster.center,
        width: 60,
        height: 48,
        child: GestureDetector(
          onTap: () => setState(() => _selectedComplaint = complaint),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isSelected ? AppTheme.primary : Colors.black45, width: 1.5),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: isSelected ? 12 : 6)],
                ),
                child: Text(
                  complaint.id.split('-').last,
                  style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontSize: 9, fontWeight: FontWeight.w800, fontFamily: 'monospace'),
                ),
              ),
              Icon(Icons.location_on_rounded, color: color, size: isSelected ? 24 : 20),
            ],
          ),
        ),
      );
    }

    // Multi-defect cluster badge
    return Marker(
      point: cluster.center,
      width: 64,
      height: 36,
      child: GestureDetector(
        onTap: () => _showClusterSheet(context, cluster),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color, width: 2),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 10, spreadRadius: 1)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text('${cluster.items.length}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, fontFamily: 'monospace')),
            ],
          ),
        ),
      ),
    );
  }

  /// Route polyline from device to selected defect
  Widget _buildRouteLine(List<ComplaintItem> complaints) {
    if (_selectedComplaint == null) return const SizedBox.shrink();
    final idx = complaints.indexWhere((c) => c.id == _selectedComplaint!.id);
    if (idx == -1) return const SizedBox.shrink();
    final destLatLng = _complaintToLatLng(_selectedComplaint!, idx);

    return PolylineLayer(
      polylines: [
        Polyline(
          points: [_deviceLocation, destLatLng],
          color: AppTheme.cyan.withValues(alpha: 0.8),
          strokeWidth: 3.5,
          pattern: const StrokePattern.dotted(),
        ),
      ],
    );
  }

  // ── Top Toolbar ──
  Widget _buildTopToolbar(BuildContext context, bool isMobile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.public_rounded, color: AppTheme.cyan, size: 18),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Global GPS Defect Map', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
              Text(
                _gpsLocked ? 'Live GPS • ${_tileStyles[_tileStyleIndex].name} Tiles' : _gpsStatusText,
                style: TextStyle(fontSize: 10, color: _gpsLocked ? AppTheme.success : const Color(0xFF94A3B8)),
              ),
            ],
          ),
          const SizedBox(width: 18),
          Container(width: 1, height: 22, color: const Color(0xFF1E293B)),
          const SizedBox(width: 14),

          // Search
          if (!isMobile) ...[
            SizedBox(
              width: 140,
              height: 32,
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                style: const TextStyle(color: Colors.white, fontSize: 11),
                decoration: InputDecoration(
                  hintText: 'Search defect / zone…',
                  hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 16),
                  contentPadding: EdgeInsets.zero,
                  filled: true,
                  fillColor: const Color(0xFF131D31),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1E293B))),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF131D31),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: DropdownButton<String>(
                value: _selectedCategoryFilter,
                underline: const SizedBox.shrink(),
                dropdownColor: const Color(0xFF131D31),
                isDense: true,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                icon: const Icon(Icons.filter_list_rounded, color: AppTheme.cyan, size: 15),
                items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedCategoryFilter = val);
                },
              ),
            ),
          ],
          const SizedBox(width: 10),

          // Pin Drop
          FilledButton.icon(
            onPressed: () => setState(() => _isPinDropMode = !_isPinDropMode),
            style: FilledButton.styleFrom(
              backgroundColor: _isPinDropMode ? AppTheme.warning : const Color(0xFF131D31),
              foregroundColor: _isPinDropMode ? Colors.black : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: _isPinDropMode ? AppTheme.warning : const Color(0xFF1E293B)),
              ),
            ),
            icon: Icon(Icons.add_location_alt_rounded, size: 14, color: _isPinDropMode ? Colors.black : AppTheme.cyan),
            label: Text(_isPinDropMode ? 'Cancel Pinning' : '+ Drop Pin', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ),

          const Spacer(),
        ],
      ),
    );
  }

  // ── Map Controls (right panel) ──
  Widget _buildMapControls() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF131D31).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E293B)),
        boxShadow: AppTheme.shadowMd,
      ),
      child: Column(
        children: [
          // Center on device GPS
          IconButton(
            icon: Icon(Icons.my_location_rounded, color: _followDevice ? AppTheme.cyan : Colors.white70, size: 18),
            tooltip: 'Center on Device GPS',
            onPressed: _centerOnDevice,
          ),
          const Divider(height: 1, color: Color(0xFF1E293B)),
          IconButton(
            icon: const Icon(Icons.add_rounded, color: Colors.white70, size: 18),
            tooltip: 'Zoom In',
            onPressed: () {
              _currentZoom = math.min(_currentZoom + 1, 19);
              _mapController.move(_mapController.camera.center, _currentZoom);
            },
          ),
          IconButton(
            icon: const Icon(Icons.remove_rounded, color: Colors.white70, size: 18),
            tooltip: 'Zoom Out',
            onPressed: () {
              _currentZoom = math.max(_currentZoom - 1, 3);
              _mapController.move(_mapController.camera.center, _currentZoom);
            },
          ),
          const Divider(height: 1, color: Color(0xFF1E293B)),
          // GPS status indicator
          Tooltip(
            message: _gpsStatusText,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _gpsLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.cyan))
                  : Icon(
                      _gpsLocked ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
                      color: _gpsLocked ? AppTheme.success : AppTheme.warning,
                      size: 16,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Floating detail card for selected defect ──
  Widget _buildFloatingDetailCard(BuildContext context, ComplaintItem item, List<ComplaintItem> complaints) {
    final idx = complaints.indexWhere((c) => c.id == item.id);
    final defectLatLng = idx >= 0 ? _complaintToLatLng(item, idx) : _deviceLocation;
    final distM = _realDistanceMeters(_deviceLocation, defectLatLng);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131D31).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.4), width: 1.5),
        boxShadow: AppTheme.shadowLg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    item.category.contains('Road') ? Icons.warning_amber_rounded : Icons.broken_image_rounded,
                    color: AppTheme.warning,
                    size: 28,
                  ),
                ),
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                    decoration: BoxDecoration(color: AppTheme.error, borderRadius: BorderRadius.circular(4)),
                    child: Text('${(item.severityScore * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(6)),
                      child: Text(item.id, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => setState(() => _selectedComplaint = null),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '📍 ${item.zone} • GPS: ${item.gpsCoordinates ?? "—"}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Distance: ${distM < 1000 ? '${distM.toInt()}m' : '${(distM / 1000).toStringAsFixed(1)}km'} '
                  '(${(distM / 80).ceil()} min ETA) • ${item.department}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.cyan),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            children: [
              FilledButton.icon(
                onPressed: () {
                  _mapController.move(defectLatLng, 18);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF131D31),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  side: const BorderSide(color: Color(0xFF334155)),
                ),
                icon: const Icon(Icons.center_focus_strong_rounded, size: 14),
                label: const Text('Fly To', style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(height: 6),
              FilledButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(backgroundColor: AppTheme.success, content: Text('🚧 Dispatched crew to ${item.zone}!')),
                  );
                },
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                icon: const Icon(Icons.send_rounded, size: 14),
                label: const Text('Dispatch', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Floating Layer Switcher Panel ──
  Widget _buildLayerSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
        boxShadow: AppTheme.shadowMd,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            child: Text('LAYERS', style: TextStyle(color: Color(0xFF64748B), fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
          ),
          for (int i = 0; i < _tileStyles.length; i++) ...[
            const Divider(height: 1, color: Color(0xFF1E293B)),
            InkWell(
              onTap: () => setState(() => _tileStyleIndex = i),
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: _tileStyleIndex == i ? AppTheme.primary.withValues(alpha: 0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _tileStyles[i].icon,
                      size: 18,
                      color: _tileStyleIndex == i ? AppTheme.cyan : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _tileStyles[i].name,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: _tileStyleIndex == i ? FontWeight.w800 : FontWeight.w500,
                        color: _tileStyleIndex == i ? Colors.white : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── GPS Telemetry Badge ──
  Widget _buildGpsTelemetryBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _gpsLocked ? Icons.satellite_alt_rounded : Icons.gps_not_fixed_rounded,
            color: _gpsLocked ? AppTheme.cyan : AppTheme.warning,
            size: 14,
          ),
          const SizedBox(width: 8),
          Text(
            _gpsStatusText,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}

/// Tile style definition for map layer switching.
class _TileStyle {
  final String name;
  final String url;
  final IconData icon;
  const _TileStyle(this.name, this.url, this.icon);
}
