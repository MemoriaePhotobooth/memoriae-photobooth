import 'server_clock.dart';

/// Booking curfew for the User app: customers can't place a booking from
/// 12:00 AM (midnight) until 6:00 AM, and can book again starting 6:00 AM.
///
/// Uses Firebase server time (see `ServerClock`) so changing the phone's
/// clock can't get around the curfew; falls back to the phone's clock if
/// the server time couldn't be fetched. This is about *when the customer taps Book* — not about which
/// event date/time they picked.
class BookingHours {
  BookingHours._();

  /// First hour of the closed window (00:00 = 12 AM).
  static const int closedFromHour = 0;

  /// First hour bookings are allowed again (06:00 = 6 AM).
  static const int reopensAtHour = 6;

  static bool isOpen([DateTime? now]) {
    final h = (now ?? ServerClock.now()).hour;
    return h >= reopensAtHour; // 00:00–05:59 => closed
  }

  /// The next 6:00 AM at or after [now] (today's 6 AM while closed).
  static DateTime nextOpening([DateTime? now]) {
    final n = now ?? ServerClock.now();
    return DateTime(n.year, n.month, n.day, reopensAtHour);
  }

  /// How long until bookings reopen (Duration.zero if already open).
  static Duration timeUntilOpen([DateTime? now]) {
    final n = now ?? ServerClock.now();
    if (isOpen(n)) return Duration.zero;
    return nextOpening(n).difference(n);
  }

  static const String closedMessage =
      "Booking is closed from 12:00 AM to 6:00 AM. "
      "You can book again starting 6:00 AM.";
}

/// Thrown when someone tries to book during the closed window.
class BookingClosedException implements Exception {
  final String message;
  const BookingClosedException([this.message = BookingHours.closedMessage]);
  @override
  String toString() => message;
}
