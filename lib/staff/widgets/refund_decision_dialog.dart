import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/booking_record.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// "Refund the payment?" — shown before rejecting or cancelling a booking
/// the customer has already paid for. Returns what to do with the money,
/// or null if the person backed out (the booking is then left untouched).
///
/// Refunds are sent manually by GCash, so choosing "refund" only adds the
/// booking to the "Refunds to send" list; someone taps "Mark refunded"
/// after actually sending it.
class RefundDecisionDialog extends StatefulWidget {
  final BookingRecord booking;
  const RefundDecisionDialog({super.key, required this.booking});

  /// Whether [b] needs this question at all — only bookings with a real
  /// payment on file do.
  static bool needed(BookingRecord b) => b.hasPaymentToSettle;

  static Future<RefundDecision?> show(BuildContext context, BookingRecord b) {
    return showDialog<RefundDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RefundDecisionDialog(booking: b),
    );
  }

  @override
  State<RefundDecisionDialog> createState() => _RefundDecisionDialogState();
}

enum _Choice { refund, void_ }

class _RefundDecisionDialogState extends State<RefundDecisionDialog> {
  late final int _paid = widget.booking.paidAmount;
  late final TextEditingController _amountCtrl = TextEditingController(text: '$_paid');
  final _noteCtrl = TextEditingController();
  _Choice _choice = _Choice.refund;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  String _money(int v) => '₱${NumberFormat('#,##0').format(v)}';

  int? get _amount => int.tryParse(_amountCtrl.text.trim());

  String? get _error {
    if (_choice != _Choice.refund) return null;
    final a = _amount;
    if (a == null || a < 1) return 'Enter an amount of at least ₱1.';
    if (a > _paid) return "Can't be more than the ${_money(_paid)} paid.";
    return null;
  }

  RefundDecision _decision() {
    final note = _noteCtrl.text.trim();
    switch (_choice) {
      case _Choice.refund:
        final a = _amount ?? _paid;
        return RefundDecision(refundAmount: a, retainedAmount: _paid - a, note: note);
      case _Choice.void_:
        return RefundDecision(refundAmount: 0, retainedAmount: 0, note: note);
    }
  }

  Widget _option(_Choice value, String title, String subtitle) {
    final selected = _choice == value;
    return InkWell(
      onTap: () => setState(() => _choice = value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20, color: selected ? AppColors.accent : AppPalette.textMuted(context)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 11.5, height: 1.3, color: AppPalette.textMuted(context))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int retained = _choice == _Choice.refund ? _paid - (_amount ?? _paid).clamp(0, _paid).toInt() : 0;
    return AlertDialog(
      title: const Text("Refund the payment?"),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "The customer has already paid ${_money(_paid)}"
                "${widget.booking.isDownpayment && widget.booking.hasBalance ? ' (downpayment)' : ''}.",
                style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context)),
              ),
              const SizedBox(height: 10),
              _option(_Choice.refund, "Refund payment", "Send the payment back to the customer's GCash. You can lower the amount only if you're charging a cancellation fee."),
              if (_choice == _Choice.refund)
                Padding(
                  padding: const EdgeInsets.fromLTRB(30, 2, 0, 6),
                  child: TextField(
                    controller: _amountCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: "Refund amount",
                      prefixText: '₱ ',
                      errorText: _error,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                  ),
                ),
              _option(_Choice.void_, "No real payment received", "E.g. a fake or wrong receipt. Nothing is refunded and nothing counts as revenue."),
              const SizedBox(height: 10),
              TextField(
                controller: _noteCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: "Note (optional)",
                  hintText: "e.g. GCash number, reason for the deduction",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
              if (retained > 0) ...[
                const SizedBox(height: 10),
                Text("Business keeps: ${_money(retained)} (counts as revenue)",
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context))),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Back")),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: _error != null ? null : () => Navigator.of(context).pop(_decision()),
          child: const Text("Continue"),
        ),
      ],
    );
  }
}
