import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/feedback_record.dart';

/// Firestore-backed repository for customer-submitted feedback — writes
/// to the same `feedback` collection the Staff and Admin apps read from,
/// and is also where the Home screen's testimonial card pulls a real
/// review from.
///
/// Requires `Firebase.initializeApp()` to have already run and Firestore
/// security rules that allow create on `feedback/{id}` plus a customer
/// reading their own entries (see `firestore.rules`).
class FeedbackRepository {
  FeedbackRepository._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('feedback');

  /// This customer's own feedback entries, keyed by which booking each
  /// one was left against — used to check "have they already reviewed
  /// this booking?" without a second round trip per booking.
  static Stream<Set<String>> watchReviewedBookingIds(String userId) {
    return _col.where('userId', isEqualTo: userId).snapshots().map(
          (snap) => snap.docs.map((d) => d.data()['bookingId'] as String? ?? '').toSet(),
        );
  }

  static Future<void> addFeedback({
    required String bookingId,
    required String userId,
    required String customerName,
    required String packageName,
    required int rating,
    required String comment,
  }) async {
    await _col.add({
      'bookingId': bookingId,
      'userId': userId,
      'customerName': customerName,
      'packageName': packageName,
      'rating': rating.clamp(1, 5),
      'comment': comment.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// A handful of the best, most recent reviews — this is what the Home
  /// screen's testimonial card shows instead of a hard-coded quote. Falls
  /// back gracefully (see `home_screen.dart`) when this is empty, which
  /// it will be until the first real review comes in.
  ///
  /// Reads the whole collection unfiltered and sorts client-side (rating
  /// first, then most recent) rather than combining a `where` with two
  /// `orderBy` clauses — that combination needs a Firestore composite
  /// index set up manually in the console, which this app avoids
  /// everywhere else too.
  static Stream<List<FeedbackRecord>> watchTopReviews({int limit = 5}) {
    return _col.snapshots().map((snap) {
      final all = snap.docs.map(FeedbackRecord.fromFirestore).where((f) => f.rating >= 4 && !f.hidden).toList()
        ..sort((a, b) {
          final byRating = b.rating.compareTo(a.rating);
          return byRating != 0 ? byRating : b.createdAt.compareTo(a.createdAt);
        });
      return all.take(limit).toList();
    });
  }
}
