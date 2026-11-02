import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/announcement_record.dart';
import 'local_db.dart';
import 'offline_cache.dart';

/// Read-only view of the announcements staff post from the Staff app
/// (`announcements` Firestore collection). Requires
/// `Firebase.initializeApp()` to have already run and a Firestore rule that
/// allows public `read` on `announcements/{id}` (see `firestore.rules`).
class AnnouncementRepository {
  AnnouncementRepository._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('announcements');

  /// Every announcement, pinned ones first and then newest first. No
  /// `where`/`orderBy` in the query itself so this never needs a composite
  /// index — the sort happens client-side (same approach as messages).
  ///
  /// Cache-first: the saved copy in the local database shows immediately
  /// (works offline), then live Firestore updates replace it.
  static Stream<List<AnnouncementRecord>> watchAll() {
    final remote = _col.snapshots().map((snap) {
      final list = snap.docs.map(AnnouncementRecord.fromFirestore).toList();
      list.sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
      return Synced(list, fromCache: snap.metadata.isFromCache);
    });
    return OfflineCache.cacheFirst<AnnouncementRecord>(
      readLocal: LocalDb.instance.loadAnnouncements,
      remote: remote,
      writeLocal: LocalDb.instance.replaceAnnouncements,
    );
  }
}
