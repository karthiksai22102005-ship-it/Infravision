import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';

/// Foreground location only (no background tracking). Map tiles: OpenStreetMap,
/// attribution is shown below; see docs/NETWORK_SETUP.md for tile usage policy.
class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});
  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  final _map = MapController();
  final _lat = TextEditingController(),
      _lng = TextEditingController(),
      _addr = TextEditingController(),
      _desc = TextEditingController();
  bool _busy = false;
  bool _improvingDescription = false;
  String? _problem; // permission / GPS problem text
  bool _permanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    final d = context.read<AppState>().draft;
    if (d.hasLocation) _sync(d.lat!, d.lng!);
    _addr.text = d.address ?? '';
    _desc.text = d.description;
  }

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    _addr.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _sync(double lat, double lng) {
    _lat.text = lat.toStringAsFixed(5);
    _lng.text = lng.toStringAsFixed(5);
  }

  Future<void> _useCurrent() async {
    final s = context.read<AppState>().s;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _problem =
            'GPS is turned off. Enable location services, or enter coordinates manually.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() {
          _permanentlyDenied = perm == LocationPermission.deniedForever;
          _problem = s('permLocation');
        });
        return;
      }
      final p = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20));
      if (!mounted) return;
      await context.read<AppState>().updateDraft((d) {
        d.lat = p.latitude;
        d.lng = p.longitude;
        d.accuracy = p.accuracy;
      });
      _sync(p.latitude, p.longitude);
      _map.move(LatLng(p.latitude, p.longitude), 17);
      if (p.accuracy > AppConfig.goodAccuracyMeters) {
        setState(() => _problem =
            'Low GPS accuracy (±${p.accuracy.round()} m). Move the pin to the exact spot.');
      }
    } catch (_) {
      setState(() => _problem =
          'Could not get your location. Enter coordinates manually or move the pin.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPoint(double lat, double lng) async {
    await context.read<AppState>().updateDraft((d) {
      d.lat = lat;
      d.lng = lng;
      d.accuracy = null;
    });
    _sync(lat, lng);
  }

  Future<void> _improveDescription(AppState state) async {
    final original = _desc.text.trim();
    if (original.length < 10) {
      showSnack(context, state.s('descriptionTooShortForAi'));
      return;
    }
    setState(() => _improvingDescription = true);
    try {
      final category = state.draft.categoryCode ?? 'not specified';
      final suggestion = (await state.api.askAI(
        'Rewrite the citizen\'s civic issue description as one clear, concise '
        'report in language code ${state.lang}. Category: $category. '
        'Use only facts stated in the citizen\'s text. Do not infer severity, '
        'cause, measurements, safety risk, or location. Return only the rewritten '
        'description, with no heading or quotation marks. Citizen\'s text: $original',
        state.lang,
      )).trim();
      if (!mounted) return;
      if (_desc.text.trim() != original) {
        showSnack(context, state.s('descriptionChangedDuringAi'));
        return;
      }
      if (suggestion.isEmpty || suggestion.length > 500) {
        throw StateError('The AI returned an empty or overly long suggestion.');
      }
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(state.s('aiSuggestionTitle')),
          content: SingleChildScrollView(child: Text(suggestion)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(state.s('keepCurrent')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(state.s('useSuggestion')),
            ),
          ],
        ),
      );
      if (accepted == true && mounted) {
        _desc.text = suggestion;
        await state.updateDraft((d) => d.description = suggestion);
      }
    } catch (error) {
      debugPrint('AI description suggestion failed: $error');
      if (mounted) showSnack(context, state.s('aiSuggestionFailed'));
    } finally {
      if (mounted) setState(() => _improvingDescription = false);
    }
  }

  void _next() {
    if (_desc.text.trim().length < 10) {
      showSnack(context, 'Describe the issue in at least 10 characters');
      return;
    }
    final lat = double.tryParse(_lat.text), lng = double.tryParse(_lng.text);
    if (lat == null ||
        lng == null ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180) {
      showSnack(context, 'Enter valid coordinates or tap the map');
      return;
    }
    final st = context.read<AppState>();
    st.updateDraft((d) {
      d.description = _desc.text.trim();
      d.lat = lat;
      d.lng = lng;
      d.address = _addr.text.trim().isEmpty ? null : _addr.text.trim();
    });
    Navigator.pushNamed(context, '/camera');
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.s;
    final d = st.draft;
    final center = d.hasLocation
        ? LatLng(d.lat!, d.lng!)
        : const LatLng(20.5937, 78.9629); // India-wide default view
    return Scaffold(
      appBar: StepHeader(2, s('setLocation')),
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: center,
                initialZoom: d.hasLocation ? 17 : 4,
                onTap: (_, p) => _setPoint(p.latitude, p.longitude),
              ),
              children: [
                TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.infravision.citizen'),
                if (d.hasLocation)
                  MarkerLayer(markers: [
                    Marker(
                        point: LatLng(d.lat!, d.lng!),
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.location_on,
                            color: AppColors.red, size: 40))
                  ]),
                const RichAttributionWidget(attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors')
                ]),
              ],
            ),
            if (_busy)
              const Positioned.fill(
                  child: ColoredBox(
                      color: Colors.black26,
                      child: Center(child: CircularProgressIndicator()))),
          ]),
        ),
        Container(
          color: Theme.of(context).colorScheme.surface,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _desc,
              maxLines: 2,
              maxLength: 500,
              decoration: InputDecoration(
                  labelText: s('description'),
                  hintText: s('describeHint'),
                  isDense: true),
              onChanged: (v) => context
                  .read<AppState>()
                  .updateDraft((d) => d.description = v),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _improvingDescription
                    ? null
                    : () => _improveDescription(st),
                icon: _improvingDescription
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(_improvingDescription
                    ? s('aiSuggestionLoading')
                    : s('improveWithAi')),
              ),
            ),
            const SizedBox(height: 4),
            if (_problem != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  const Icon(Icons.info_outline,
                      color: AppColors.amber, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_problem!,
                          style: const TextStyle(fontSize: 12))),
                  if (_permanentlyDenied)
                    TextButton(
                        onPressed: Geolocator.openAppSettings,
                        child: Text(s('openSettings'))),
                ]),
              ),
            OutlinedButton.icon(
                onPressed: _busy ? null : _useCurrent,
                icon: const Icon(Icons.my_location),
                label: Text(s('useCurrent'))),
            const SizedBox(height: 8),
            TextField(
                controller: _addr,
                decoration: const InputDecoration(
                    labelText: 'Address / landmark (optional)', isDense: true)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _lat,
                      decoration: const InputDecoration(
                          labelText: 'Latitude', isDense: true),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: _lng,
                      decoration: const InputDecoration(
                          labelText: 'Longitude', isDense: true),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true))),
            ]),
            const SizedBox(height: 10),
            FilledButton.icon(
                onPressed: _next,
                icon: const Icon(Icons.arrow_forward),
                label: Text(s('next'))),
          ]),
        ),
      ]),
    );
  }
}
