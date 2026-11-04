import '../../shared/app_modal.dart';
import '../../shared/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../shared/refund_account_line.dart';
import '../models/booking_record.dart';
import '../services/booking_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import 'refund_sent_dialog.dart';

String _peso(int v) => '₱${NumberFormat('#,##0').format(v)}';

/// Orange banner shown above the bookings list while any refund is waiting
/// to be sent. Tapping it opens the full "Refunds to send" list. Renders
/// nothing when there's nothing to send.
///
/// [onMarkRefunded] is supplied by the dashboard so the Staff app can
/// attribute the refund to the signed-in staff member.
class RefundsToSendBanner extends StatelessWidget {
  final Future<void> Function(BookingRecord booking, String reference) onMarkRefunded;
  final EdgeInsetsGeometry padding;
  const RefundsToSendBanner({super.key, required this.onMarkRefunded, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BookingRecord>>(
      stream: BookingRepository.watchAllBookings(),
      builder: (context, snap) {
        final pending = (snap.data ?? const <BookingRecord>[]).where((b) => b.refundPending).toList();
        if (pending.isEmpty) return const SizedBox.shrink();
        final total = pending.fold<int>(0, (s, b) => s + b.refundAmount);
        const orange = Color(0xFFE08A00);
        return Padding(
          padding: padding,
          child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => RefundsToSendSheet.show(context, onMarkRefunded: onMarkRefunded),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: orange.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: orange.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.undo_rounded, size: 18, color: orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "${pending.length} refund${pending.length == 1 ? '' : 's'} to send · ${_peso(total)}",
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: orange),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 20, color: orange),
                ],
              ),
            ),
          ),
          ),
        );
      },
    );
  }
}

/// Bottom sheet listing every refund still to be sent, with a
/// "Mark refunded" button per row.
class RefundsToSendSheet extends StatefulWidget {
  final Future<void> Function(BookingRecord booking, String reference) onMarkRefunded;
  const RefundsToSendSheet({super.key, required this.onMarkRefunded});

  static Future<void> show(BuildContext context, {required Future<void> Function(BookingRecord booking, String reference) onMarkRefunded}) {
    return showAppModal<void>(
      context,
      maxWidth: 560,
      builder: (_) => RefundsToSendSheet(onMarkRefunded: onMarkRefunded),
    );
  }

  @override
  State<RefundsToSendSheet> createState() => _RefundsToSendSheetState();
}

class _RefundsToSendSheetState extends State<RefundsToSendSheet> {
  final Set<String> _busy = {};

  Future<void> _mark(BookingRecord b) async {
    final reference = await RefundSentDialog.show(context, amount: b.refundAmount);
    if (reference == null) return;
    setState(() => _busy.add(b.id));
    try {
      await widget.onMarkRefunded(b, reference);
    } catch (e) {
      if (mounted) {
        TopToast.show(context, "Couldn't update refund: $e", kind: TopToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(b.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text("Refunds to send",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 22),
                    color: AppPalette.textMuted(context),
                    tooltip: "Close",
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text("Send each one by GCash, then tap \"Mark refunded\".",
                  style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
              const SizedBox(height: 12),
              Flexible(
                child: StreamBuilder<List<BookingRecord>>(
                  stream: BookingRepository.watchAllBookings(),
                  builder: (context, snap) {
                    final pending = (snap.data ?? const <BookingRecord>[]).where((b) => b.refundPending).toList();
                    if (pending.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: Text("All caught up — no refunds waiting.", style: TextStyle(color: AppPalette.textMuted(context))),
                        ),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: pending.length,
                      separatorBuilder: (_, __) => Divider(height: 20, color: AppPalette.divider(context)),
                      itemBuilder: (context, i) {
                        final b = pending[i];
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(b.customerName.isNotEmpty ? b.customerName : 'Customer ${b.bookingRef}',
                                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
                                  const SizedBox(height: 2),
                                  Text('${b.packageName} · ${DateFormat('MMM d, yyyy').format(b.date)} · ref ${b.bookingRef}',
                                      style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
                                  if (b.refundNote.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(b.refundNote, style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
                                  ],
                                  if (b.retainedAmount > 0) ...[
                                    const SizedBox(height: 2),
                                    Text('Business keeps ${_peso(b.retainedAmount)}',
                                        style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(_peso(b.refundAmount),
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFFE08A00))),
                                const SizedBox(height: 6),
                                SizedBox(
                                  height: 34,
                                  child: FilledButton(
                                    onPressed: _busy.contains(b.id) ? null : () => _mark(b),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppColors.accent,
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                    ),
                                    child: _busy.contains(b.id)
                                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        : const Text("Mark refunded", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Refund summary for one booking's detail page: the decision, the amounts,
/// and (while pending) a "Mark refunded" button. Renders nothing when no
/// refund decision was recorded.
class RefundStatusCard extends StatelessWidget {
  final BookingRecord booking;
  final bool busy;
  final VoidCallback? onMarkRefunded;
  const RefundStatusCard({super.key, required this.booking, this.busy = false, this.onMarkRefunded});

  @override
  Widget build(BuildContext context) {
    final b = booking;
    if (b.refundStatus == null) return const SizedBox.shrink();
    const orange = Color(0xFFE08A00);
    const green = Color(0xFF2E7D32);

    final String title;
    final Color color;
    switch (b.refundStatus) {
      case 'pending':
        title = 'Refund pending — ${_peso(b.refundAmount)} to send';
        color = orange;
        break;
      case 'refunded':
        title = 'Refunded — ${_peso(b.refundAmount)}';
        color = green;
        break;
      default:
        title = 'No refund needed — no payment received';
        color = AppPalette.textMuted(context);
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(b.refundStatus == 'refunded' ? Icons.check_circle_rounded : Icons.undo_rounded, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: color))),
            ],
          ),
          if (b.refundPending) RefundAccountLine(userId: b.userId),
          if (b.refundStatus == 'refunded' && b.refundedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Sent ${DateFormat('MMM d, yyyy · h:mm a').format(b.refundedAt!)}'
              '${(b.refundedByStaffName ?? '').isNotEmpty ? ' by ${b.refundedByStaffName}' : ''}',
              style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)),
            ),
          ],
          if (b.refundStatus == 'refunded' && b.refundReference.isNotEmpty) ...[
            const SizedBox(height: 4),
            SelectableText('GCash ref no. ${b.refundReference}', style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
          ],
          if (b.retainedAmount > 0) ...[
            const SizedBox(height: 6),
            Text('Business keeps ${_peso(b.retainedAmount)}', style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
          ],
          if (b.refundNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(b.refundNote, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
          ],
          if (b.refundPending && onMarkRefunded != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onMarkRefunded,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text("Mark refunded", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
