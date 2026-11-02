import '../models/activity_log_entry.dart';

/// Broad groups the Activity Log can be narrowed to.
enum ActivityCategory { all, bookings, rentals, customers, other }

/// Which group a log entry belongs to, judged from its action text (the
/// log stores free-text actions such as "Approved booking").
ActivityCategory activityCategoryOf(ActivityLogEntry e) {
  final a = e.action.toLowerCase();
  if (a.contains('rental')) return ActivityCategory.rentals;
  if (a.contains('blocked') || a.contains('unblocked') || a.contains('customer')) return ActivityCategory.customers;
  if (a.contains('booking') || a.contains('hold') || a.contains('walk-in') || a.contains('refund') || a.contains('reschedul')) {
    return ActivityCategory.bookings;
  }
  return ActivityCategory.other;
}

/// Applies the Activity Log's filters. [since] keeps only entries at or
/// after that moment; [query] matches action, target or who did it.
List<ActivityLogEntry> filterActivity(
  List<ActivityLogEntry> entries, {
  String role = 'all',
  ActivityCategory category = ActivityCategory.all,
  String query = '',
  DateTime? since,
}) {
  final q = query.trim().toLowerCase();
  return entries.where((e) {
    if (role != 'all' && e.actorRole != role) return false;
    if (category != ActivityCategory.all && activityCategoryOf(e) != category) return false;
    if (since != null && e.createdAt.isBefore(since)) return false;
    if (q.isNotEmpty &&
        !e.action.toLowerCase().contains(q) &&
        !e.targetSummary.toLowerCase().contains(q) &&
        !e.actorEmail.toLowerCase().contains(q)) {
      return false;
    }
    return true;
  }).toList();
}
