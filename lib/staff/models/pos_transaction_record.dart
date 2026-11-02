import 'package:cloud_firestore/cloud_firestore.dart';

/// One line in a POS sale's cart — a snapshot of a [PricingItemRecord]'s
/// name/price at the moment it was rung up (so a later price change on
/// Admin's Pricing screen never rewrites history) plus how many were
/// bought.
class PosLineItem {
  final String name;
  final String category; // 'Booth Package' | 'Camera Rental' | 'Add-on'
  final int unitPrice;
  final int quantity;

  const PosLineItem({required this.name, required this.category, required this.unitPrice, required this.quantity});

  int get lineTotal => unitPrice * quantity;

  Map<String, dynamic> toMap() => {
        'name': name,
        'category': category,
        'unitPrice': unitPrice,
        'quantity': quantity,
      };

  factory PosLineItem.fromMap(Map<String, dynamic> m) => PosLineItem(
        name: (m['name'] ?? '') as String,
        category: (m['category'] ?? '') as String,
        unitPrice: (m['unitPrice'] ?? 0) as int,
        quantity: (m['quantity'] ?? 1) as int,
      );
}

/// One completed over-the-counter sale — a walk-in package payment, a
/// camera-rental fee, or add-ons like extra prints — rung up by staff
/// through the POS screen. Stored in the `posTransactions` collection,
/// separate from `bookings`/`cameraRentals` since a single sale can mix
/// line items from more than one of those at once (e.g. a rental fee
/// plus a couple of extra prints in the same transaction).
class PosTransactionRecord {
  final String id;
  final List<PosLineItem> items;
  final int total;
  final String paymentMethod; // 'cash' | 'gcash'
  final int? amountReceived; // cash only — null for GCash
  final String referenceNote; // free-text: linked booking ref, customer name, etc.
  final String staffId;
  final String staffEmail;
  final DateTime createdAt;

  const PosTransactionRecord({
    required this.id,
    required this.items,
    required this.total,
    required this.paymentMethod,
    this.amountReceived,
    this.referenceNote = '',
    required this.staffId,
    required this.staffEmail,
    required this.createdAt,
  });

  int? get change => (paymentMethod == 'cash' && amountReceived != null) ? amountReceived! - total : null;

  factory PosTransactionRecord.fromFirestore(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final ts = d['createdAt'];
    return PosTransactionRecord(
      id: doc.id,
      items: (d['items'] as List? ?? const []).map((e) => PosLineItem.fromMap(Map<String, dynamic>.from(e as Map))).toList(),
      total: (d['total'] ?? 0) as int,
      paymentMethod: (d['paymentMethod'] ?? 'cash') as String,
      amountReceived: d['amountReceived'] as int?,
      referenceNote: (d['referenceNote'] ?? '') as String,
      staffId: (d['staffId'] ?? '') as String,
      staffEmail: (d['staffEmail'] ?? '') as String,
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}