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
import 'admin_messages_screen.dart';
import '../../shared/refund_account_line.dart';

/// Customer refund requests. The Open tab holds those waiting for a decision:
/// approving cancels the booking through the normal refund flow (so the refund
/// shows up in "Refunds to send"); declining just records the decision. The
/// Approved and Declined tabs are the history, with who/when and, for approved
/// ones, whether the money has actually been sent.
class RefundRequestsScreen extends StatefulWidget {
  const RefundRequestsScreen({super.key});

  @override
  State<RefundRequestsScreen> createState() => _RefundRequestsScreenState();
}

enum _Tab { open, approved, declined }

class _RefundRequestsScreenState extends State<RefundRequestsScreen> {
  final Set<String> _busy = {};

  String _uidOf(RefundRequest req, BookingRecord b) => req.userId.isNotEmpty ? req.userId : b.userId;

  void _openChat(String userId, String name) {
    final wide = MediaQuery.of(context).size.width >= 900;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => wide
          // Wide screens: the Messages page with this customer already selected.
          ? Scaffold(
              appBar: AppBar(title: const Text('Messages')),
              body: AdminMessagesScreen(isDesktop: true, initialUserId: userId, initialName: name),
            )
          // Phones: the single conversation, as before.
          : AdminMessageThreadScreen(userId: userId, customerName: name),
    ));
  }

  Future<bool> _hasGcash(String userId) async {
    if (userId.isEmpty) return false;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      return ((snap.data()?['gcashNumber'] as String?) ?? '').trim().isNotEmpty;
    } catch (_) {
      return true; // can't tell — don't block the approval on a failed read
    }
  }

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
      final uid = _uidOf(req, b);
      if (!await _hasGcash(uid)) {
        if (!mounted) return;
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("No GCash number saved"),
            content: const Text(
              "This customer hasn't saved a GCash number, so you won't know where to send the refund. "
              "It's best to message them for it before approving.",
              style: TextStyle(fontSize: 13),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text("Cancel")),
              TextButton(onPressed: () => Navigator.pop(ctx, 'message'), child: const Text("Message customer")),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                onPressed: () => Navigator.pop(ctx, 'approve'),
                child: const Text("Approve anyway"),
              ),
            ],
          ),
        );
        if (choice == 'message') {
          _openChat(uid, b.customerName);
          return;
        }
        if (choice != 'approve') return;
      }
      if (!mounted) return;
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
        // Closes the request in the same write as the cancellation.
        refundRequestId: req.id,
        decidedBy: FirebaseAuth.instance.currentUser?.uid,
      );
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
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: noteCtrl,
            builder: (_, v, __) => FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
              // The customer sees this reason, so it can't be blank.
              onPressed: v.text.trim().isEmpty ? null : () => Navigator.pop(ctx, true),
              child: const Text("Decline"),
            ),
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
    final muted = AppPalette.textSecondary(context);
    return DefaultTabController(
      length: _Tab.values.length,
      child: Column(
        children: [
          _centered(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(16)),
                // The default underline under TabBar is hidden: the pill is the indicator.
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: TabBar(
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: AppPalette.cardBg(context),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: AppShadows.soft,
                    ),
                    labelColor: AppColors.accent,
                    unselectedLabelColor: muted,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    tabs: const [
                      Tab(height: 38, text: "Open"),
                      Tab(height: 38, text: "Approved"),
                      Tab(height: 38, text: "Declined"),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _list(RefundRequestRepository.watchOpen(), _Tab.open),
                _list(RefundRequestRepository.watchDecided('approved'), _Tab.approved),
                _list(RefundRequestRepository.watchDecided('declined'), _Tab.declined),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Keeps the cards readable on very wide screens.
  Widget _centered(Widget child) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 980), child: child),
      );

  Widget _list(Stream<List<RefundRequest>> stream, _Tab tab) {
    return StreamBuilder<List<RefundRequest>>(
      stream: stream,
      builder: (context, reqSnap) {
        if (reqSnap.hasError) return _message(context, Icons.error_outline, "Couldn't load refund requests.");
        if (!reqSnap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accent));
        }
        return StreamBuilder<List<BookingRecord>>(
          stream: BookingRepository.watchAllBookings(),
          builder: (context, bookSnap) {
            final byId = {for (final b in bookSnap.data ?? const <BookingRecord>[]) b.id: b};
            final reqs = reqSnap.data!;
            if (reqs.isEmpty) {
              return switch (tab) {
                _Tab.open => _message(context, Icons.inbox_outlined, "No open refund requests",
                    "When a customer asks for a refund, it will show up here for you to approve or decline."),
                _Tab.approved => _message(context, Icons.task_alt_rounded, "No approved refunds yet",
                    "Requests you approve will be kept here, with whether the money was sent."),
                _Tab.declined => _message(context, Icons.block_rounded, "No declined requests",
                    "Requests you decline will be kept here, with your reason."),
              };
            }
            return _centered(
              ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                itemCount: reqs.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    final label = tab == _Tab.open
                        ? "${reqs.length} open request${reqs.length == 1 ? '' : 's'} waiting for you"
                        : "${reqs.length} ${tab == _Tab.approved ? 'approved' : 'declined'}";
                    return Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(label,
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppPalette.textMuted(context))),
                    );
                  }
                  final req = reqs[i - 1];
                  return _card(context, req, byId[req.bookingId], tab);
                },
              ),
            );
          },
        );
      },
    );
  }

  static String _peso(int v) => "₱${NumberFormat('#,##0').format(v)}";

  Widget _chip(BuildContext context, IconData icon, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.11), borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12.5, color: color),
            const SizedBox(width: 5),
            Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      );

  /// "Event passed 16 days ago" / "Event is today" / "Event in 5 days", plus
  /// how long a request has been waiting — what staff weigh before deciding.
  List<Widget> _flags(BuildContext context, RefundRequest req, BookingRecord b, _Tab tab) {
    const orange = Color(0xFFE08A00);
    const red = Color(0xFFC62828);
    final today = DateTime.now();
    final days = DateTime(b.date.year, b.date.month, b.date.day).difference(DateTime(today.year, today.month, today.day)).inDays;
    final flags = <Widget>[];
    if (days < 0) {
      flags.add(_chip(context, Icons.event_busy_rounded, "Event passed ${-days} day${days == -1 ? '' : 's'} ago", orange));
    } else if (days == 0) {
      flags.add(_chip(context, Icons.today_rounded, "Event is today", orange));
    } else {
      flags.add(_chip(context, Icons.event_available_rounded, "Event in $days day${days == 1 ? '' : 's'}", AppColors.stone500));
    }
    if (tab == _Tab.open && req.createdAt != null) {
      final waiting = today.difference(req.createdAt!).inDays;
      if (waiting >= 2) flags.add(_chip(context, Icons.hourglass_bottom_rounded, "Waiting $waiting days", red));
    }
    return flags;
  }

  Widget _card(BuildContext context, RefundRequest req, BookingRecord? b, _Tab tab) {
    final busy = _busy.contains(req.id);
    final name = b == null
        ? 'Booking not found'
        : (b.customerName.trim().isEmpty ? 'Customer' : b.customerName.trim());
    final primary = AppPalette.textPrimary(context);
    final muted = AppPalette.textMuted(context);
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppPalette.divider(context)),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    gradient: const LinearGradient(
                      colors: [AppColors.accent, Color(0xFF3F0F11)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Text(name[0].toUpperCase(),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: primary)),
                      const SizedBox(height: 3),
                      if (b != null)
                        Text(
                          "${b.packageName} · ${DateFormat('MMM d, yyyy').format(b.date)} · ${b.time}",
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                    ],
                  ),
                ),
                if (b != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_peso(b.totalPrice),
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.accent, height: 1.1)),
                      const SizedBox(height: 2),
                      Text(b.isDownpayment ? "downpayment" : "paid in full", style: TextStyle(fontSize: 11, color: muted)),
                    ],
                  ),
              ],
            ),
          ),
          if (b != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Wrap(spacing: 8, runSpacing: 6, children: _flags(context, req, b, tab)),
            ),
            const SizedBox(height: 16),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _info(context, req, b)),
            const SizedBox(height: 12),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _refundTo(context, req, b)),
          ],
          const SizedBox(height: 12),
          // ── customer's reason ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: AppPalette.surface(context),
                borderRadius: BorderRadius.circular(14),
                border: const Border(left: BorderSide(color: AppColors.accent, width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("CUSTOMER'S REASON",
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: muted)),
                  const SizedBox(height: 6),
                  Text(
                    req.reason.isEmpty ? "No reason given." : req.reason,
                    style: TextStyle(fontSize: 13.5, height: 1.45, color: primary),
                  ),
                ],
              ),
            ),
          ),
          // ── footer ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 12, 0),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 13, color: muted),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    req.createdAt == null ? "Just now" : "Requested ${DateFormat('MMM d, h:mm a').format(req.createdAt!)}",
                    style: TextStyle(fontSize: 11.5, color: muted),
                  ),
                ),
                if (b != null)
                  TextButton.icon(
                    onPressed: () => _openChat(_uidOf(req, b), b.customerName),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                    label: const Text("Message customer", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
            child: tab == _Tab.open
                ? Align(
                    alignment: Alignment.centerRight,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: busy ? null : () => _decline(req),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.accent,
                                side: BorderSide(color: AppColors.accent.withValues(alpha: 0.45)),
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: const Text("Decline", style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: (busy || b == null) ? null : () => _approve(req, b),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              icon: busy
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.check_circle_outline_rounded, size: 18),
                              label: const Text("Approve & refund", style: TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : _outcome(context, req, b, tab),
          ),
        ],
      ),
    );
  }

  /// History tabs: what was decided, when, and (for approved requests)
  /// whether the money has actually been sent yet.
  Widget _outcome(BuildContext context, RefundRequest req, BookingRecord? b, _Tab tab) {
    final when = req.decidedAt == null ? '' : ' · ${DateFormat('MMM d, yyyy · h:mm a').format(req.decidedAt!)}';
    final String title;
    final String? detail;
    final Color color;
    final IconData icon;
    if (tab == _Tab.declined) {
      title = "Declined$when";
      detail = req.decisionNote.isEmpty ? null : "Reason: ${req.decisionNote}";
      color = AppColors.stone500;
      icon = Icons.block_rounded;
    } else if (b?.refundStatus == 'refunded') {
      title = "Refunded ${_peso(b!.refundAmount)}";
      detail = [
        if (b.refundedAt != null) "Sent ${DateFormat('MMM d, yyyy · h:mm a').format(b.refundedAt!)}",
        if ((b.refundedByStaffName ?? '').isNotEmpty) "by ${b.refundedByStaffName}",
        if (b.refundReference.isNotEmpty) "· GCash ref ${b.refundReference}",
      ].join(' ');
      color = const Color(0xFF2E7D32);
      icon = Icons.check_circle_rounded;
    } else if (b?.refundStatus == 'pending') {
      title = "Approved$when";
      detail = "${_peso(b!.refundAmount)} still to send. Send it by GCash, then tap \"Mark refunded\" in Refunds to send.";
      color = const Color(0xFFE08A00);
      icon = Icons.hourglass_top_rounded;
    } else {
      title = "Approved$when";
      detail = b?.refundStatus == 'none' ? "No refund needed — no payment received." : null;
      color = AppColors.stone500;
      icon = Icons.task_alt_rounded;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
                if (detail != null && detail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SelectableText(detail, style: TextStyle(fontSize: 12.5, height: 1.4, color: AppPalette.textSecondary(context))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Contact, what was booked, and what was paid — laid out in two columns
  /// on wide screens.
  Widget _info(BuildContext context, RefundRequest req, BookingRecord b) {
    final addOns = b.addOnNames.isEmpty ? '' : ' + ${b.addOnNames.join(', ')}';
    final paidLine = b.isDownpayment
        ? "${_peso(b.paidAmount)} paid of ${_peso(b.totalPrice)}${b.balancePaid ? ' (balance collected)' : ''}"
        : _peso(b.paidAmount);
    final uid = _uidOf(req, b);

    Widget tile(IconData icon, String label, Widget value) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 15, color: AppColors.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
                  const SizedBox(height: 1),
                  value,
                ],
              ),
            ),
          ],
        );
    Widget text(String v) => Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context)));

    final tiles = <Widget>[
      FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
        builder: (context, snap) {
          final d = snap.data?.data();
          final contact = [
            ((d?['contactNumber'] ?? '') as String).trim(),
            ((d?['email'] ?? '') as String).trim(),
          ].where((v) => v.isNotEmpty).join(' · ');
          return tile(Icons.call_outlined, 'Contact',
              text(snap.connectionState != ConnectionState.done ? '…' : (contact.isEmpty ? '—' : contact)));
        },
      ),
      tile(Icons.photo_camera_outlined, 'Booking', text('${b.packageName}$addOns')),
      tile(Icons.event_rounded, 'Event', text('${DateFormat('EEE, MMM d, yyyy').format(b.date)} · ${b.time}')),
      if (b.location.trim().isNotEmpty) tile(Icons.place_outlined, 'Location', text(b.location.trim())),
      tile(Icons.payments_outlined, 'Payment', text(paidLine)),
      if (b.receiptRefNo.isNotEmpty) tile(Icons.receipt_long_outlined, 'GCash ref no.', text(b.receiptRefNo)),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final twoCols = c.maxWidth >= 560;
        final w = twoCols ? (c.maxWidth - 24) / 2 : c.maxWidth;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(14)),
          child: Wrap(
            spacing: 24,
            runSpacing: 14,
            children: [for (final t in tiles) SizedBox(width: w, child: t)],
          ),
        );
      },
    );
  }

  /// Where the money goes. Highlighted so a missing GCash number is hard to miss.
  Widget _refundTo(BuildContext context, RefundRequest req, BookingRecord b) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_rounded, size: 14, color: AppColors.accent),
              const SizedBox(width: 6),
              Text("SEND THE REFUND TO",
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppPalette.textMuted(context))),
            ],
          ),
          RefundAccountLine(userId: _uidOf(req, b)),
        ],
      ),
    );
  }

  Widget _message(BuildContext context, IconData icon, String title, [String? subtitle]) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.08), shape: BoxShape.circle),
                child: Icon(icon, size: 38, color: AppColors.accent),
              ),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, height: 1.5, color: AppPalette.textMuted(context))),
                ),
              ],
            ],
          ),
        ),
      );
}
