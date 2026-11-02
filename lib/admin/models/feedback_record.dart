import 'package:cloud_firestore/cloud_firestore.dart';

/// Plain data class for a piece of customer feedback left against a
/// completed booking, backed by a `feedback/{id}` Firestore document —
/// the same collection the User app's "Leave a Review" flow writes to.
class FeedbackRecord {
  final String id;
  final String bookingId;
  final String userId;
  final String customerName;
  final String packageName;
  final int rating; // 1-5
  final String comment;
  final DateTime createdAt;

  /// Moderation: a hidden review stays in Firestore (and in the admin's
  /// list) but is no longer shown to customers.
  final bool hidden;

  /// The business's public reply to this review, empty when none.
  final String adminReply;
  final DateTime? adminReplyAt;

  const FeedbackRecord({
    required this.id,
    required this.bookingId,
    required this.userId,
    required this.customerName,
    required this.packageName,
    required this.rating,
    required this.comment,
    required this.createdAt,
    this.hidden = false,
    this.adminReply = '',
    this.adminReplyAt,
  });

  factory FeedbackRecord.fromFirestore(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final ts = d['createdAt'];
    return FeedbackRecord(
      id: doc.id,
      bookingId: (d['bookingId'] ?? '') as String,
      userId: (d['userId'] ?? '') as String,
      customerName: (d['customerName'] ?? '') as String,
      packageName: (d['packageName'] ?? '') as String,
      rating: (d['rating'] as num?)?.toInt() ?? 5,
      comment: (d['comment'] ?? '') as String,
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
      hidden: d['hidden'] == true,
      adminReply: (d['adminReply'] ?? '') as String,
      adminReplyAt: (d['adminReplyAt'] as Timestamp?)?.toDate(),
    );
  }
}
