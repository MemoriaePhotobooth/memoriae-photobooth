import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';

/// "Mark refund as sent?" — asks for the GCash reference number of the
/// transfer, so there is proof of payment on file if the customer ever
/// disputes it. Returns the reference, or null if the person backed out.
class RefundSentDialog extends StatefulWidget {
  final int amount;
  const RefundSentDialog({super.key, required this.amount});

  static Future<String?> show(BuildContext context, {required int amount}) {
    return showDialog<String>(
      context: context,
      builder: (_) => RefundSentDialog(amount: amount),
    );
  }

  @override
  State<RefundSentDialog> createState() => _RefundSentDialogState();
}

class _RefundSentDialogState extends State<RefundSentDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final ref = _ctrl.text.trim();
    // GCash reference numbers are 13 digits; allow a little slack.
    if (ref.length < 6) {
      setState(() => _error = "Enter the GCash reference number of the transfer.");
      return;
    }
    Navigator.of(context).pop(ref);
  }

  @override
  Widget build(BuildContext context) {
    final peso = "₱${NumberFormat('#,##0').format(widget.amount)}";
    return AlertDialog(
      title: const Text("Mark refund as sent?"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Confirm you've already sent $peso back to the customer by GCash.", style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLength: 30,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: "GCash reference no.",
              helperText: "Kept as proof of payment",
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Not yet")),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: _submit,
          child: const Text("Yes, sent"),
        ),
      ],
    );
  }
}
