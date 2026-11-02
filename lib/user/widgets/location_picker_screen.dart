import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import 'circle_back_button.dart';
import 'app_toast.dart';

/// API keys are passed at run/build time so they are not hardcoded:
///   flutter run --dart-define-from-file=env.json
/// Without MAPTILER_KEY the map falls back to OpenStreetMap tiles (testing only).
/// Without LOCATIONIQ_KEY, search and tap-to-address are disabled; the customer
/// can still type the address and tap the map to set the pin.
const String _maptilerKey = String.fromEnvironment('MAPTILER_KEY');
const String _locationIqKey = String.fromEnvironment('LOCATIONIQ_KEY');
const String _userAgent = 'MemoriaePhotobooth/1.0';

const LatLng _kDefaultCenter = LatLng(14.5995, 120.9842); // Manila

/// A location the customer pinned for their event.
class PickedLocation {
  final String address;
  final double lat;
  final double lng;
  const PickedLocation({required this.address, required this.lat, required this.lng});
}

/// Full-screen "pin your event location" picker using flutter_map.
class LocationPickerScreen extends StatefulWidget {
  final PickedLocation? initial;
  const LocationPickerScreen({super.key, this.initial});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _mapController = MapController();
  final _addressController = TextEditingController();
  // Realtime validation: the message shows once the field is touched.
  bool _addressTouched = false;
  late LatLng _pin;
  bool _busy = false;
  int _tapToken = 0; // ignores stale reverse-geocoding responses

  bool get _hasLocationIq => _locationIqKey.isNotEmpty;

  String get _tileUrl => _maptilerKey.isNotEmpty
      ? 'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=$_maptilerKey'
      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _pin = LatLng(widget.initial!.lat, widget.initial!.lng);
      _addressController.text = widget.initial!.address;
    } else {
      _pin = _kDefaultCenter;
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    AppToast.show(context, message);
  }

  void _setPin(LatLng point, {String? address, bool moveCamera = false}) {
    setState(() {
      _pin = point;
      if (address != null) _addressController.text = address;
    });
    if (moveCamera) _mapController.move(point, 16);
  }

  /// Forward geocoding: find a venue or address in the Philippines.
  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    if (!_hasLocationIq) {
      _toast('Search is unavailable. Type the address and tap the map instead.');
      return;
    }
    setState(() => _busy = true);
    try {
      final uri = Uri.https('us1.locationiq.com', '/v1/search', {
        'key': _locationIqKey,
        'q': q,
        'format': 'json',
        'countrycodes': 'ph',
        'limit': '1',
      });
      final res = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      if (res.statusCode != 200 || body is! List || body.isEmpty) {
        _toast('No results found. Try a different name or tap the map.');
        return;
      }
      final hit = body.first as Map<String, dynamic>;
      final point = LatLng(
        double.parse(hit['lat'] as String),
        double.parse(hit['lon'] as String),
      );
      _setPin(point, address: hit['display_name'] as String? ?? q, moveCamera: true);
    } catch (_) {
      _toast('Could not reach the search service. Try again or type the address.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Reverse geocoding: get an address for the tapped point.
  Future<String?> _reverse(LatLng point) async {
    if (!_hasLocationIq) return null;
    try {
      final uri = Uri.https('us1.locationiq.com', '/v1/reverse', {
        'key': _locationIqKey,
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
        'format': 'json',
      });
      final res = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['display_name'] as String?;
    } catch (_) {
      return null;
    }
  }

  void _onMapTap(LatLng point) {
    final token = ++_tapToken;
    _setPin(point);
    _reverse(point).then((address) {
      if (!mounted || token != _tapToken || address == null) return;
      setState(() => _addressController.text = address);
    });
  }

  void _confirm() {
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      setState(() => _addressTouched = true);
      _toast('Please enter an address or venue name.');
      return;
    }
    Navigator.of(context).pop(
      PickedLocation(address: address, lat: _pin.latitude, lng: _pin.longitude),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppPalette.textMuted(context);
    final primary = AppPalette.textPrimary(context);
    final surface = AppPalette.surface(context);

    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        leading: const CircleBackButton.appBar(),
        leadingWidth: CircleBackButton.appBarLeadingWidth,
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        foregroundColor: primary,
        title: const Text('Pin Your Event Location'),
      ),
      body: Column(
        children: [
          // ── Map ─────────────────────────────────────────────
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _pin,
                initialZoom: 14,
                // Rotation is disabled so the map stays north-up and no compass is needed.
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onTap: (_, point) => _onMapTap(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: _tileUrl,
                  userAgentPackageName: 'com.example.memoriae_photobooth',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _pin,
                      width: 44,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: const Icon(Icons.location_on, size: 44, color: Color(0xFFD32F2F)),
                    ),
                  ],
                ),
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      _maptilerKey.isNotEmpty
                          ? '© MapTiler © OpenStreetMap contributors'
                          : '© OpenStreetMap contributors',
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Bottom card ─────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: AppPalette.cardBg(context),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppPalette.divider(context),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Exact Address / Venue',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: primary),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _addressController,
                      style: TextStyle(color: primary, fontSize: 14),
                      textInputAction: TextInputAction.search,
                      onSubmitted: _search,
                      onChanged: (_) => setState(() => _addressTouched = true),
                      decoration: InputDecoration(
                        errorText: (_addressTouched && _addressController.text.trim().isEmpty) ? 'Enter an address or venue name.' : null,
                        hintText: 'e.g. Fairview Terraces Function Hall, QC',
                        hintStyle: TextStyle(color: muted, fontSize: 13),
                        filled: true,
                        fillColor: surface,
                        prefixIcon: Icon(Icons.location_on_outlined, size: 18, color: muted),
                        suffixIcon: _busy
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.search),
                                tooltip: 'Search',
                                onPressed: () => _search(_addressController.text),
                              ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.touch_app_outlined, size: 14, color: muted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Tap the map to drop a pin, or search for a venue.',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ),
                        Text(
                          '${_pin.latitude.toStringAsFixed(5)}, ${_pin.longitude.toStringAsFixed(5)}',
                          style: TextStyle(fontSize: 11, color: muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _confirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.onAccent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text(
                          'Confirm Location',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
