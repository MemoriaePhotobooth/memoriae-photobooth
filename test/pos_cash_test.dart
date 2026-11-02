import 'package:flutter_test/flutter_test.dart';
import 'package:memoriae_photobooth/staff/services/pos_cash.dart';

void main() {
  test('no cash typed shows neither change nor short', () {
    final r = PosCash.compare(3999, null);
    expect(r.status, CashStatus.none);
    expect(r.amount, 0);
  });

  test('exact cash gives zero change', () {
    final r = PosCash.compare(3999, 3999);
    expect(r.status, CashStatus.change);
    expect(r.amount, 0);
  });

  test('overpaying gives the change back', () {
    final r = PosCash.compare(3999, 4000);
    expect(r.status, CashStatus.change);
    expect(r.amount, 1);
  });

  test('underpaying shows how much is still missing', () {
    final r = PosCash.compare(3999, 3000);
    expect(r.status, CashStatus.short);
    expect(r.amount, 999);
  });
}
