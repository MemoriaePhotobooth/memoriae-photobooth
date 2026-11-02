import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// A photo staff took at the customer's event (`eventPhotos/{id}`).
class EventPhoto {
  final String id;
  final String dataUri;
  final DateTime? createdAt;

  const EventPhoto({required this.id, required this.dataUri, required this.createdAt});

  static final Map<String, Uint8List> _bytesCache = {};

  /// Decoded image bytes (cached so rebuilds don't re-decode).
  Uint8List get bytes => _bytesCache.putIfAbsent(id, () => base64Decode(dataUri.substring(dataUri.indexOf(',') + 1)));

  factory EventPhoto.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final ts = d['createdAt'];
    return EventPhoto(
      id: doc.id,
      dataUri: (d['data'] ?? '') as String,
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

/// Read-only access to the photos staff uploaded for the customer's own
/// booking. The query filters on BOTH `bookingId` and `userId` because the
/// Firestore rule only allows reading photos whose `userId` is the signed-in
/// customer — a query that doesn't constrain `userId` would be rejected.
class EventPhotoRepository {
  EventPhotoRepository._();

  static Stream<List<EventPhoto>> watchForBooking({required String bookingId, required String userId}) {
    return FirebaseFirestore.instance
        .collection('eventPhotos')
        .where('bookingId', isEqualTo: bookingId)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(EventPhoto.fromDoc).toList();
      list.sort((a, b) {
        final at = a.createdAt, bt = b.createdAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return at.compareTo(bt);
      });
      return list;
    });
  }
}
