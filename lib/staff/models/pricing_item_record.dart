import 'package:cloud_firestore/cloud_firestore.dart';

/// Plain data class for one price line — a booth package, a camera
/// rental, or a POS add-on — read from the `pricing/{id}` collection
/// that Admin manages. Staff only reads this (via [PricingRepository]),
/// never writes it — editing prices stays an Admin-only capability.
class PricingItemRecord {
  final String id;
  final String name;
  final String category; // 'Booth Package' | 'Camera Rental' | 'Add-on'
  final int price;

  /// Camera rentals only: per-day rate for 8+ day rentals (0 = not set).
  final int rate8Plus;

  /// Camera rentals only: per-day rate for 5-7 days (0 = not set).
  final int rate5to7;
  final String unit; // e.g. 'per event', 'per 24 hrs', 'per item'
  final String imageUrl;
  final List<String> features;

  const PricingItemRecord({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.unit,
    this.imageUrl = '',
    this.features = const [],
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
    );
  }
}