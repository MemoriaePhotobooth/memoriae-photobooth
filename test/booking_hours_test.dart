import 'package:flutter_test/flutter_test.dart';
import 'package:memoriae_photobooth/user/services/booking_hours.dart';

/// Manila wall-clock time. The value is flagged UTC only so BookingHours
/// reads its fields as-is (see ServerClock.phNow).
DateTime ph(int y, int m, int d, int h, [int min = 0]) => DateTime.utc(y, m, d, h, min);

void main() {
  final today = DateTime(2026, 11, 13);

  group('past-time check (Philippine time)', () {
    test('a morning slot is already over in the afternoon', () {
      expect(BookingHours.isSlotInPast(today, 10, ph(2026, 11, 13, 15)), isTrue);
    });

    test('a later slot today is still bookable', () {
      expect(BookingHours.isSlotInPast(today, 17, ph(2026, 11, 13, 15)), isFalse);
    });

    test('a slot that starts right now counts as started', () {
      expect(BookingHours.isSlotInPast(today, 15, ph(2026, 11, 13, 15)), isTrue);
    });

    test('tomorrow is never in the past, yesterday always is', () {
      final now = ph(2026, 11, 13, 23);
      expect(BookingHours.isSlotInPast(DateTime(2026, 11, 14), 8, now), isFalse);
      expect(BookingHours.isSlotInPast(DateTime(2026, 11, 12), 20, now), isTrue);
    });

    test('today has no bookable start left after 9 PM', () {
      expect(BookingHours.dateHasFutureSlot(today, ph(2026, 11, 13, 20, 30)), isTrue);
      expect(BookingHours.dateHasFutureSlot(today, ph(2026, 11, 13, 21, 30)), isFalse);
    });

    test('earliest start today is the next half hour', () {
      expect(BookingHours.earliestStart(today, ph(2026, 11, 13, 15, 10)), 15.5);
      expect(BookingHours.earliestStart(today, ph(2026, 11, 13, 6)), 8.0);
      expect(BookingHours.earliestStart(today, ph(2026, 11, 13, 22)), isNull);
    });
  });

  group('time label parsing', () {
    test('reads the start hour', () {
      expect(BookingHours.startHourOf('10:00 AM – 12:00 PM'), 10.0);
      expect(BookingHours.startHourOf('1:30 PM – 3:30 PM'), 13.5);
      expect(BookingHours.startHourOf('12:00 AM – 1:00 AM'), 0.0);
      expect(BookingHours.startHourOf('12:30 PM – 2:00 PM'), 12.5);
      expect(BookingHours.startHourOf('nonsense'), isNull);
    });
  });

  group('curfew uses Manila time', () {
    test('closed 12 AM – 6 AM, open from 6 AM', () {
      expect(BookingHours.isOpen(ph(2026, 11, 13, 0, 0)), isFalse);
      expect(BookingHours.isOpen(ph(2026, 11, 13, 5, 59)), isFalse);
      expect(BookingHours.isOpen(ph(2026, 11, 13, 6, 0)), isTrue);
    });
  });
}
