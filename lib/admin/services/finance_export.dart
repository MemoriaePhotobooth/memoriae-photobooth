import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/booking_record.dart';
import '../models/pos_transaction_record.dart';
import '../models/shift_closing_record.dart';

/// Everything the Financial Logs page shows for one period, bundled so it
/// can be turned into a CSV or a PDF for accounting / month-end closing.
class FinanceReport {
  final String periodLabel;
  final int totalRevenue;
  final int onlineRevenue;
  final int posRevenue;
  final int cashRevenue;
  final int gcashRevenue;
  final List<BookingRecord> bookings; // bookings with a receipt on file
  final List<PosTransactionRecord> sales;
  final List<ShiftClosingRecord> closings;

  const FinanceReport({
    required this.periodLabel,
    required this.totalRevenue,
    required this.onlineRevenue,
    required this.posRevenue,
    required this.cashRevenue,
    required this.gcashRevenue,
    required this.bookings,
    required this.sales,
    required this.closings,
  });
}

/// Builds the CSV text and the PDF bytes for a [FinanceReport].
class FinanceExport {
  FinanceExport._();

  static final DateFormat _dateTime = DateFormat('yyyy-MM-dd HH:mm');
  static final DateFormat _date = DateFormat('yyyy-MM-dd');

  /// File-name friendly stamp, e.g. `2026-10-06`.
  static String fileStamp() => _date.format(DateTime.now());

  // ---------------------------------------------------------------- CSV

  static String _cell(Object? value) {
    final text = '${value ?? ''}';
    if (text.contains(',') || text.contains('"') || text.contains('\n') || text.contains('\r')) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  static String _row(List<Object?> cells) => cells.map(_cell).join(',');

  static String _itemsSummary(PosTransactionRecord s) =>
      s.items.map((i) => '${i.quantity}x ${i.name}').join('; ');

  /// Plain CSV (opens in Excel / Google Sheets). The three tables are
  /// stacked in one file, each under its own title row.
  static String buildCsv(FinanceReport r) {
    final lines = <String>[
      _row(['Memoriae Photobooth - Financial Report']),
      _row(['Period', r.periodLabel]),
      _row(['Generated', _dateTime.format(DateTime.now())]),
      '',
      _row(['SUMMARY (PHP)']),
      _row(['Total revenue', r.totalRevenue]),
      _row(['Online bookings', r.onlineRevenue]),
      _row(['Counter sales (POS)', r.posRevenue]),
      _row(['POS - cash', r.cashRevenue]),
      _row(['POS - GCash', r.gcashRevenue]),
      '',
      _row(['BOOKING PAYMENTS']),
      _row(['Ref', 'Created', 'Customer', 'Package', 'Event date', 'Status', 'Total', 'Paid', 'Balance due', 'Payment option', 'Refund amount', 'Retained amount']),
      for (final b in r.bookings)
        _row([
          b.bookingRef,
          b.createdAt == null ? '' : _dateTime.format(b.createdAt!),
          b.customerName,
          b.packageName,
          _date.format(b.date),
          b.status,
          b.totalPrice,
          b.paidAmount,
          b.balanceDue,
          b.paymentOption ?? '',
          b.refundAmount,
          b.retainedAmount,
        ]),
      '',
      _row(['COUNTER SALES (POS)']),
      _row(['Date', 'Staff', 'Items', 'Payment method', 'Total', 'Amount received', 'Change', 'Reference / note']),
      for (final s in r.sales)
        _row([
          _dateTime.format(s.createdAt),
          s.staffEmail,
          _itemsSummary(s),
          s.paymentMethod,
          s.total,
          s.amountReceived ?? '',
          s.change ?? '',
          s.referenceNote,
        ]),
      '',
      _row(['SHIFT CLOSE-OUTS']),
      _row(['Closed at', 'Staff', 'Sales count', 'Cash sales', 'GCash sales', 'Opening float', 'Expected cash', 'Counted cash', 'Variance', 'Notes']),
      for (final c in r.closings)
        _row([
          _dateTime.format(c.closedAt),
          c.staffEmail,
          c.salesCount,
          c.cashSales,
          c.gcashSales,
          c.openingFloat,
          c.expectedCash,
          c.countedCash,
          c.variance,
          c.notes,
        ]),
    ];
    return '${lines.join('\r\n')}\r\n';
  }

  // ---------------------------------------------------------------- PDF

  static const PdfColor _maroon = PdfColor.fromInt(0xFF6E1B1E);
  static const PdfColor _grey = PdfColor.fromInt(0xFF6B6B6B);

  static Future<Uint8List> buildPdf(FinanceReport r) async {
    // Roboto has the peso sign; the PDF default font doesn't. Offline, fall
    // back to the default font and write "PHP" so nothing prints as a box.
    pw.Font? regular;
    pw.Font? bold;
    try {
      regular = await PdfGoogleFonts.robotoRegular();
      bold = await PdfGoogleFonts.robotoBold();
    } catch (_) {}
    final hasPeso = regular != null && bold != null;
    String money(int v) => '${hasPeso ? '₱' : 'PHP '}${NumberFormat('#,##0').format(v)}';

    final doc = pw.Document(
      theme: hasPeso ? pw.ThemeData.withFont(base: regular, bold: bold) : null,
      title: 'Financial Report - ${r.periodLabel}',
    );

    pw.Widget heading(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
          child: pw.Text(t, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _maroon)),
        );

    pw.Widget table(List<String> headers, List<List<String>> rows, {Map<int, pw.Alignment>? align}) {
      if (rows.isEmpty) {
        return pw.Text('None in this period.', style: const pw.TextStyle(fontSize: 9, color: _grey));
      }
      return pw.TableHelper.fromTextArray(
        headers: headers,
        data: rows,
        headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: _maroon),
        cellStyle: const pw.TextStyle(fontSize: 8),
        cellAlignments: align,
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        border: pw.TableBorder(horizontalInside: const pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
      );
    }

    pw.Widget summaryRow(String label, int amount, {bool strong = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(label, style: pw.TextStyle(fontSize: 10, fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal)),
              pw.Text(money(amount), style: pw.TextStyle(fontSize: 10, fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal)),
            ],
          ),
        );

    const right = pw.Alignment.centerRight;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _grey)),
        ),
        build: (ctx) => [
          pw.Text('Memoriae Photobooth', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _maroon)),
          pw.SizedBox(height: 2),
          pw.Text('Financial Report', style: const pw.TextStyle(fontSize: 12)),
          pw.Text('${r.periodLabel}  |  Generated ${_dateTime.format(DateTime.now())}', style: const pw.TextStyle(fontSize: 9, color: _grey)),
          heading('Summary'),
          pw.SizedBox(
            width: 260,
            child: pw.Column(children: [
              summaryRow('Total revenue', r.totalRevenue, strong: true),
              summaryRow('Online bookings', r.onlineRevenue),
              summaryRow('Counter sales (POS)', r.posRevenue),
              summaryRow('  POS - cash', r.cashRevenue),
              summaryRow('  POS - GCash', r.gcashRevenue),
            ]),
          ),
          heading('Booking payments (${r.bookings.length})'),
          table(
            ['Ref', 'Created', 'Customer', 'Package', 'Event date', 'Status', 'Total', 'Paid', 'Balance'],
            [
              for (final b in r.bookings)
                [
                  b.bookingRef,
                  b.createdAt == null ? '' : _dateTime.format(b.createdAt!),
                  b.customerName,
                  b.packageName,
                  _date.format(b.date),
                  b.status,
                  money(b.totalPrice),
                  money(b.paidAmount),
                  money(b.balanceDue),
                ],
            ],
            align: {6: right, 7: right, 8: right},
          ),
          heading('Counter sales - POS (${r.sales.length})'),
          table(
            ['Date', 'Staff', 'Items', 'Method', 'Total', 'Received', 'Change'],
            [
              for (final s in r.sales)
                [
                  _dateTime.format(s.createdAt),
                  s.staffEmail,
                  _itemsSummary(s),
                  s.paymentMethod,
                  money(s.total),
                  s.amountReceived == null ? '' : money(s.amountReceived!),
                  s.change == null ? '' : money(s.change!),
                ],
            ],
            align: {4: right, 5: right, 6: right},
          ),
          heading('Shift close-outs (${r.closings.length})'),
          table(
            ['Closed at', 'Staff', 'Sales', 'Cash sales', 'GCash sales', 'Float', 'Expected', 'Counted', 'Variance'],
            [
              for (final c in r.closings)
                [
                  _dateTime.format(c.closedAt),
                  c.staffEmail,
                  '${c.salesCount}',
                  money(c.cashSales),
                  money(c.gcashSales),
                  money(c.openingFloat),
                  money(c.expectedCash),
                  money(c.countedCash),
                  money(c.variance),
                ],
            ],
            align: {2: right, 3: right, 4: right, 5: right, 6: right, 7: right, 8: right},
          ),
        ],
      ),
    );

    return doc.save();
  }
}