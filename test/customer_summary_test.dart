import 'package:flutter_test/flutter_test.dart';
import 'package:memoriae_photobooth/admin/models/booking_record.dart';
import 'package:memoriae_photobooth/admin/models/customer_summary.dart';
import 'package:memoriae_photobooth/admin/models/feedback_record.dart';
import 'package:memoriae_photobooth/admin/services/block_repository.dart';
import 'package:memoriae_photobooth/admin/services/user_account_repository.dart';

BookingRecord booking({
  String id = 'b1',
  String userId = '',
  String name = '',
  String email = '',
  String status = 'confirmed',
  int price = 5000,
  DateTime? date,
}) {
  return BookingRecord(
    id: id,
    userId: userId,
    customerName: name,
    customerEmail: email,
    packageId: 'p',
    packageName: 'Classic Moments',
    duration: '2 hours',
    price: price,
    date: date ?? DateTime(2026, 10, 1),
    time: '2:00 PM',
    guests: 20,
    receiptFileName: '',
    receiptUrl: '',
    status: status,
    createdAt: DateTime(2026, 9, 1),
  );
}

FeedbackRecord review(String userId, int rating) => FeedbackRecord(
      id: 'f$userId$rating',
      bookingId: 'b1',
      userId: userId,
      customerName: 'x',
      packageName: 'Classic Moments',
      rating: rating,
      comment: '',
      createdAt: DateTime(2026, 10, 2),
    );

void main() {
  test('one entry per app account, rolled up across bookings', () {
    final list = groupCustomers([
      booking(id: 'a', userId: 'u1', name: 'Juan'),
      booking(id: 'b', userId: 'u1', name: 'Juan', date: DateTime(2026, 11, 1)),
      booking(id: 'c', userId: 'u2', name: 'Ana'),
    ], const []);
    expect(list, hasLength(2));
    final juan = list.firstWhere((c) => c.name == 'Juan');
    expect(juan.bookings, hasLength(2));
    expect(juan.activeBookingCount, 2);
    expect(juan.lastBookingDate, DateTime(2026, 11, 1));
  });

  test('unpaid slot holds are not customers', () {
    final list = groupCustomers([booking(userId: 'u1', name: 'Juan', status: 'awaiting_receipt')], const []);
    expect(list, isEmpty);
  });

  test('walk-ins with the same email merge into one customer', () {
    final list = groupCustomers([
      booking(id: 'a', name: 'Pedro', email: 'Pedro@x.com'),
      booking(id: 'b', name: 'Pedro', email: 'pedro@x.com'),
    ], const []);
    expect(list, hasLength(1));
    expect(list.single.userIds, isEmpty);
  });

  test('totalSpent counts only confirmed/completed bookings', () {
    final list = groupCustomers([
      booking(id: 'a', userId: 'u1', name: 'Juan', price: 5000),
      booking(id: 'b', userId: 'u1', name: 'Juan', price: 3000, status: 'completed'),
      booking(id: 'c', userId: 'u1', name: 'Juan', price: 9000, status: 'cancelled'),
    ], const []);
    expect(list.single.totalSpent, 8000);
    expect(list.single.activeBookingCount, 2);
  });

  test('average rating comes from that customer\'s reviews', () {
    final list = groupCustomers([booking(userId: 'u1', name: 'Juan')], [review('u1', 5), review('u1', 3), review('other', 1)]);
    expect(list.single.avgRating, 4.0);
  });

  test('nameless customers get a placeholder', () {
    final list = groupCustomers([booking(userId: 'u1')], const []);
    expect(list.single.name, 'Unnamed customer');
  });

  test('isBlockedIn matches any of the customer\'s account ids', () {
    final c = groupCustomers([booking(userId: 'u1', name: 'Juan')], const []).single;
    final blocked = {'u1': BlockedUser(userId: 'u1', name: 'Juan', reason: '', blockedAt: DateTime(2026, 10, 1))};
    expect(c.isBlockedIn(blocked), isTrue);
    expect(c.isBlockedIn(const {}), isFalse);
  });
  registeredAccountTests();
}

void registeredAccountTests() {
  test('a newly registered account with no bookings still shows up', () {
    final list = groupCustomers(const [], const [], accounts: [
      RegisteredAccount(uid: 'u9', name: 'Maria Santos', email: 'maria@mail.com', contact: '09171234567', createdAt: DateTime.now()),
    ]);
    expect(list, hasLength(1));
    expect(list.single.name, 'Maria Santos');
    expect(list.single.userIds, {'u9'});
    expect(list.single.isNewAccount, isTrue);
    expect(list.single.activeBookingCount, 0);
  });

  test('an account merges with the customer who already booked', () {
    final list = groupCustomers(
      [booking(userId: 'u1', name: 'Juan', email: 'juan@mail.com')],
      const [],
      accounts: [RegisteredAccount(uid: 'u1', name: 'Juan Dela Cruz', email: 'juan@mail.com', contact: '', createdAt: DateTime(2026, 1, 1))],
    );
    expect(list, hasLength(1));
    expect(list.single.activeBookingCount, 1);
    expect(list.single.isNewAccount, isFalse);
  });
}
