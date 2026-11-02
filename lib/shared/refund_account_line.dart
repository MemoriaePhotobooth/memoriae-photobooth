import 'top_toast.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows the GCash account a customer saved under Profile → Payment
/// Methods, so whoever is sending a pending refund (Staff or Admin) does
/// not have to ask for it. Reads `users/{userId}`, which Staff and Admin
/// are allowed to read (see firestore.rules). Renders nothing while
/// loading or if the read fails.
class RefundAccountLine extends StatelessWidget {
  const RefundAccountLine({super.key, required this.userId});
  final String userId;

  static const Color _accent = Color(0xFF6E1B1E);

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done || snap.hasError) return const SizedBox.shrink();
        final d = snap.data?.data();
        final number = (d?['gcashNumber'] as String? ?? '').trim();
        final name = (d?['gcashName'] as String? ?? '').trim();
        final muted = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7);

        if (number.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'No GCash number saved by the customer — ask them in Messages.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 15, color: _accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Send to GCash $number${name.isNotEmpty ? ' · $name' : ''}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: number));
                  TopToast.show(context, 'GCash number copied');
                },
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.copy_rounded, size: 15, color: _accent),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
