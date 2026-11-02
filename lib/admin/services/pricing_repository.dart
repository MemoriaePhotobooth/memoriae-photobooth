import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/pricing_item_record.dart';

/// Firestore-backed repository for the `pricing` collection — the shared
/// catalog of booth packages and camera rentals. Admin creates/edits/
/// deletes entries here; the Customer app's package picker and camera
/// rental screen read the same collection (read-only) so a change here,
/// photo included, shows up there right away.
///
/// Requires `Firebase.initializeApp()` to have already run and Firestore
/// security rules that let an admin account write to `pricing/{id}` and
/// let anyone read it (see `firestore.rules`).
class PricingRepository {
  PricingRepository._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('pricing');

  static bool _seeded = false;

  /// The very first time anyone opens this screen against an empty
  /// collection (a brand-new Firebase project), seed it with a starter
  /// catalog so Admin isn't staring at a blank page. Harmless to call
  /// more than once — it only writes when the collection is still empty.
  static Future<void> _seedIfEmpty() async {
    if (_seeded) return;
    _seeded = true;
    final snap = await _col.limit(1).get();
    if (snap.docs.isNotEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final item in _starterCatalog) {
      batch.set(_col.doc(item.id), item.toMap());
    }
    await batch.commit();
  }

  static const List<PricingItemRecord> _starterCatalog = [
    PricingItemRecord(id: 'pkg-classic', name: 'Classic Moments', category: 'Booth Package', price: 6500, unit: 'per 2 hrs'),
    PricingItemRecord(id: 'pkg-deluxe', name: 'Deluxe Experience', category: 'Booth Package', price: 9800, unit: 'per 3 hrs'),
    PricingItemRecord(id: 'pkg-premium', name: 'Premium Package', category: 'Booth Package', price: 13500, unit: 'per 4 hrs'),
    PricingItemRecord(id: 'cam-mirrorless', name: 'Mirrorless Camera', category: 'Camera Rental', price: 1200, unit: 'per 24 hrs'),
    PricingItemRecord(id: 'cam-instant', name: 'Instant Film Camera', category: 'Camera Rental', price: 600, unit: 'per 24 hrs'),
  ];

  static Stream<List<PricingItemRecord>> watchAllPricing() {
    _seedIfEmpty();
    return _col.snapshots().map((snap) => snap.docs.map(PricingItemRecord.fromFirestore).toList());
  }

  /// Adds a brand-new package or camera rental line to the price list —
  /// [item.imageUrl] can already carry a photo picked before saving (see
  /// [encodeImage]).
  static Future<void> addPricingItem(PricingItemRecord item) async {
    await _col.doc(item.id).set(item.toMap());
  }

  /// Edits any field of an existing line — name, category, price, unit,
  /// features, or its photo. Pass `imageUrl: ''` explicitly to clear an
  /// existing photo; omit it to leave the current photo untouched.
  static Future<void> updateItem(
    String id, {
    String? name,
    String? category,
    int? price,
    String? unit,
    String? imageUrl,
    List<String>? features,
    String? description,
    int? rate8Plus,
    int? rate5to7,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (category != null) updates['category'] = category;
    if (price != null) updates['price'] = price;
    if (unit != null) updates['unit'] = unit;
    if (imageUrl != null) updates['imageUrl'] = imageUrl;
    if (features != null) updates['features'] = features;
    if (description != null) updates['description'] = description;
    if (rate8Plus != null) updates['rate8Plus'] = rate8Plus;
    if (rate5to7 != null) updates['rate5to7'] = rate5to7;
    if (updates.isEmpty) return;
    await _col.doc(id).update(updates);
  }

  /// Removes a discontinued package or camera rental line by [id].
  static Future<void> removePricingItem(String id) async {
    await _col.doc(id).delete();
  }

  /// Encodes a picked photo as a `data:` URI, same technique
  /// `BookingRepository._encodeReceipt` uses for payment receipts — no
  /// Firebase Storage involved (that needs the project on a paid billing
  /// plan). Callers should already have constrained the image's
  /// dimensions/quality via `image_picker` before this runs, the same way
  /// `ReceiptUpload` does.
  static String encodeImage(Uint8List bytes, String fileName) {
    final mimeType = _guessMimeType(fileName);
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  static String _guessMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }
}
