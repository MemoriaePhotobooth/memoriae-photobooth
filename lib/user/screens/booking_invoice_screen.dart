import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../models/booth_package.dart';
import '../services/invoice_pdf.dart';
import '../services/payment_info.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/circle_back_button.dart';
import '../widgets/app_toast.dart';

/// Online invoice / e-receipt for a single booking. Built entirely from
/// the booking document the My Bookings list already streams, so it needs
/// no extra Firestore reads and updates its status stamp live.
class BookingInvoiceScreen extends StatelessWidget {
  final Map<String, dynamic> booking;
  const BookingInvoiceScreen({super.key, required this.booking});

  /// Invoices exist once a payment receipt has been sent in.
  static bool isAvailable(String status) =>
      status == 'pending_confirmation' || status == 'confirmed' || status == 'completed';

  DateTime? _ts(String key) {
    final v = booking[key];
    return v is Timestamp ? v.toDate() : null;
  }

  String get _invoiceNo {
    final saved = (booking['invoiceNo'] as String? ?? '').trim();
    if (saved.isNotEmpty) return saved; // running number assigned on receipt upload
    final created = _ts('createdAt') ?? _ts('date') ?? DateTime.now();
    final id = (booking['id'] as String? ?? '').toUpperCase();
    final tail = id.length >= 5 ? id.substring(0, 5) : id.padRight(5, '0');
    return 'MEM-${DateFormat('yyyyMMdd').format(created)}-$tail';
  }

  (String, Color) get _stamp {
    final pay = PaymentInfo.fromBooking(booking);
    switch (booking['status'] as String? ?? '') {
      case 'confirmed':
        if (pay.hasBalance) return ('RESERVED · BALANCE DUE', const Color(0xFFE08A00));
        return ('PAID · CONFIRMED', const Color(0xFF2E7D32));
      case 'completed':
        if (pay.hasBalance) return ('COMPLETED · BALANCE DUE', const Color(0xFFE08A00));
        return ('PAID · COMPLETED', const Color(0xFF2E7D32));
      default:
        return ('PAYMENT UNDER REVIEW', const Color(0xFFE08A00));
    }
  }

  Future<void> _print(BuildContext context) async {
    try {
      await Printing.layoutPdf(
        name: 'Invoice $_invoiceNo',
        onLayout: (_) => InvoicePdf.build(booking, invoiceNo: _invoiceNo, stampText: _stamp.$1),
      );
    } catch (_) {
      if (!context.mounted) return;
      AppToast.show(context, "Couldn't open the print dialog. Try again.");
    }
  }

  Future<void> _savePdf(BuildContext context) async {
    try {
      final bytes = await InvoicePdf.build(booking, invoiceNo: _invoiceNo, stampText: _stamp.$1);
      await Printing.sharePdf(bytes: bytes, filename: '$_invoiceNo.pdf');
    } catch (_) {
      if (!context.mounted) return;
      AppToast.show(context, "Couldn't create the PDF. Try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
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
    final addOnLines = <Widget>[];
    if (addOnItems.isNotEmpty) {
      for (final a in addOnItems) {
        addOnLines.add(const SizedBox(height: 8));
        addOnLines.add(_line(context, "+ ${a.name}", formatPeso(a.price), muted: true));
      }
    } else if (addOnNames.isNotEmpty) {
      addOnLines.add(const SizedBox(height: 8));
      addOnLines.add(_line(context, "Add-ons: ${addOnNames.join(', ')}", formatPeso(addOnsPrice), muted: true));
    }
    final date = _ts('date');
    final issued = _ts('receiptSubmittedAt') ?? _ts('createdAt');
    final location = (booking['location'] as String? ?? '').trim();
    final staff = (booking['acceptedByStaffName'] as String? ?? '').trim();
    final (stampText, stampColor) = _stamp;

    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        leading: const CircleBackButton.appBar(),
        leadingWidth: CircleBackButton.appBarLeadingWidth,
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: const Text("Invoice"),
        actions: [
          IconButton(
            tooltip: "Copy invoice",
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(
                text: "Memoriae Photobooth — Invoice $_invoiceNo\n"
                    "${booking['packageName'] ?? ''}"
                    "${date != null ? ' · ${DateFormat('MMM d, yyyy').format(date)} ${booking['time'] ?? ''}' : ''}\n"
                    "Total: ${formatPeso(total)}"
                    "${pay.hasBalance ? '\nBalance due: ${formatPeso(pay.balance)}' : ''}",
              ));
              AppToast.show(context, "Invoice details copied");
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            child: Container(
              decoration: BoxDecoration(
                color: AppPalette.cardBg(context),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppPalette.divider(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header band
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF8A2429), Color(0xFF3A1214)],
                      ),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("MEMORIAE PHOTOBOOTH",
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.4)),
                        const SizedBox(height: 14),
                        Text("INVOICE", style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11, letterSpacing: 1.2)),
                        const SizedBox(height: 2),
                        Text(_invoiceNo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                        if (issued != null) ...[
                          const SizedBox(height: 4),
                          Text("Issued ${DateFormat('MMM d, yyyy · h:mm a').format(issued)}",
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(color: stampColor, width: 1.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(stampText,
                              style: TextStyle(color: stampColor, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.8)),
                        ),
                        const SizedBox(height: 20),
                        _label(context, "BILLED TO"),
                        const SizedBox(height: 4),
                        Text(booking['customerName'] as String? ?? 'Customer',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                        const SizedBox(height: 18),
                        _label(context, "EVENT"),
                        const SizedBox(height: 6),
                        _info(context, Icons.event, date != null ? DateFormat('EEEE, MMM d, yyyy').format(date) : '—'),
                        _info(context, Icons.access_time, "${booking['time'] ?? ''} · ${booking['duration'] ?? ''}"),
                        if (location.isNotEmpty) _info(context, Icons.place_outlined, location),
                        if (booking['guests'] != null) _info(context, Icons.people_outline, "${booking['guests']} guests"),
                        Divider(height: 32, color: AppPalette.divider(context)),
                        _label(context, "DETAILS"),
                        const SizedBox(height: 10),
                        _line(context, booking['packageName'] as String? ?? 'Package', formatPeso(price)),
                        ...addOnLines,
                        Divider(height: 32, color: AppPalette.divider(context)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("TOTAL", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                            Text(formatPeso(total),
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.accent)),
                          ],
                        ),
                        if (pay.isSplit) ...[
                          const SizedBox(height: 12),
                          _line(context, pay.hasBalance ? "Downpayment received" : "Paid", formatPeso(pay.paid)),
                          if (pay.hasBalance) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("BALANCE DUE",
                                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFFE08A00))),
                                Text(formatPeso(pay.balance),
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFFE08A00))),
                              ],
                            ),
                          ],
                        ],
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(12)),
                          child: Text(
                            pay.hasBalance
                                ? (staff.isEmpty
                                    ? "Downpayment received. Please settle the remaining ${formatPeso(pay.balance)} on the event day."
                                    : "Downpayment confirmed by $staff. Please settle the remaining ${formatPeso(pay.balance)} on the event day.")
                                : staff.isEmpty
                                    ? "Payment proof received. Our team will confirm your booking shortly."
                                    : "Payment confirmed by $staff.",
                            style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _print(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  foregroundColor: AppColors.onAccent,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: const Icon(Icons.print_outlined, size: 18),
                                label: const Text("Print", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _savePdf(context),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.accent,
                                  side: const BorderSide(color: AppColors.accent),
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                                label: const Text("Save PDF", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Center(
                          child: Text("Thank you for booking with Memoriae!",
                              style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(BuildContext c, String t) =>
      Text(t, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppPalette.textMuted(c)));

  Widget _info(BuildContext c, IconData icon, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 15, color: AppPalette.textMuted(c)),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: TextStyle(fontSize: 13, color: AppPalette.textPrimary(c)))),
        ]),
      );

  Widget _line(BuildContext c, String l, String r, {bool muted = false}) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
              child: Text(l,
                  style: TextStyle(fontSize: 13, color: muted ? AppPalette.textSecondary(c) : AppPalette.textPrimary(c)))),
          const SizedBox(width: 12),
          Text(r, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(c))),
        ],
      );
}
