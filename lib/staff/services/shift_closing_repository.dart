import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/shift_closing_record.dart';
import 'activity_log_repository.dart';

/// Firestore-backed repository for `shiftClosings` — the end-of-shift cash
/// counts staff submit from the POS screen. Closings are write-once (see
/// `firestore.rules`): a count can't be edited or deleted after the fact,
/// which is the whole point of a close-out.
class ShiftClosingRepository {
  ShiftClosingRepository._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('shiftClosings');

  /// Most recent close-outs first. Filtering by staff member happens on
  /// the client — a `where(staffId)` + `orderBy(closedAt)` query would
  /// need a composite index, and the list is small.
  static Stream<List<ShiftClosingRecord>> watchRecent({int limit = 200}) {
    return _col
        .orderBy('closedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(ShiftClosingRecord.fromFirestore).toList());
  }

  /// Saves a close-out. [closedAt] is the exact moment the sales totals
  /// were computed up to — the next close-out for this staff member starts
  /// from it, so no sale is ever counted in two shifts or in none.
  static Future<String> createClosing({
    required String staffId,
    required String staffEmail,
    required DateTime periodStart,
    required DateTime closedAt,
    required int salesCount,
    required int cashSales,
    required int gcashSales,
    required int openingFloat,
    required int expectedCash,
    required int countedCash,
    String notes = '',
  }) async {
    final ref = await _col.add({
      'staffId': staffId,
      'staffEmail': staffEmail,
      'periodStart': Timestamp.fromDate(periodStart),
      'closedAt': Timestamp.fromDate(closedAt),
      'salesCount': salesCount,
      'cashSales': cashSales,
      'gcashSales': gcashSales,
      'openingFloat': openingFloat,
      'expectedCash': expectedCash,
      'countedCash': countedCash,
      'notes': notes.trim(),
    });

    final variance = countedCash - expectedCash;
    final result = variance == 0
        ? 'balanced'
        : variance > 0
            ? 'over by ₱$variance'
            : 'short by ₱${-variance}';
    await ActivityLogRepository.log(
      action: 'Closed shift',
      targetSummary: 'Counted ₱$countedCash vs expected ₱$expectedCash — $result',
    );
    return ref.id;
  }
}