import '../../shared/top_toast.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/booking_record.dart';
import '../services/booking_repository.dart';
import '../services/refund_request_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/refund_decision_dialog.dart';
import '../../shared/refund_account_line.dart';

/// Customer refund requests waiting for a decision. Approving cancels the
/// booking through the normal refund flow (so the refund shows up in
/// "Refunds to send"); declining just records the decision.
class RefundRequestsScreen extends StatefulWidget {
  const RefundRequestsScreen({super.key});

  @override
  State<RefundRequestsScreen> createState() => _RefundRequestsScreenState();
}

class _RefundRequestsScreenState extends State<RefundRequestsScreen> {
  final Set<String> _busy = {};

  void _snack(String msg) {
    if (mounted) TopToast.show(context, msg);
  }

  Future<void> _approve(RefundRequest req, BookingRecord b) async {
    if (b.status != 'confirmed') {
      _snack("This booking is no longer confirmed.");
      return;
    }
    setState(() => _busy.add(req.id));
    try {
      RefundDecision? refund;
      if (RefundDecisionDialog.needed(b)) {
        refund = await RefundDecisionDialog.show(context, b);
        if (refund == null) return; // staff backed out
      }
      await BookingRepository.updateStatus(
        b.id,
        'cancelled',
        rejectionReason: 'Refund approved at the customer\'s request',
        refund: refund,
      );
      await RefundRequestRepository.decide(req.id, 'approved', decidedBy: FirebaseAuth.instance.currentUser?.uid);
      _snack("Refund approved for ${b.customerName.isEmpty ? 'the customer' : b.customerName}.");
    } catch (e) {
      _snack("Couldn't approve: $e");
    } finally {
      if (mounted) setState(() => _busy.remove(req.id));
    }
  }

  Future<void> _decline(RefundRequest req) async {
    final noteCtrl = TextEditingController();
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Decline this request?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("The customer will see that it was declined, with your reason."),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              maxLines: 3,
              maxLength: 200,
              decoration: const InputDecoration(
                hintText: "Reason (shown to the customer)",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Decline"),
          ),
        ],
      ),
    );
    final note = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (yes != true) return;
    setState(() => _busy.add(req.id));
    try {
      await RefundRequestRepository.decide(req.id, 'declined', decidedBy: FirebaseAuth.instance.currentUser?.uid, note: note);
      _snack("Request declined.");
    } catch (e) {
      _snack("Couldn't decline: $e");
    } finally {
      if (mounted) setState(() => _busy.remove(req.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RefundRequest>>(
      stream: RefundRequestRepository.watchOpen(),
      builder: (context, reqSnap) {
        if (reqSnap.hasError) return _message(context, "Couldn't load refund requests.");
        if (!reqSnap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accent));
        }
        return StreamBuilder<List<BookingRecord>>(
          stream: BookingRepository.watchAllBookings(),
          builder: (context, bookSnap) {
            final byId = {for (final b in bookSnap.data ?? const <BookingRecord>[]) b.id: b};
            final reqs = reqSnap.data!;
            if (reqs.isEmpty) {
              return _message(context, "No open refund requests.\nCustomers' requests will show up here.");
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              itemCount: reqs.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 2),
                    child: Text(
                      "${reqs.length} open request${reqs.length == 1 ? '' : 's'}",
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppPalette.textMuted(context)),
                    ),
                  );
                }
                final req = reqs[i - 1];
                return _card(context, req, byId[req.bookingId]);
              },
            );
          },
        );
      },
    );
  }

  Widget _card(BuildContext context, RefundRequest req, BookingRecord? b) {
    final busy = _busy.contains(req.id);
    final name = b == null
        ? 'Booking not found'
        : (b.customerName.trim().isEmpty ? 'Customer' : b.customerName.trim());
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.divider(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.accentTint(0.10),
                child: Text(name[0].toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.accent)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
                    if (b != null)
                      Text(
                        "${b.packageName} · ${DateFormat('MMM d, yyyy').format(b.date)} · ${b.time}",
                        style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
                      ),
                  ],
                ),
              ),
              if (b != null)
                Text("₱${NumberFormat('#,##0').format(b.totalPrice)}",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
            ],
          ),
          if (b != null) ...[
            const SizedBox(height: 12),
            _details(context, req, b),
          ],
          const SizedBox(height: 12),
          Text("Customer's reason",
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: AppPalette.textMuted(context))),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppPalette.surface(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              req.reason.isEmpty ? "No reason given." : req.reason,
              style: TextStyle(fontSize: 13, height: 1.4, color: AppPalette.textPrimary(context)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            req.createdAt == null ? "Just now" : "Requested ${DateFormat('MMM d, h:mm a').format(req.createdAt!)}",
            style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => _decline(req),
                  child: const Text("Decline"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                  onPressed: (busy || b == null) ? null : () => _approve(req, b),
                  child: busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text("Approve & refund"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Everything staff need to decide and to send the money: who to contact,
  /// what was booked, what was paid, and where the refund goes.
  Widget _details(BuildContext context, RefundRequest req, BookingRecord b) {
    String peso(int v) => "₱${NumberFormat('#,##0').format(v)}";
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                child: Text(label, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
              ),
              Expanded(
                child: Text(value,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context))),
              ),
            ],
          ),
        );
    final addOns = b.addOnNames.isEmpty ? '' : ' + ${b.addOnNames.join(', ')}';
    final payLabel = b.isDownpayment ? 'Downpayment' : 'Paid in full';
    final paidLine = b.isDownpayment
        ? "${peso(b.paidAmount)} paid of ${peso(b.totalPrice)}${b.balancePaid ? ' (balance collected)' : ''}"
        : peso(b.paidAmount);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      decoration: BoxDecoration(
        color: AppPalette.surface(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: FirebaseFirestore.instance.collection('users').doc(req.userId.isNotEmpty ? req.userId : b.userId).get(),
            builder: (context, snap) {
              final d = snap.data?.data();
              final contact = [
                ((d?['contactNumber'] ?? '') as String).trim(),
                ((d?['email'] ?? '') as String).trim(),
              ].where((v) => v.isNotEmpty).join(' · ');
              return row('Contact', snap.connectionState != ConnectionState.done ? '…' : (contact.isEmpty ? '—' : contact));
            },
          ),
          row('Booking', '${b.packageName}$addOns'),
          row('Event', '${DateFormat('EEE, MMM d, yyyy').format(b.date)} · ${b.time}'),
          if (b.location.trim().isNotEmpty) row('Location', b.location.trim()),
          row('Payment', '$payLabel · $paidLine'),
          if (b.receiptRefNo.isNotEmpty) row('GCash ref no.', b.receiptRefNo),
          Divider(height: 14, color: AppPalette.divider(context)),
          Text('Send the refund to',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: AppPalette.textMuted(context))),
          RefundAccountLine(userId: req.userId.isNotEmpty ? req.userId : b.userId),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _message(BuildContext context, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.undo_rounded, size: 40, color: AppPalette.textMuted(context)),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.45, color: AppPalette.textMuted(context))),
            ],
          ),
        ),
      );
}