import 'package:flutter_test/flutter_test.dart';
import 'package:memoriae_photobooth/user/services/receipt_ocr.dart';

void main() {
  const sample = '''
Express Send
Sent via GCash
JO*** D.
+63 917 123 4567
Amount 500.00
Total Amount Sent ₱500.00
Ref No. 7034 123 456789
Oct 10, 2026 3:45 PM
''';

  test('parses amount, reference and recipient from a GCash receipt', () {
    final r = ReceiptOcr.parse(sample);
    expect(r.looksLikeGcash, isTrue);
    expect(r.amount, 500.0);
    expect(r.referenceNo, '7034123456789');
    expect(r.referenceDisplay, '7034 123 456789');
    expect(r.recipientNumber, '09171234567');
  });

  test('handles thousands separators and a misread peso sign', () {
    final r = ReceiptOcr.parse('GCash\nTotal Amount Sent P1,250.00\nRef No. 1111 222 333333');
    expect(r.amount, 1250.0);
  });

  test('flags non-GCash images', () {
    final r = ReceiptOcr.parse('hello world');
    expect(r.looksLikeGcash, isFalse);
    expect(r.foundAnything, isFalse);
  });

  test('normalizes PH numbers', () {
    expect(ReceiptOcr.normalizeNumber('+63 917 123 4567'), '09171234567');
    expect(ReceiptOcr.normalizeNumber('0917-123-4567'), '09171234567');
  });

  group('verify (proof the payment reached the studio)', () {
    const number = '09754269253';
    const name = 'Mary Lyn T. Marbella';
    ReceiptVerdict check(String text, {num? due = 500}) =>
        ReceiptOcr.verify(ReceiptOcr.parse(text), amountDue: due, accountNumber: number, accountName: name);

    test('accepts a GCash receipt sent to the studio number for the right amount', () {
      final v = check('Express Send\nSent via GCash\n+63 975 426 9253\nTotal Amount Sent ₱500.00\nRef No. 7034 123 456789');
      expect(v.accepted, isTrue);
    });

    test('accepts when the app masks the middle of the number', () {
      final v = check('GCash\n0975 *** 9253\nTotal Amount Sent ₱500.00\nRef No. 7034 123 456789');
      expect(v.accepted, isTrue);
    });

    test('accepts a masked account name when the number is not shown', () {
      final v = check('GCash\nMA** LY* T. MA*****A\nTotal Amount Sent ₱500.00\nRef No. 7034 123 456789');
      expect(v.accepted, isTrue);
    });

    test('accepts another wallet or bank as long as it went to the studio account', () {
      final v = check('Maya\nTransfer successful\n0975 426 9253\nAmount ₱500.00\nRef 1234 567 890123');
      expect(v.accepted, isTrue);
    });

    test('rejects an image that is not a payment receipt', () {
      expect(check('hello world').accepted, isFalse);
    });

    test('rejects a receipt sent to a different account', () {
      final v = check('GCash\n+63 917 123 4567\nTotal Amount Sent ₱500.00\nRef No. 7034 123 456789');
      expect(v.accepted, isFalse);
    });

    test('rejects an amount lower than what is due, allows a higher one', () {
      const base = 'GCash\n0975 426 9253\nRef No. 7034 123 456789\n';
      expect(check('${base}Total Amount Sent ₱300.00').accepted, isFalse);
      expect(check('${base}Total Amount Sent ₱800.00').accepted, isTrue);
    });
  });
}
