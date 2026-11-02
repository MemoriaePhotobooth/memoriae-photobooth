import 'package:cloud_firestore/cloud_firestore.dart';

/// Plain data class for one editable price line — a booth package or a
/// camera rental — on the Admin > Pricing screen. Backed by a
/// `pricing/{id}` Firestore document, the same collection the Customer
/// app's package picker and camera rental screen read from, so an edit
/// (including the photo) shows up there right away.
class PricingItemRecord {
  final String id;
  final String name;
  final String category; // 'Booth Package' | 'Camera Rental'
  final int price;

  /// Camera rentals only: per-day rate for rentals of 8 days or more, as on
  /// the rate card ("8 days onwards"). 0 means not set — customers are then
  /// charged the 5-7 day rate.
  final int rate8Plus;

  /// Camera rentals only: per-day rate for 5-7 day rentals. 0 = not set
  /// (customers are then charged price - 100 per day).
  final int rate5to7;
  final String unit; // e.g. 'per event', 'per 24 hrs'

  /// Short marketing line shown on the Customer homepage package card
  /// (e.g. "Unlimited photos for 2 hours with a standee frame.").
  /// Empty means the card falls back to the first feature.
  final String description;

  /// A `data:` URI (base64-encoded photo), same technique
  /// `BookingRepository._encodeReceipt` uses for receipts — kept as a
  /// plain string here rather than Firebase Storage for the same reason:
  /// Storage needs the project on a paid billing plan, which this app
  /// intentionally avoids. Empty string means no photo set yet.
  final String imageUrl;

  /// Short bullet points shown under a booth package (e.g. "Unlimited
  /// prints"). Camera rentals can use this too, for specs, but don't have
  /// to — an empty list is fine either way.
  final List<String> features;

  const PricingItemRecord({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.unit,
    this.imageUrl = '',
    this.features = const [],
    this.description = '',
    this.rate8Plus = 0,
    this.rate5to7 = 0,
  });

  factory PricingItemRecord.fromFirestore(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return PricingItemRecord(
      id: doc.id,
      name: (d['name'] ?? '') as String,
      category: (d['category'] ?? 'Booth Package') as String,
      price: (d['price'] ?? 0) as int,
      rate8Plus: ((d['rate8Plus'] ?? 0) as num).toInt(),
      rate5to7: ((d['rate5to7'] ?? 0) as num).toInt(),
      unit: (d['unit'] ?? '') as String,
      imageUrl: (d['imageUrl'] ?? '') as String,
      features: (d['features'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      description: (d['description'] ?? '') as String,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'category': category,
        'price': price,
        'rate8Plus': rate8Plus,
        'rate5to7': rate5to7,
        'unit': unit,
        'imageUrl': imageUrl,
        'features': features,
        'description': description,
      };

  PricingItemRecord copyWith({String? name, String? category, int? price, String? unit, String? imageUrl, List<String>? features, String? description, int? rate8Plus, int? rate5to7}) {
    return PricingItemRecord(
      id: id,
      rate8Plus: rate8Plus ?? this.rate8Plus,
      rate5to7: rate5to7 ?? this.rate5to7,
      name: name ?? this.name,
      category: category ?? this.category,
      price: price ?? this.price,
      unit: unit ?? this.unit,
      imageUrl: imageUrl ?? this.imageUrl,
      features: features ?? this.features,
      description: description ?? this.description,
    );
  }
}
