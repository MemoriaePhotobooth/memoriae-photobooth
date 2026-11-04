import 'package:cloud_firestore/cloud_firestore.dart';

/// A customer's refund request (`refundRequests/{id}`), read by staff/admin.
class RefundRequest {
  final String id;
  final String bookingId;
  final String userId;
  final String reason;
  final String status; // open | approved | declined
  final DateTime? createdAt;
  final DateTime? decidedAt;
  final String decisionNote;

  const RefundRequest({
    required this.id,
    required this.bookingId,
    required this.userId,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.decidedAt,
    this.decisionNote = '',
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
      decidedAt: d['decidedAt'] is Timestamp ? (d['decidedAt'] as Timestamp).toDate() : null,
      decisionNote: (d['decisionNote'] ?? '') as String,
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

  /// Requests already decided ([status] is `approved` or `declined`), most
  /// recently decided first. Also a single equality filter.
  static Stream<List<RefundRequest>> watchDecided(String status) {
    return _col.where('status', isEqualTo: status).snapshots().map((snap) {
      final list = snap.docs.map(RefundRequest.fromDoc).toList();
      DateTime when(RefundRequest r) => r.decidedAt ?? r.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      list.sort((a, b) => when(b).compareTo(when(a)));
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
