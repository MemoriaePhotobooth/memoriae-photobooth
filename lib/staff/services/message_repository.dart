import 'package:cloud_firestore/cloud_firestore.dart';
import '../../shared/chat_media.dart';
import '../models/message_record.dart';

/// Firestore-backed repository for staff <-> customer chat — reads and
/// writes the same `messages` collection the User app's chat screen uses,
/// so a message from either side shows up for the other without any
/// extra syncing.
///
/// Requires `Firebase.initializeApp()` to have already run (see
/// `main_staff.dart`) and Firestore security rules that allow create/read
/// on `messages/{id}` (see `firestore.rules`).
class MessageRepository {
  MessageRepository._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('messages');

  /// Every message across every thread — screens filter/group by
  /// `userId`. Unfiltered on purpose (no `orderBy`, no `where`) so this
  /// never needs a composite index; sorting and grouping happen
  /// client-side in the inbox and thread screens.
  static Stream<List<MessageRecord>> watchAllMessages() {
    return _col.snapshots().map((snap) => snap.docs.map(MessageRecord.fromFirestore).toList());
  }

  static Future<void> sendMessage({
    required String userId,
    required String customerName,
    required String text,
    required bool fromStaff,
    ChatPickedImage? image,
  }) async {
    final doc = _col.doc();
    if (image != null) {
      await ChatMedia.saveImage(id: doc.id, userId: userId, fromStaff: fromStaff, dataUri: image.dataUri);
    }
    await doc.set({
      'userId': userId,
      'customerName': customerName,
      // Rules require non-empty text, so a photo-only message carries a label.
      'text': (text.isEmpty && image != null) ? kPhotoMessageText : text,
      'fromStaff': fromStaff,
      if (image != null) 'imageId': doc.id,
      'sentAt': FieldValue.serverTimestamp(),
    });
  }

  /// Permanently deletes this customer's whole conversation (messages,
  /// photos and the closed marker).
  static Future<void> clearThread(String userId) => ChatMedia.deleteThread(userId);

  static CollectionReference<Map<String, dynamic>> get _status =>
      FirebaseFirestore.instance.collection('threadStatus');

  /// When each thread was closed, keyed by userId. A thread counts as
  /// closed only while its last message is older than this — so a new
  /// message from the customer re-opens it without any extra write.
  /// Same `threadStatus` collection the Admin app reads/writes.
  static Stream<Map<String, DateTime>> watchClosedThreads() {
    return _status.snapshots().map((snap) {
      final out = <String, DateTime>{};
      for (final d in snap.docs) {
        if (d.data()['closed'] != true) continue;
        final ts = d.data()['closedAt'];
        out[d.id] = ts is Timestamp ? ts.toDate() : DateTime.now();
      }
      return out;
    });
  }

  static Future<void> closeThread(String userId) =>
      _status.doc(userId).set({'closed': true, 'closedAt': FieldValue.serverTimestamp()});

  static Future<void> reopenThread(String userId) =>
      _status.doc(userId).set({'closed': false, 'closedAt': FieldValue.delete()}, SetOptions(merge: true));
}
