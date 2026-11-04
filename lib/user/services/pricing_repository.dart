import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/booth_package.dart';
import '../models/camera_rental.dart';
import 'local_db.dart';
import 'offline_cache.dart';

/// Read-only view of the same `pricing` collection Admin manages on its
/// Pricing screen — this is what makes an admin-added photo, price, or
/// new package/camera actually show up for customers, instead of the
/// static `kPackages`/`kCameraOptions` fallback lists staying frozen.
///
/// Requires `Firebase.initializeApp()` to have already run and Firestore
/// security rules that allow public read on `pricing/{id}` (see
/// `firestore.rules`).
class PricingRepository {
  PricingRepository._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('pricing');

  /// Every "Booth Package" line, in whatever order Admin created them.
  /// Empty until Admin has added at least one (or hasn't opened the
  /// Pricing screen yet, since that's what seeds the starter catalog) —
  /// callers should fall back to `kPackages` when this stream is empty.
  ///
  /// Cache-first: the saved copy in the local database is emitted
  /// immediately (works offline), then live Firestore updates replace it
  /// and are written back to the local database.
  static Stream<List<BoothPackage>> watchPackages() {
    final remote = _col.where('category', isEqualTo: 'Booth Package').snapshots().map(
          (snap) => Synced(
            snap.docs.map(_toBoothPackage).toList(),
            fromCache: snap.metadata.isFromCache,
          ),
        );
    return OfflineCache.cacheFirst<BoothPackage>(
      readLocal: LocalDb.instance.loadPackages,
      remote: remote,
      writeLocal: LocalDb.instance.replacePackages,
    );
  }

  /// Every "Camera Rental" line — same idea as [watchPackages]. Callers
  /// should fall back to `kCameraOptions` when this stream is empty.
  /// Cache-first, same as [watchPackages].
  static Stream<List<CameraOption>> watchCameraOptions() {
    final remote = _col.where('category', isEqualTo: 'Camera Rental').snapshots().map(
          (snap) => Synced(
            snap.docs.map(_toCameraOption).toList(),
            fromCache: snap.metadata.isFromCache,
          ),
        );
    return OfflineCache.cacheFirst<CameraOption>(
      readLocal: LocalDb.instance.loadCameraOptions,
      remote: remote,
      writeLocal: LocalDb.instance.replaceCameraOptions,
    );
  }

  static BoothPackage _toBoothPackage(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return BoothPackage(
      id: doc.id,
      name: (d['name'] ?? '') as String,
      duration: (d['unit'] ?? '') as String,
      price: (d['price'] ?? 0) as int,
      features: (d['features'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      imageUrl: (d['imageUrl'] ?? '') as String,
      description: (d['description'] ?? '') as String,
    );
  }

  static CameraOption _toCameraOption(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final features = (d['features'] as List?)?.map((e) => e.toString()).toList() ?? const [];
    final adminDescription = (d['description'] ?? '') as String;
    return CameraOption(
      id: doc.id,
      name: (d['name'] ?? '') as String,
      // Uses the Admin description when set; otherwise falls back to the
      // features list (specs) as the description line.
      description: adminDescription.isNotEmpty
          ? adminDescription
          : (features.isNotEmpty ? features.join(' · ') : (d['unit'] ?? '') as String),
      dailyRate: (d['price'] ?? 0) as int,
      rate8Plus: ((d['rate8Plus'] ?? 0) as num).toInt(),
      rate5to7: ((d['rate5to7'] ?? 0) as num).toInt(),
      icon: 'camera', // Admin doesn't set an icon — the photo takes over when there is one
      imageUrl: (d['imageUrl'] ?? '') as String,
    );
  }
}

/// Decodes a `data:` URI produced by `PricingRepository.encodeImage` (on
/// the Admin side) back into raw bytes for `Image.memory`. Returns null
/// for an empty string or anything that isn't a valid data URI, so
/// callers can fall back to an icon.
///
/// Results are memoized: a package photo is a big base64 string, and
/// decoding it on every rebuild (scrolling, setState, stream updates) is
/// what made the customer app feel laggy. The cache is small and is
/// cleared if it ever grows past [_kDecodeCacheMax] photos.
final Map<String, Uint8List?> _decodeCache = {};
const int _kDecodeCacheMax = 40;

/// A short key for a (possibly multi-megabyte) data URI. Hashing the whole
/// string on every lookup would itself be slow on the web, so the key is the
/// length plus two small samples from the middle and the end.
String _decodeKey(String v) {
  final n = v.length;
  if (n < 160) return v;
  final mid = n ~/ 2;
  return '$n:${v.substring(mid, mid + 48)}:${v.substring(n - 48)}';
}

Uint8List? decodeDataUriImage(String value) {
  if (!value.startsWith('data:') || !value.contains(',')) return null;
  final key = _decodeKey(value);
  final hit = _decodeCache[key];
  if (hit != null) return hit;
  try {
    final bytes = base64Decode(value.split(',').last);
    if (_decodeCache.length >= _kDecodeCacheMax) _decodeCache.clear();
    _decodeCache[key] = bytes;
    return bytes;
  } catch (_) {
    return null;
  }
}
