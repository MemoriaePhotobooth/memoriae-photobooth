import 'package:cloud_firestore/cloud_firestore.dart';

/// "Seen" marks for chat threads, stored on `threadStatus/{userId}` next to the
/// closed marker. Staff and admin each keep their own field, so one side
/// opening a thread doesn't clear the other side's unread dot.
class ThreadReadStatus {
  ThreadReadStatus._();

  static CollectionReference<Map<String, dynamic>> get _status =>
      FirebaseFirestore.instance.collection('threadStatus');

  /// userId -> when staff (or admin) last opened that thread.
  static Stream<Map<String, DateTime>> watch({required bool asStaff}) {
    final field = asStaff ? 'staffReadAt' : 'adminReadAt';
    return _status.snapshots().map((snap) {
      final out = <String, DateTime>{};
      for (final d in snap.docs) {
        final data = d.data();
        if (!data.containsKey(field)) continue;
        final ts = data[field];
        // A mark still being written reads as null; treat it as read now.
        out[d.id] = ts is Timestamp ? ts.toDate() : DateTime.now();
      }
      return out;
    });
  }

  static Future<void> markRead(String userId, {required bool asStaff}) {
    return _status.doc(userId).set(
      {asStaff ? 'staffReadAt' : 'adminReadAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  /// True when the customer wrote the newest message and nobody has opened
  /// the thread since it arrived.
  static bool isUnread({required bool fromCustomer, required DateTime sentAt, DateTime? readAt}) {
    return fromCustomer && (readAt == null || sentAt.isAfter(readAt));
  }
}
