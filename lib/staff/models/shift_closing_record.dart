import 'package:cloud_firestore/cloud_firestore.dart';

/// One end-of-shift cash count a staff member submitted from the POS
/// screen — a frozen snapshot of what the POS said they should have in
/// the drawer versus what they actually counted. Stored in
/// `shiftClosings`; Admin reads the same collection to see variances.
///
/// A closing covers `[periodStart, closedAt]`: from that staff member's
/// previous close-out (or the start of the day if they've never closed
/// one) up to the moment they closed this one.
class ShiftClosingRecord {
  final String id;
  final String staffId;
  final String staffEmail;
  final DateTime periodStart;
  final DateTime closedAt;
  final int salesCount;
  final int cashSales;
  final int gcashSales;

  /// Change fund already in the drawer when the shift started.
  final int openingFloat;

  /// What the drawer should hold: opening float + cash sales.
  final int expectedCash;
  final int countedCash;
  final String notes;

  const ShiftClosingRecord({
    required this.id,
    required this.staffId,
    required this.staffEmail,
    required this.periodStart,
    required this.closedAt,
    required this.salesCount,
    required this.cashSales,
    required this.gcashSales,
    required this.openingFloat,
    required this.expectedCash,
    required this.countedCash,
    this.notes = '',
  });

  /// Counted minus expected: 0 = balanced, positive = over, negative = short.
  int get variance => countedCash - expectedCash;

  static int _asInt(dynamic v) => (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
  static DateTime _asDate(dynamic v) => v is Timestamp ? v.toDate() : DateTime.now();

  factory ShiftClosingRecord.fromFirestore(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return ShiftClosingRecord(
      id: doc.id,
      staffId: (d['staffId'] ?? '') as String,
      staffEmail: (d['staffEmail'] ?? '') as String,
      periodStart: _asDate(d['periodStart']),
      closedAt: _asDate(d['closedAt']),
      salesCount: _asInt(d['salesCount']),
      cashSales: _asInt(d['cashSales']),
      gcashSales: _asInt(d['gcashSales']),
      openingFloat: _asInt(d['openingFloat']),
      expectedCash: _asInt(d['expectedCash']),
      countedCash: _asInt(d['countedCash']),
      notes: (d['notes'] ?? '') as String,
    );
  }
}