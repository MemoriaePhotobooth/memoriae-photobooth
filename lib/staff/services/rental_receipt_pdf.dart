import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/camera_rental_record.dart';

/// Printable / saveable receipt for a walk-in camera rental. Includes the
/// rental terms and a signature line, so the shop has something the
/// customer actually agreed to when the camera left the counter.
class RentalReceiptPdf {
  RentalReceiptPdf._();

  static const PdfColor _maroon = PdfColor.fromInt(0xFF6E1B1E);
  static const PdfColor _grey = PdfColor.fromInt(0xFF6B6B6B);
  static const PdfColor _line = PdfColor.fromInt(0xFFDDDDDD);

  /// Short receipt number taken from the end of the rental's document id.
  static String receiptNo(CameraRentalRecord r) {
    final id = r.id;
    final tail = id.length <= 6 ? id : id.substring(id.length - 6);
    return 'R-${tail.toUpperCase()}';
  }

  /// Opens the system print / save-as-PDF dialog for [r]'s receipt.
  static Future<void> printReceipt(CameraRentalRecord r) async {
    final bytes = await build(r);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: receiptNo(r));
  }

  static Future<Uint8List> build(CameraRentalRecord r) async {
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
    final stamp = DateFormat('MMM d, yyyy h:mm a');

    final doc = pw.Document(
      theme: hasPeso ? pw.ThemeData.withFont(base: regular, bold: bold) : null,
      title: 'Rental receipt ${receiptNo(r)}',
    );

    pw.Widget label(String t) => pw.Text(t, style: const pw.TextStyle(fontSize: 9, color: _grey, letterSpacing: 1));
    pw.Widget row(String l, String v, {bool strong = false, bool muted = false}) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Text(
                  l,
                  style: pw.TextStyle(fontSize: 11, color: muted ? _grey : PdfColors.black, fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal),
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Text(v, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        );
    pw.Widget divider() => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Divider(color: _line, thickness: 0.8, height: 1),
        );

    final fee = r.totalPrice;
    final collected = fee + r.deposit;
    final received = r.amountReceived;
    final change = (r.paymentMethod == 'cash' && received != null) ? received - collected : null;
    final hourlyLate = (r.dailyRate / 24).ceil();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('MEMORIAE PHOTOBOOTH', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _maroon)),
            pw.SizedBox(height: 2),
            pw.Text('Camera rental receipt', style: const pw.TextStyle(fontSize: 11, color: _grey)),
            divider(),
            row('Receipt no.', receiptNo(r)),
            row('Issued', stamp.format(r.rentedAt)),
            if (r.staffEmail.isNotEmpty) row('Served by', r.staffEmail, muted: true),
            divider(),
            label('CUSTOMER'),
            pw.SizedBox(height: 4),
            row('Name', r.customerName.isNotEmpty ? r.customerName : '—'),
            row('Contact', r.customerPhone.isNotEmpty ? r.customerPhone : '—'),
            if (r.idType.isNotEmpty) row('ID left with shop', r.idType),
            if (r.hasCoMaker) ...[
              divider(),
              label('CO-MAKER (BACKUP CONTACT)'),
              pw.SizedBox(height: 4),
              row('Name', r.coMakerName.isNotEmpty ? r.coMakerName : '—'),
              row('Contact', r.coMakerPhone.isNotEmpty ? r.coMakerPhone : '—'),
              if (r.coMakerRelationship.trim().isNotEmpty) row('Relationship', r.coMakerRelationship.trim()),
            ],
            divider(),
            label('RENTAL'),
            pw.SizedBox(height: 4),
            row('Camera', r.cameraName),
            row('Out', stamp.format(r.rentedAt)),
            row('Due back', stamp.format(r.dueAt), strong: true),
            if (r.conditionNote.trim().isNotEmpty) row('Condition / items', r.conditionNote.trim(), muted: true),
            divider(),
            row('Rental fee', money(fee)),
            if (r.deposit > 0) row('Deposit (refundable)', money(r.deposit)),
            row('Total collected', money(collected), strong: true),
            if (r.paymentMethod.isNotEmpty) row('Paid by', r.paymentMethod == 'gcash' ? 'GCash' : 'Cash', muted: true),
            if (change != null && change > 0) row('Change', money(change), muted: true),
            divider(),
            pw.Text(
              'Late returns are charged ${money(hourlyLate)} per hour. Damage or missing items are charged separately. '
              'The deposit is returned after the camera is checked in, less any fees. '
              'The co-maker may be contacted if the customer cannot be reached.',
              style: const pw.TextStyle(fontSize: 8.5, color: _grey, lineSpacing: 2),
            ),
            pw.Spacer(),
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(height: 0.8, color: PdfColors.black),
                      pw.SizedBox(height: 3),
                      pw.Text('Customer signature', style: const pw.TextStyle(fontSize: 8.5, color: _grey)),
                    ],
                  ),
                ),
                pw.SizedBox(width: 28),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(height: 0.8, color: PdfColors.black),
                      pw.SizedBox(height: 3),
                      pw.Text('Staff', style: const pw.TextStyle(fontSize: 8.5, color: _grey)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }
}