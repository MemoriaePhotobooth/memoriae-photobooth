import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Write-only side of the audit trail for the Staff app (Admin reads it
/// on its Activity Log page). Same document shape as the Admin copy.
class ActivityLogRepository {
  ActivityLogRepository._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('activityLog');

  /// "Package — Customer" for a booking doc's data, falling back to the
  /// short booking ref when there's no customer name.
  static String bookingSummary(String bookingId, Map<String, dynamic>? d) {
    final pkg = (d?['packageName'] ?? 'Booking') as String;
    final name = ((d?['customerName'] ?? '') as String).trim();
    final ref = bookingId.length <= 6 ? bookingId.toUpperCase() : bookingId.substring(bookingId.length - 6).toUpperCase();
    return '$pkg — ${name.isNotEmpty ? name : ref}';
  }

  /// Human label for a booking status change. A 'cancelled' status with
  /// the hold-cancel reason is a Live Queue cancel, not a normal reject.
  static String? bookingActionLabel(String status, String? rejectionReason) {
    switch (status) {
      case 'confirmed':
        return 'Approved booking';
      case 'cancelled':
        return (rejectionReason ?? '').startsWith('Hold cancelled') ? 'Cancelled hold' : 'Rejected booking';
      case 'completed':
        return 'Marked booking completed';
      default:
        return null; // not worth a log line (e.g. pending/awaiting_receipt)
    }
  }

  /// Set when the most recent log write failed (null once one succeeds), so
  /// the Activity Log page can say WHY it's empty instead of failing silently.
  static final ValueNotifier<String?> lastWriteError = ValueNotifier<String?>(null);

  /// Records one action, attributed to whoever is signed in. Best-effort:
  /// a failed log write never makes the real action look like it failed —
  /// but the error is kept in [lastWriteError] and printed to the console.
  static Future<void> log({required String action, required String targetSummary}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      await _col.add({
        'action': action,
        'targetSummary': targetSummary,
        'actorEmail': user?.email ?? 'unknown',
        'actorRole': 'staff',
        'createdAt': FieldValue.serverTimestamp(),
      });
      lastWriteError.value = null;
    } catch (e) {
      lastWriteError.value = e.toString();
      debugPrint('ActivityLog write failed: $e');
    }
  }
}