import 'package:cloud_firestore/cloud_firestore.dart';

/// A customer's refund request (`refundRequests/{id}`), read by staff/admin.
class RefundRequest {
  final String id;
  final String bookingId;
  final String userId;
  final String reason;
  final String status; // open | approved | declined
  final DateTime? createdAt;

  const RefundRequest({
    required this.id,
    required this.bookingId,
    required this.userId,
    required this.reason,
    required this.status,
    required this.createdAt,
  });

  factory RefundRequest.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final ts = d['createdAt'];
    return RefundRequest(
      id: doc.id,
      bookingId: (d['bookingId'] ?? '') as String,
      userId: (d['userId'] ?? '') as String,
      reason: (d['reason'] ?? '') as String,
      status: (d['status'] ?? 'open') as String,
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

class RefundRequestRepository {
  RefundRequestRepository._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('refundRequests');

  /// Requests still waiting for a decision, newest first. A single equality
  /// filter, so no composite index is needed.
  static Stream<List<RefundRequest>> watchOpen() {
    return _col.where('status', isEqualTo: 'open').snapshots().map((snap) {
      final list = snap.docs.map(RefundRequest.fromDoc).toList();
      final now = DateTime.now();
      list.sort((a, b) => (b.createdAt ?? now).compareTo(a.createdAt ?? now));
      return list;
    });
  }

  /// Records the decision on the request. The refund itself (if approved) is
  /// done through BookingRepository.updateStatus with a RefundDecision.
  static Future<void> decide(String id, String status, {String? decidedBy, String? note}) {
    return _col.doc(id).update({
      'status': status,
      'decidedAt': FieldValue.serverTimestamp(),
      'decidedBy': decidedBy ?? '',
      // Shown to the customer on their booking when a request is declined.
      if (note != null && note.trim().isNotEmpty) 'decisionNote': note.trim(),
    });
  }
}
