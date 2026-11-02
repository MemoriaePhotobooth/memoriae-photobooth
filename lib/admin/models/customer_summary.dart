import '../services/block_repository.dart';
import '../services/user_account_repository.dart';
import 'booking_record.dart';
import 'feedback_record.dart';

/// One customer, rolled up from every booking (and review) that belongs
/// to them — the data behind the Customers page.
class CustomerSummary {
  final String key;
  String name;
  String email;
  String contact;
  final List<BookingRecord> bookings = [];
  final List<FeedbackRecord> feedback = [];

  /// Account ids from the Register screen (users/{uid}). Filled even when the
  /// person hasn't booked anything yet.
  final Set<String> accountIds = {};

  /// When the app account was created. Null for walk-ins with no account.
  DateTime? registeredAt;

  CustomerSummary(this.key)
      : email = '',
        name = '',
        contact = '';

  /// App account ids behind this customer. Empty for walk-ins staff typed
  /// in by hand, who have no account to message or block.
  Set<String> get userIds => {...bookings.map((b) => b.userId).where((id) => id.isNotEmpty), ...accountIds};

  bool isBlockedIn(Map<String, BlockedUser> blocked) => userIds.any(blocked.containsKey);

  /// Only confirmed/completed bookings count as money actually earned.
  int get totalSpent =>
      bookings.where((b) => b.status == 'confirmed' || b.status == 'completed').fold<int>(0, (sum, b) => sum + b.paidAmount);

  /// Bookings that weren't rejected/cancelled — what makes someone a repeat customer.
  int get activeBookingCount => bookings.where((b) => b.status != 'cancelled').length;

  /// Registered within the last 7 days.
  bool get isNewAccount => registeredAt != null && DateTime.now().difference(registeredAt!).inDays < 7;

  DateTime? get lastBookingDate =>
      bookings.isEmpty ? null : bookings.map((b) => b.date).reduce((a, b) => a.isAfter(b) ? a : b);

  double? get avgRating =>
      feedback.isEmpty ? null : feedback.fold<int>(0, (sum, f) => sum + f.rating) / feedback.length;
}

/// Groups bookings (and reviews) into one entry per customer. App
/// customers are keyed by their account id; walk-ins staff entered with
/// an email are keyed by that email (so a returning walk-in merges into
/// one entry instead of one per visit); anyone else falls back to name.
///
/// [accounts] are the users who registered in the app. Each one is merged into
/// the matching customer (same email or account id) or listed on their own, so
/// the admin sees a new account right away even before the first booking.
List<CustomerSummary> groupCustomers(
  List<BookingRecord> bookings,
  List<FeedbackRecord> feedback, {
  List<RegisteredAccount> accounts = const [],
}) {
  final map = <String, CustomerSummary>{};
  final keyByUserId = <String, String>{};
  for (final b in bookings) {
    if (b.status == 'awaiting_receipt') continue; // an unpaid slot hold isn't a customer yet
    final email = b.customerEmail.trim().toLowerCase();
    final key = email.isNotEmpty
        ? 'e:$email'
        : b.userId.isNotEmpty
            ? 'u:${b.userId}'
            : 'n:${b.customerName.trim().toLowerCase()}';
    final c = map.putIfAbsent(key, () => CustomerSummary(key));
    c.bookings.add(b);
    if (c.name.isEmpty && b.customerName.trim().isNotEmpty) c.name = b.customerName.trim();
    if (c.email.isEmpty) c.email = b.customerEmail.trim();
    if (c.contact.isEmpty) c.contact = b.customerContact.trim();
    if (b.userId.isNotEmpty) keyByUserId[b.userId] = key;
  }
  for (final a in accounts) {
    final email = a.email.trim().toLowerCase();
    final key = keyByUserId[a.uid] ??
        (email.isNotEmpty ? 'e:$email' : 'u:${a.uid}');
    final c = map.putIfAbsent(key, () => CustomerSummary(key));
    c.accountIds.add(a.uid);
    c.registeredAt = a.createdAt ?? c.registeredAt;
    if (c.name.isEmpty && a.name.isNotEmpty) c.name = a.name;
    if (c.email.isEmpty) c.email = a.email;
    if (c.contact.isEmpty) c.contact = a.contact;
    keyByUserId[a.uid] = key;
  }
  for (final f in feedback) {
    final key = keyByUserId[f.userId];
    if (key != null) map[key]!.feedback.add(f);
  }
  final list = map.values.toList();
  for (final c in list) {
    if (c.name.isEmpty) c.name = 'Unnamed customer';
  }
  return list;
}
