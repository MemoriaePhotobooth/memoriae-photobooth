import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'payment_info.dart';

/// Builds the printable / saveable PDF version of a booking invoice.
/// Same data and layout as `BookingInvoiceScreen`, but laid out for paper.
class InvoicePdf {
  InvoicePdf._();

  static const PdfColor _maroon = PdfColor.fromInt(0xFF6E1B1E);
  static const PdfColor _grey = PdfColor.fromInt(0xFF6B6B6B);
  static const PdfColor _line = PdfColor.fromInt(0xFFDDDDDD);

  static DateTime? _ts(Map<String, dynamic> b, String key) {
    final v = b[key];
    return v is Timestamp ? v.toDate() : null;
  }

  static Future<Uint8List> build(
    Map<String, dynamic> booking, {
    required String invoiceNo,
    required String stampText,
  }) async {
    // Roboto has the peso sign (₱); the PDF default font doesn't. If the
    // font can't be fetched (offline), fall back to the default font and
    // write "PHP" instead so nothing prints as a blank box.
    pw.Font? regular;
    pw.Font? bold;
    try {
      regular = await PdfGoogleFonts.robotoRegular();
      bold = await PdfGoogleFonts.robotoBold();
    } catch (_) {}
    final hasPeso = regular != null && bold != null;
    String money(int v) => '${hasPeso ? '₱' : 'PHP '}${NumberFormat('#,##0').format(v)}';

    final price = (booking['price'] as num?)?.toInt() ?? 0;
    final addOnsPrice = (booking['addOnsPrice'] as num?)?.toInt() ?? 0;
    final addOnNames = (booking['addOnNames'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    final total = price + addOnsPrice;
    final pay = PaymentInfo.fromBooking(booking);
    final addOnItems = (booking['addOns'] as List?)
            ?.whereType<Map>()
            .map((m) => (name: '${m['name'] ?? ''}', price: (m['price'] as num?)?.toInt() ?? 0))
            .toList() ??
        const <({String name, int price})>[];
    final date = _ts(booking, 'date');
    final issued = _ts(booking, 'receiptSubmittedAt') ?? _ts(booking, 'createdAt');
    final location = (booking['location'] as String? ?? '').trim();
    final staff = (booking['acceptedByStaffName'] as String? ?? '').trim();

    final doc = pw.Document(
      theme: hasPeso ? pw.ThemeData.withFont(base: regular, bold: bold) : null,
      title: 'Invoice $invoiceNo',
    );

    pw.Widget label(String t) =>
        pw.Text(t, style: const pw.TextStyle(fontSize: 9, color: _grey, letterSpacing: 1));
    pw.Widget row(String l, String r, {bool muted = false}) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: pw.Text(l, style: pw.TextStyle(fontSize: 11, color: muted ? _grey : PdfColors.black))),
            pw.SizedBox(width: 12),
            pw.Text(r, style: const pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          ],
        );

    final addOnLines = <pw.Widget>[];
    if (addOnItems.isNotEmpty) {
      for (final a in addOnItems) {
        addOnLines.add(pw.SizedBox(height: 6));
        addOnLines.add(row('+ ${a.name}', money(a.price), muted: true));
      }
    } else if (addOnNames.isNotEmpty) {
      addOnLines.add(pw.SizedBox(height: 6));
      addOnLines.add(row('Add-ons: ${addOnNames.join(', ')}', money(addOnsPrice), muted: true));
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(20),
              decoration: const pw.BoxDecoration(color: _maroon, borderRadius: pw.BorderRadius.all(pw.Radius.circular(10))),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('MEMORIAE PHOTOBOOTH',
                      style: const pw.TextStyle(color: PdfColors.white, fontSize: 12, fontWeight: pw.FontWeight.bold, letterSpacing: 1.4)),
                  pw.SizedBox(height: 14),
                  pw.Text('INVOICE', style: const pw.TextStyle(color: PdfColors.white, fontSize: 10, letterSpacing: 1.2)),
                  pw.SizedBox(height: 2),
                  pw.Text(invoiceNo, style: const pw.TextStyle(color: PdfColors.white, fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  if (issued != null) ...[
                    pw.SizedBox(height: 4),
                    pw.Text('Issued ${DateFormat('MMM d, yyyy · h:mm a').format(issued)}',
                        style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 18),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _maroon, width: 1.2),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Text(stampText,
                  style: const pw.TextStyle(color: _maroon, fontSize: 10, fontWeight: pw.FontWeight.bold, letterSpacing: 0.8)),
            ),
            pw.SizedBox(height: 18),
            label('BILLED TO'),
            pw.SizedBox(height: 4),
            pw.Text(booking['customerName'] as String? ?? 'Customer',
                style: const pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 16),
            label('EVENT'),
            pw.SizedBox(height: 4),
            pw.Text(date != null ? DateFormat('EEEE, MMM d, yyyy').format(date) : '—', style: const pw.TextStyle(fontSize: 11)),
            pw.Text('${booking['time'] ?? ''} · ${booking['duration'] ?? ''}', style: const pw.TextStyle(fontSize: 11)),
            if (location.isNotEmpty) pw.Text(location, style: const pw.TextStyle(fontSize: 11)),
            if (booking['guests'] != null) pw.Text('${booking['guests']} guests', style: const pw.TextStyle(fontSize: 11)),
            pw.SizedBox(height: 14),
            pw.Divider(color: _line),
            pw.SizedBox(height: 8),
            label('DETAILS'),
            pw.SizedBox(height: 8),
            row(booking['packageName'] as String? ?? 'Package', money(price)),
            ...addOnLines,
            pw.SizedBox(height: 10),
            pw.Divider(color: _line),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('TOTAL', style: const pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.Text(money(total), style: const pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: _maroon)),
              ],
            ),
            if (pay.isSplit) ...[
              pw.SizedBox(height: 10),
              row(pay.hasBalance ? 'Downpayment received' : 'Paid', money(pay.paid)),
              if (pay.hasBalance) ...[
                pw.SizedBox(height: 6),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('BALANCE DUE', style: const pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _maroon)),
                    pw.Text(money(pay.balance), style: const pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _maroon)),
                  ],
                ),
              ],
            ],
            pw.SizedBox(height: 18),
            pw.Text(
              pay.hasBalance
                  ? 'Downpayment received. Please settle the remaining ${money(pay.balance)} on the event day.'
                  : staff.isEmpty
                      ? 'Payment proof received. Our team will confirm your booking shortly.'
                      : 'Payment confirmed by $staff.',
              style: const pw.TextStyle(fontSize: 10, color: _grey),
            ),
            pw.Spacer(),
            pw.Center(
              child: pw.Text('Thank you for booking with Memoriae!', style: const pw.TextStyle(fontSize: 10, color: _grey)),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }
}
