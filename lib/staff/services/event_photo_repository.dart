import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// One photo staff took during an event, stored in `eventPhotos/{id}`.
///
/// Same base64-in-Firestore approach as receipts and chat photos, so no
/// Firebase Storage plan is needed. Each photo is tied to a booking and to
/// that booking's customer (`userId`), and Firestore rules only let that
/// customer (or staff/admin) read it.
class EventPhoto {
  final String id;
  final String bookingId;
  final String userId;
  final String dataUri;
  final String uploadedByName;
  final DateTime? createdAt;

  const EventPhoto({
    required this.id,
    required this.bookingId,
    required this.userId,
    required this.dataUri,
    required this.uploadedByName,
    required this.createdAt,
  });

  static final Map<String, Uint8List> _bytesCache = {};

  /// Decoded image bytes (cached so rebuilds don't re-decode).
  Uint8List get bytes => _bytesCache.putIfAbsent(id, () => base64Decode(dataUri.substring(dataUri.indexOf(',') + 1)));

  factory EventPhoto.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final ts = d['createdAt'];
    return EventPhoto(
      id: doc.id,
      bookingId: (d['bookingId'] ?? '') as String,
      userId: (d['userId'] ?? '') as String,
      dataUri: (d['data'] ?? '') as String,
      uploadedByName: (d['uploadedByStaffName'] ?? '') as String,
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

class EventPhotoRepository {
  EventPhotoRepository._();

  /// Must stay under the Firestore rule's `data.size() < 850000` cap (a
  /// document can't exceed 1 MiB).
  static const int maxEncodedLength = 850000;

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('eventPhotos');

  static DocumentReference<Map<String, dynamic>> _booking(String id) =>
      FirebaseFirestore.instance.collection('bookings').doc(id);

  /// Live photos for one booking, oldest first (the order they were taken).
  /// Filtered on a single field, so no composite index is needed.
  static Stream<List<EventPhoto>> watch(String bookingId) {
    return _col.where('bookingId', isEqualTo: bookingId).snapshots().map((snap) {
      final list = snap.docs.map(EventPhoto.fromDoc).toList();
      list.sort((a, b) {
        final at = a.createdAt, bt = b.createdAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1; // just-uploaded (pending server time) goes last
        if (bt == null) return -1;
        return at.compareTo(bt);
      });
      return list;
    });
  }

  /// Saves one photo and bumps the booking's `eventPhotoCount` (so the
  /// customer's My Bookings can show "Event Photos (12)" without loading
  /// any images). Throws if the photo is too big to store.
  static Future<void> add({
    required String bookingId,
    required String userId,
    required Uint8List bytes,
    required String mime,
    String? staffId,
    String? staffName,
  }) async {
    final encoded = 'data:$mime;base64,${base64Encode(bytes)}';
    if (encoded.length >= maxEncodedLength) {
      throw Exception('That photo is too large to upload.');
    }
    final batch = FirebaseFirestore.instance.batch();
    final ref = _col.doc();
    batch.set(ref, {
      'bookingId': bookingId,
      'userId': userId,
      'data': encoded,
      if (staffId != null) 'uploadedByStaffId': staffId,
      'uploadedByStaffName': staffName ?? 'Staff',
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_booking(bookingId), {
      'eventPhotoCount': FieldValue.increment(1),
      'eventPhotosAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  static Future<void> delete(EventPhoto photo) async {
    final batch = FirebaseFirestore.instance.batch();
    batch.delete(_col.doc(photo.id));
    batch.update(_booking(photo.bookingId), {'eventPhotoCount': FieldValue.increment(-1)});
    await batch.commit();
    EventPhoto._bytesCache.remove(photo.id);
  }
}
