import 'package:cloud_firestore/cloud_firestore.dart';
import '../../shared/chat_media.dart';
import '../models/message_record.dart';

/// Firestore-backed repository for the single support thread between this
/// customer and staff — writes to the same `messages` collection the
/// Staff app's inbox reads from.
///
/// Requires `Firebase.initializeApp()` to have already run (see
/// `main_user.dart`) and Firestore security rules that allow create/read
/// on `messages/{id}` (see `firestore.rules`).
class MessageRepository {
  MessageRepository._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('messages');

  /// This customer's whole thread, oldest first. Filtered by `userId`
  /// only (no `orderBy` in the query itself) so this never needs a
  /// composite index — the sort happens client-side instead.
  static Stream<List<MessageRecord>> watchThread(String userId) {
    return _col.where('userId', isEqualTo: userId).snapshots().map((snap) {
      final list = snap.docs.map(MessageRecord.fromFirestore).toList();
      list.sort((a, b) => a.sentAt.compareTo(b.sentAt));
      return list;
    });
  }

  /// Deletes one of this customer's own messages (and its photo, if any).
  /// Removes it for staff too, since both sides read the same document.
  static Future<void> deleteMessage(MessageRecord m) async {
    if (m.fromStaff) return; // customers can only delete their own messages
    if (m.hasImage) {
      try {
        await ChatMedia.deleteImage(m.imageId);
      } catch (_) {
        // Keep going — the message itself must still be removed.
      }
    }
    await _col.doc(m.id).delete();
  }

  static Future<void> sendMessage({
    required String userId,
    required String customerName,
    required String text,
    ChatPickedImage? image,
    String refType = '',
    String refId = '',
    String refTitle = '',
    String refSubtitle = '',
  }) async {
    final doc = _col.doc();
    if (image != null) {
      await ChatMedia.saveImage(id: doc.id, userId: userId, fromStaff: false, dataUri: image.dataUri);
    }
    await doc.set({
      'userId': userId,
      'customerName': customerName,
      // Rules require non-empty text, so a photo-only message carries a label.
      'text': (text.isEmpty && image != null) ? kPhotoMessageText : text,
      'fromStaff': false,
      if (image != null) 'imageId': doc.id,
      if (refType.isNotEmpty) ...{
        'refType': refType,
        'refId': refId,
        'refTitle': refTitle,
        'refSubtitle': refSubtitle,
      },
      'sentAt': FieldValue.serverTimestamp(),
    });
  }
}
