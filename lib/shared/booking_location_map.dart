import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'top_toast.dart';

/// Same keys the customer's location picker uses (passed with
/// --dart-define-from-file=env.json). Without MAPTILER_KEY it falls back to
/// OpenStreetMap tiles.
const String _maptilerKey = String.fromEnvironment('MAPTILER_KEY');

String get _tileUrl => _maptilerKey.isNotEmpty
    ? 'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=$_maptilerKey'
    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

const Color _kMaroon = Color(0xFF6E1B1E);

/// Read-only map of the location the customer pinned when booking.
/// Used in the Staff and Admin booking details. Tap the map to open a
/// full-screen version you can pan and zoom. The pin can't be moved.
class BookingLocationMap extends StatelessWidget {
  const BookingLocationMap({
    super.key,
    required this.lat,
    required this.lng,
    this.address = '',
    this.height = 170,
  });

  final double lat;
  final double lng;
  final String address;
  final double height;

  LatLng get _point => LatLng(lat, lng);

  String get _mapsLink => 'https://www.google.com/maps?q=$lat,$lng';

  void _copyLink(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _mapsLink));
    TopToast.show(context, 'Map link copied');
  }

  void _openFull(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _FullMapPage(point: _point, address: address, link: _mapsLink)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: height,
              child: Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: _point,
                      initialZoom: 15,
                      interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                      onTap: (_, __) => _openFull(context),
                    ),
                    children: [
                      TileLayer(urlTemplate: _tileUrl, userAgentPackageName: 'com.example.memoriae_photobooth'),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _point,
                            width: 40,
                            height: 40,
                            alignment: Alignment.topCenter,
                            child: const Icon(Icons.location_on, size: 40, color: Color(0xFFD32F2F)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Tap to enlarge', style: TextStyle(color: Colors.white, fontSize: 10.5)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _copyLink(context),
            icon: const Icon(Icons.link_rounded, size: 16),
            label: const Text('Copy map link', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kMaroon,
              side: const BorderSide(color: _kMaroon),
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FullMapPage extends StatelessWidget {
  const _FullMapPage({required this.point, required this.address, required this.link});

  final LatLng point;
  final String address;
  final String link;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Event location'),
        backgroundColor: _kMaroon,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Copy map link',
            icon: const Icon(Icons.link_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              TopToast.show(context, 'Map link copied');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: point,
                initialZoom: 16,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              ),
              children: [
                TileLayer(urlTemplate: _tileUrl, userAgentPackageName: 'com.example.memoriae_photobooth'),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
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
                      _maptilerKey.isNotEmpty ? '© MapTiler © OpenStreetMap contributors' : '© OpenStreetMap contributors',
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (address.trim().isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.place_rounded, color: _kMaroon, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(address.trim(), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
