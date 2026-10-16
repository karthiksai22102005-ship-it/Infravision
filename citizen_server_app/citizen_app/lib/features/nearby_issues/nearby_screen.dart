import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/network/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});
  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  final _map = MapController();
  List<NearbyIssue> _issues = [];
  LatLng? _me;
  String? _problem;
  bool _loading = true;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final permissionMessage = state.s('permLocation');
    setState(() {
      _loading = true;
      _problem = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw 'GPS is turned off.';
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied ||
          p == LocationPermission.deniedForever) {
        throw permissionMessage;
      }
      final pos = await Geolocator.getCurrentPosition();
      _me = LatLng(pos.latitude, pos.longitude);
      _issues = await state.api.nearby(pos.latitude, pos.longitude);
      _map.move(_me!, 14);
    } on ApiException catch (e) {
      _problem = e.offline ? state.s('offline') : e.message;
    } catch (e) {
      _problem = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _filter == 'all'
        ? _issues
        : _issues.where((i) => i.categoryCode == _filter).toList();
    return Scaffold(
      appBar: AppBar(title: Text(context.watch<AppState>().s('nearby'))),
      bottomNavigationBar: const AppBottomNav(1),
      body: Column(children: [
        SizedBox(
            height: 52,
            child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final f in const [
                    'all',
                    'pothole',
                    'streetlight',
                    'drainage'
                  ])
                    Padding(
                        padding:
                            const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                        child: ChoiceChip(
                            label: Text(f == 'all'
                                ? 'All'
                                : f[0].toUpperCase() + f.substring(1)),
                            selected: _filter == f,
                            onSelected: (_) => setState(() => _filter = f))),
                ])),
        if (_problem != null)
          MaterialBanner(content: Text(_problem!), actions: [
            TextButton(onPressed: _load, child: const Text('Retry'))
          ]),
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                  initialCenter: _me ?? const LatLng(20.5937, 78.9629),
                  initialZoom: _me == null ? 4 : 14),
              children: [
                TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.infravision.citizen'),
                MarkerLayer(markers: [
                  for (final i in shown)
                    Marker(
                        point: LatLng(i.latitude, i.longitude),
                        width: 36,
                        height: 36,
                        child: GestureDetector(
                            onTap: () => showModalBottomSheet(
                                context: context,
                                builder: (_) => ListTile(
                                    title: Text(i.categoryCode),
                                    trailing: StatusBadge(i.status))),
                            child: Icon(Icons.location_on,
                                color: statusColor(i.status), size: 36))),
                  if (_me != null)
                    Marker(
                        point: _me!,
                        child: const Icon(Icons.my_location,
                            color: AppColors.blue)),
                ]),
                const RichAttributionWidget(attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors')
                ]),
              ],
            ),
            if (_loading)
              const Positioned.fill(
                  child: ColoredBox(
                      color: Colors.black12,
                      child: Center(child: CircularProgressIndicator()))),
          ]),
        ),
      ]),
    );
  }
}
