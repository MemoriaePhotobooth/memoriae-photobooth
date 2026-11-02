import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/announcement_record.dart';

/// Staff-side access to the `announcements` collection — staff post,
/// pin/unpin and delete; the User app reads the same collection so a new
/// announcement shows up on the customer side right away.
///
/// Requires `Firebase.initializeApp()` to have already run and Firestore
/// rules that let staff write `announcements/{id}` (see `firestore.rules`).
class AnnouncementRepository {
  AnnouncementRepository._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('announcements');

  /// Pinned first, then newest first. Sorted client-side so no composite
  /// index is needed.
  static Stream<List<AnnouncementRecord>> watchAll() {
    return _col.snapshots().map((snap) {
      final list = snap.docs.map(AnnouncementRecord.fromFirestore).toList();
      list.sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
      return list;
    });
  }

  static Future<void> post({
    required String title,
    required String message,
    required String type,
    required bool pinned,
    required String? createdById,
    required String createdByName,
  }) async {
    await _col.add({
      'title': title,
      'message': message,
      'type': type,
      'pinned': pinned,
      'createdById': createdById,
      'createdByName': createdByName,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> setPinned(String id, bool pinned) async {
    await _col.doc(id).update({'pinned': pinned});
  }

  static Future<void> delete(String id) async {
    await _col.doc(id).delete();
  }
}
