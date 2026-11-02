import 'package:flutter_test/flutter_test.dart';
import 'package:memoriae_photobooth/admin/models/camera_rental_record.dart';

CameraRentalRecord rental({
  required DateTime dueAt,
  DateTime? returnedAt,
  int dailyRate = 2400,
  int overdueFee = 0,
  int damageFee = 0,
  String damageNote = '',
}) {
  return CameraRentalRecord(
    id: 'r1',
    userId: 'u1',
    cameraId: 'c1',
    cameraName: 'DSLR Camera Kit',
    rentedAt: dueAt.subtract(const Duration(hours: 24)),
    dueAt: dueAt,
    returnedAt: returnedAt,
    dailyRate: dailyRate,
    overdueFee: overdueFee,
    damageFee: damageFee,
    damageNote: damageNote,
  );
}

void main() {
  final due = DateTime(2026, 10, 1, 12);

  group('overdue fee suggestion', () {
    test('returned on time has no late hours or fee', () {
      final r = rental(dueAt: due, returnedAt: due.subtract(const Duration(minutes: 5)));
      expect(r.overdueHours, 0);
      expect(r.suggestedOverdueFee, 0);
      expect(r.status, 'returned');
    });

    test('rounds late time up to whole hours', () {
      final r = rental(dueAt: due, returnedAt: due.add(const Duration(hours: 2, minutes: 10)));
      expect(r.overdueHours, 3);
    });

    test('suggested fee is hourly rate (daily / 24) times hours late', () {
      final r = rental(dueAt: due, returnedAt: due.add(const Duration(hours: 3)), dailyRate: 2400);
      expect(r.suggestedOverdueFee, 300); // 2400 / 24 = 100 per hour
    });

    test('no suggestion when the rental has no daily rate', () {
      final r = rental(dueAt: due, returnedAt: due.add(const Duration(hours: 5)), dailyRate: 0);
      expect(r.suggestedOverdueFee, 0);
    });
  });

  group('charges', () {
    test('totalFees adds overdue and damage fees', () {
      final r = rental(dueAt: due, overdueFee: 300, damageFee: 500);
      expect(r.totalFees, 800);
      expect(r.hasCharges, isTrue);
    });

    test('a damage note alone counts as a recorded charge', () {
      final r = rental(dueAt: due, damageNote: 'Scratch on lens hood');
      expect(r.totalFees, 0);
      expect(r.hasCharges, isTrue);
    });

    test('a clean rental has no charges', () {
      expect(rental(dueAt: due).hasCharges, isFalse);
    });

    test('copyWith keeps the fee fields', () {
      final r = rental(dueAt: due, overdueFee: 100, damageFee: 200, damageNote: 'x').copyWith(acknowledged: true);
      expect(r.overdueFee, 100);
      expect(r.damageFee, 200);
      expect(r.damageNote, 'x');
      expect(r.acknowledged, isTrue);
    });
  });
}
