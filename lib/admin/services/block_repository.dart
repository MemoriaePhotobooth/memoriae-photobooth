import 'package:cloud_firestore/cloud_firestore.dart';
import 'activity_log_repository.dart';

/// A customer an admin has blocked from booking, renting, messaging and
/// leaving reviews.
class BlockedUser {
  final String userId;
  final String name;
  final String reason;
  final DateTime blockedAt;

  const BlockedUser({required this.userId, required this.name, required this.reason, required this.blockedAt});
}

/// Admin-side access to `blockedUsers/{userId}`. Firestore rules refuse
/// new bookings, rentals, reviews and customer messages from any userId
/// that has a document here, so a block takes effect on the server and
/// not just in the UI.
class BlockRepository {
  BlockRepository._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('blockedUsers');

  /// Every blocked customer, keyed by userId.
  static Stream<Map<String, BlockedUser>> watchBlocked() {
    return _col.snapshots().map((snap) {
      return {
        for (final d in snap.docs)
          d.id: BlockedUser(
            userId: d.id,
            name: (d.data()['name'] ?? '') as String,
            reason: (d.data()['reason'] ?? '') as String,
            blockedAt: (d.data()['blockedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          ),
      };
    });
  }

  static Future<void> block({required Iterable<String> userIds, required String name, required String reason}) async {
    final batch = FirebaseFirestore.instance.batch();
    for (final id in userIds.where((e) => e.isNotEmpty)) {
      batch.set(_col.doc(id), {
        'name': name,
        'reason': reason.trim(),
        'blockedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    await ActivityLogRepository.log(action: 'Blocked customer', targetSummary: name);
  }

  static Future<void> unblock({required Iterable<String> userIds, required String name}) async {
    final batch = FirebaseFirestore.instance.batch();
    for (final id in userIds.where((e) => e.isNotEmpty)) {
      batch.delete(_col.doc(id));
    }
    await batch.commit();
    await ActivityLogRepository.log(action: 'Unblocked customer', targetSummary: name);
  }
}
