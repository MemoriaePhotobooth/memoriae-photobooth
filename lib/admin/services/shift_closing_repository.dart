import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/shift_closing_record.dart';

/// Read-only view of `shiftClosings` for Admin — the end-of-shift cash
/// counts staff submit from the POS screen. Admin never writes these
/// (a close-out is the staff member's own count), it only reviews them.
class ShiftClosingRepository {
  ShiftClosingRepository._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('shiftClosings');

  static Stream<List<ShiftClosingRecord>> watchRecent({int limit = 200}) {
    return _col
        .orderBy('closedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(ShiftClosingRecord.fromFirestore).toList());
  }
}