import '../widgets/time_selector.dart' show kEarliestHour, kLatestHour, kMinBookingHours;
import 'server_clock.dart';

/// Booking rules for the User app. Everything here is judged in
/// **Philippine time (UTC+8)** using Firebase server time (see
/// `ServerClock`), so neither the phone's clock nor its time zone setting
/// can get around them.
///
/// 1. Booking curfew: customers can't place a booking from 12:00 AM
///    (midnight) until 6:00 AM, and can book again starting 6:00 AM. This
///    is about *when the customer taps Book*.
/// 2. No booking in the past: a slot whose start time has already passed
///    (e.g. 10:00 AM when it's already 3:00 PM today) can't be booked.
///    This is about *which date/time the customer picked*.
class BookingHours {
  BookingHours._();

  /// First hour of the closed window (00:00 = 12 AM).
  static const int closedFromHour = 0;

  /// First hour bookings are allowed again (06:00 = 6 AM).
  static const int reopensAtHour = 6;

  /// Current Manila time (wall-clock fields only — see [ServerClock.phNow]).
  static DateTime phNow([DateTime? now]) => now ?? ServerClock.phNow();

  static bool isOpen([DateTime? now]) {
    final h = phNow(now).hour;
    return h >= reopensAtHour; // 00:00–05:59 => closed
  }

  /// The next 6:00 AM at or after [now] (today's 6 AM while closed).
  static DateTime nextOpening([DateTime? now]) {
    final n = phNow(now);
    return DateTime(n.year, n.month, n.day, reopensAtHour);
  }

  /// How long until bookings reopen (Duration.zero if already open).
  static Duration timeUntilOpen([DateTime? now]) {
    final n = phNow(now);
    if (isOpen(n)) return Duration.zero;
    final open = nextOpening(n);
    return open.difference(DateTime(n.year, n.month, n.day, n.hour, n.minute, n.second));
  }

  static const String closedMessage =
      "Booking is closed from 12:00 AM to 6:00 AM. "
      "You can book again starting 6:00 AM.";

  // ───────────────────────── past-time check ─────────────────────────

  static const String slotPassedMessage =
      "That time has already passed. Please pick a later time or another date.";

  /// Reads the start hour out of a label like "10:00 AM – 12:00 PM" and
  /// returns it as a decimal hour (10.0, 13.5, …). Null if it can't be read.
  static double? startHourOf(String timeLabel) {
    final m = RegExp(r'(\d{1,2}):(\d{2})\s*([AaPp][Mm])').firstMatch(timeLabel);
    if (m == null) return null;
    var h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    final pm = m.group(3)!.toLowerCase() == 'pm';
    h = h % 12;
    if (pm) h += 12;
    return h + min / 60.0;
  }

  /// True when the slot starting at [startHour] on [date] has already
  /// started (or the whole day is over) in Philippine time.
  static bool isSlotInPast(DateTime date, double startHour, [DateTime? now]) {
    final n = phNow(now);
    final today = DateTime(n.year, n.month, n.day);
    final day = DateTime(date.year, date.month, date.day);
    if (day.isBefore(today)) return true;
    if (day.isAfter(today)) return false;
    final nowHour = n.hour + n.minute / 60.0 + n.second / 3600.0;
    return startHour <= nowHour;
  }

  /// Whether [date] still has at least one start time left that is in the
  /// future. Today stops being bookable once the last possible start
  /// ([kLatestHour] − [kMinBookingHours]) has passed.
  static bool dateHasFutureSlot(DateTime date, [DateTime? now]) {
    return !isSlotInPast(date, kLatestHour - kMinBookingHours, now);
  }

  /// The first half-hour start on [date] that is still in the future, or
  /// null if the day has none left.
  static double? earliestStart(DateTime date, [DateTime? now]) {
    for (var h = kEarliestHour; h <= kLatestHour - kMinBookingHours + 0.001; h += 0.5) {
      if (!isSlotInPast(date, h, now)) return h;
    }
    return null;
  }
}

/// Thrown when someone tries to book during the closed window.
class BookingClosedException implements Exception {
  final String message;
  const BookingClosedException([this.message = BookingHours.closedMessage]);
  @override
  String toString() => message;
}

/// Thrown when someone tries to book a date/time that has already passed.
class SlotInPastException implements Exception {
  final String message;
  const SlotInPastException([this.message = BookingHours.slotPassedMessage]);
  @override
  String toString() => message;
}
