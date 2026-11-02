import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/pricing_item_record.dart';

/// Read-only view of the shared `pricing` collection Admin manages —
/// gives the Staff app's POS screen the same catalog of packages, camera
/// rentals, and add-ons the Customer app's package picker reads, without
/// staff ever being able to edit a price (that stays Admin-only).
class PricingRepository {
  PricingRepository._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('pricing');

  static Stream<List<PricingItemRecord>> watchAllPricing() {
    return _col.snapshots().map((snap) => snap.docs.map(PricingItemRecord.fromFirestore).toList());
  }
}