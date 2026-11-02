import 'package:flutter_test/flutter_test.dart';
import 'package:memoriae_photobooth/shared/thread_read.dart';

void main() {
  final sent = DateTime(2026, 10, 17, 10);

  test('customer message with no read mark is unread', () {
    expect(ThreadReadStatus.isUnread(fromCustomer: true, sentAt: sent, readAt: null), isTrue);
  });

  test('message sent before the thread was opened is read', () {
    expect(
      ThreadReadStatus.isUnread(fromCustomer: true, sentAt: sent, readAt: sent.add(const Duration(minutes: 5))),
      isFalse,
    );
  });

  test('message sent after the last open is unread again', () {
    expect(
      ThreadReadStatus.isUnread(fromCustomer: true, sentAt: sent, readAt: sent.subtract(const Duration(minutes: 5))),
      isTrue,
    );
  });

  test('our own (staff) messages are never unread', () {
    expect(ThreadReadStatus.isUnread(fromCustomer: false, sentAt: sent, readAt: null), isFalse);
  });
}
