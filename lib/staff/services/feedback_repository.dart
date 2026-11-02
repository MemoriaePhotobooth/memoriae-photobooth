import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/feedback_record.dart';

/// Firestore-backed repository for customer feedback — reads the same
/// `feedback` collection the User app's "Leave a Review" flow writes to.
///
/// Requires `Firebase.initializeApp()` to have already run and Firestore
/// security rules that let a signed-in staff member read every entry
/// (see `firestore.rules`).
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
}
