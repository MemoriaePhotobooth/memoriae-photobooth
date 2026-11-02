import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/feedback_record.dart';

/// Firestore-backed repository for customer feedback — reads the same
/// `feedback` collection the User app's "Leave a Review" flow writes to.
///
/// Requires `Firebase.initializeApp()` to have already run and Firestore
/// security rules that let a signed-in admin read every entry and delete
/// one (see `firestore.rules`).
class FeedbackRepository {
  FeedbackRepository._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('feedback');

  /// Every piece of feedback, most recent first. Unfiltered/unsorted in
  /// the query itself (sorted client-side) so this never needs a
  /// Firestore composite index.
  static Stream<List<FeedbackRecord>> watchAllFeedback() {
    return _col.snapshots().map((snap) {
      final list = snap.docs.map(FeedbackRecord.fromFirestore).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Saves (or, with an empty [reply], clears) the business's reply.
  static Future<void> setReply(String id, String reply) async {
    final r = reply.trim();
    await _col.doc(id).update({
      'adminReply': r,
      'adminReplyAt': r.isEmpty ? FieldValue.delete() : FieldValue.serverTimestamp(),
    });
  }

  /// Hides a review from customers (or shows it again) without deleting it.
  static Future<void> setHidden(String id, bool hidden) => _col.doc(id).update({'hidden': hidden});

  /// Lets an Admin remove a piece of feedback (e.g. spam or inappropriate
  /// content) by [id].
  static Future<void> deleteFeedback(String id) async {
    await _col.doc(id).delete();
  }
}
