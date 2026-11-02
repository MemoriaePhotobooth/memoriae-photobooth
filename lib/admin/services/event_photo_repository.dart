import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// A photo staff or admin took during an event (`eventPhotos/{id}`).
class EventPhoto {
  final String id;
  final String bookingId;
  final String dataUri;
  final String uploadedByName;
  final DateTime? createdAt;

  const EventPhoto({
    required this.id,
    required this.bookingId,
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
      dataUri: (d['data'] ?? '') as String,
      uploadedByName: (d['uploadedByStaffName'] ?? '') as String,
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

/// A booking shown on the admin Event Photos screen.
class EventPhotoBooking {
  final String id;
  final String userId;
  final String status;
  final String customerName;
  final String packageName;
  final DateTime date;
  final String time;
  final int count;

  const EventPhotoBooking({
    required this.id,
    this.userId = '',
    this.status = '',
    required this.customerName,
    required this.packageName,
    required this.date,
    required this.time,
    required this.count,
  });

  String get bookingRef => id.length <= 6 ? id.toUpperCase() : id.substring(id.length - 6).toUpperCase();

  factory EventPhotoBooking.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final ts = d['date'];
    return EventPhotoBooking(
      id: doc.id,
      userId: (d['userId'] ?? '') as String,
      status: (d['status'] ?? '') as String,
      customerName: (d['customerName'] ?? '') as String,
      packageName: (d['packageName'] ?? '') as String,
      date: ts is Timestamp ? ts.toDate() : DateTime.fromMillisecondsSinceEpoch(0),
      time: (d['time'] ?? '') as String,
      count: ((d['eventPhotoCount'] ?? 0) as num).toInt(),
    );
  }
}

class EventPhotoRepository {
  EventPhotoRepository._();

  /// Must stay under the Firestore rule's `data.size() < 850000` cap.
  static const int maxEncodedLength = 850000;

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('eventPhotos');

  static DocumentReference<Map<String, dynamic>> _booking(String id) =>
      FirebaseFirestore.instance.collection('bookings').doc(id);

  /// Confirmed/completed bookings dated today, so the admin can add photos
  /// before any photo exists. Single-field range, so no composite index.
  static Stream<List<EventPhotoBooking>> watchTodayBookings() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return FirebaseFirestore.instance
        .collection('bookings')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end))
        .snapshots()
        .map((snap) => snap.docs
            .map(EventPhotoBooking.fromDoc)
            .where((b) => b.status == 'confirmed' || b.status == 'completed')
            .toList());
  }

  /// Bookings that have at least one event photo (uses `eventPhotoCount`, so no
  /// photo data is downloaded to build the list).
  static Stream<List<EventPhotoBooking>> watchBookingsWithPhotos() {
    return FirebaseFirestore.instance
        .collection('bookings')
        .where('eventPhotoCount', isGreaterThan: 0)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(EventPhotoBooking.fromDoc).toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    });
  }

  /// Live photos of one booking, oldest first (the order they were taken).
  static Stream<List<EventPhoto>> watch(String bookingId) {
    return _col.where('bookingId', isEqualTo: bookingId).snapshots().map((snap) {
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

  /// Saves one photo as the admin and bumps the booking's `eventPhotoCount`.
  static Future<void> add({
    required String bookingId,
    required String userId,
    required Uint8List bytes,
    required String mime,
  }) async {
    final encoded = 'data:$mime;base64,${base64Encode(bytes)}';
    if (encoded.length >= maxEncodedLength) {
      throw Exception('That photo is too large to upload.');
    }
    final batch = FirebaseFirestore.instance.batch();
    batch.set(_col.doc(), {
      'bookingId': bookingId,
      'userId': userId,
      'data': encoded,
      'uploadedByStaffName': 'Admin',
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_booking(bookingId), {
      'eventPhotoCount': FieldValue.increment(1),
      'eventPhotosAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Removes one photo and keeps the booking's `eventPhotoCount` in step.
  static Future<void> delete(EventPhoto photo) async {
    final batch = FirebaseFirestore.instance.batch();
    batch.delete(_col.doc(photo.id));
    batch.update(_booking(photo.bookingId), {'eventPhotoCount': FieldValue.increment(-1)});
    await batch.commit();
    EventPhoto._bytesCache.remove(photo.id);
  }
}
