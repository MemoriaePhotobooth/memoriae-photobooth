import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// The kinds of announcement staff can post. Stored as a plain string on
/// the `announcements/{id}` document (`type` field) so the Staff and User
/// apps stay in sync without sharing code.
class AnnouncementType {
  AnnouncementType._();

  static const String info = 'info';
  static const String closed = 'closed';
  static const String reminder = 'reminder';

  static const List<String> all = ['info', 'closed', 'reminder'];

  static String label(String type) {
    if (type == 'closed') return 'Closed';
    if (type == 'reminder') return 'Reminder';
    return 'Info';
  }

  static Color color(String type) {
    if (type == 'closed') return const Color(0xFFB3261E);
    if (type == 'reminder') return const Color(0xFFB7791F);
    return const Color(0xFF1565C0);
  }

  static IconData icon(String type) {
    if (type == 'closed') return Icons.do_not_disturb_on_rounded;
    if (type == 'reminder') return Icons.notifications_active_rounded;
    return Icons.campaign_rounded;
  }
}

/// A single announcement posted by staff, backed by an
/// `announcements/{id}` Firestore document. Every customer can read it.
class AnnouncementRecord {
  final String id;
  final String title;
  final String message;
  final String type; // see [AnnouncementType]
  final bool pinned;
  final String createdByName;
  final DateTime createdAt;

  const AnnouncementRecord({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.pinned,
    required this.createdByName,
    required this.createdAt,
  });

  factory AnnouncementRecord.fromFirestore(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final ts = d['createdAt'];
    return AnnouncementRecord(
      id: doc.id,
      title: (d['title'] ?? '') as String,
      message: (d['message'] ?? '') as String,
      type: (d['type'] ?? 'info') as String,
      pinned: d['pinned'] == true,
      createdByName: (d['createdByName'] ?? '') as String,
      // A just-posted announcement may still be a pending local write, so
      // `createdAt` briefly reads null until the server timestamp lands —
      // treat that as "now" rather than sorting it to the wrong end.
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}
