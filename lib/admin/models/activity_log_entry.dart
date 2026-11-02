import 'package:cloud_firestore/cloud_firestore.dart';

/// One entry in the `activityLog` collection: who did what, to what, and
/// when. Immutable once written (see `firestore.rules`) — if an action
/// needs undoing, that's a new action, not an edit to the log.
class ActivityLogEntry {
  final String id;
  final String action; // e.g. "Approved booking"
  final String targetSummary; // e.g. "Classic Moments — Juan Dela Cruz"
  final String actorEmail;
  final String actorRole; // 'admin' | 'staff' | 'unknown'
  final DateTime createdAt;

  const ActivityLogEntry({
    required this.id,
    required this.action,
    required this.targetSummary,
    required this.actorEmail,
    required this.actorRole,
    required this.createdAt,
  });

  factory ActivityLogEntry.fromFirestore(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final ts = d['createdAt'];
    return ActivityLogEntry(
      id: doc.id,
      action: (d['action'] ?? '') as String,
      targetSummary: (d['targetSummary'] ?? '') as String,
      actorEmail: (d['actorEmail'] ?? '') as String,
      actorRole: (d['actorRole'] ?? 'unknown') as String,
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}