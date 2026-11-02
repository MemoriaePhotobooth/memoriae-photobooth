import 'package:cloud_firestore/cloud_firestore.dart';

/// A customer's request for a refund on their own paid booking
/// (`refundRequests/{id}`). Staff/admin review it; approving it still goes
/// through the normal cancel + refund flow.
class RefundRequestRepository {
  RefundRequestRepository._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('refundRequests');

  /// True if this customer already has a request on this booking that is
  /// still waiting for a decision. A declined request doesn't count, so
  /// the customer can ask again.
  static Future<bool> hasRequest({required String bookingId, required String userId}) async {
    final snap = await _col
        .where('userId', isEqualTo: userId)
        .where('bookingId', isEqualTo: bookingId)
        .where('status', isEqualTo: 'open')
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  /// The customer's most recent request on [bookingId] (or null if none):
  /// `status` is open | approved | declined, plus `reason` and, for a
  /// declined one, staff's `decisionNote`.
  static Stream<Map<String, dynamic>?> watchLatest({required String bookingId, required String userId}) {
    return _col
        .where('userId', isEqualTo: userId)
        .where('bookingId', isEqualTo: bookingId)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      final docs = snap.docs.toList()
        ..sort((a, b) {
          final ta = a.data()['createdAt'];
          final tb = b.data()['createdAt'];
          final da = ta is Timestamp ? ta.toDate() : DateTime.now();
          final db = tb is Timestamp ? tb.toDate() : DateTime.now();
          return db.compareTo(da);
        });
      return docs.first.data();
    });
  }

  static Future<void> submit({
    required String bookingId,
    required String userId,
    required String reason,
  }) async {
    await _col.add({
      'bookingId': bookingId,
      'userId': userId,
      'reason': reason,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
