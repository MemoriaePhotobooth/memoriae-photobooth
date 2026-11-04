import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/booking_repository.dart';
import '../models/booth_package.dart';
import '../services/feedback_repository.dart';
import '../services/payment_info.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/receipt_upload_modal.dart';
import 'booking_invoice_screen.dart';
import 'event_photos_screen.dart';
import '../services/refund_request_repository.dart';
import '../widgets/circle_back_button.dart';
import '../widgets/app_toast.dart';
import '../widgets/stream_once.dart';

/// Lets the customer see every booking they've made and, once one is
/// marked `completed` by staff, leave a star rating + comment against it.
/// A real review submitted here is what powers the Home screen's
/// testimonial card and what Staff/Admin see in their Feedback tab.
class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  String? _uid;
  // 'upcoming' | 'past' | 'all'
  String _tab = 'upcoming';

  @override
  void initState() {
    super.initState();
    AuthService.instance.me().then((u) {
      if (mounted) setState(() => _uid = u?.uid);
    });
  }

  DateTime? _dateOf(Map<String, dynamic> b) {
    final ts = b['date'];
    return ts is Timestamp ? ts.toDate() : null;
  }

  bool _isUpcoming(Map<String, dynamic> b) {
    final status = b['status'] as String? ?? '';
    if (status == 'completed' || status == 'cancelled') return false;
    final date = _dateOf(b);
    if (date == null) return true;
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    return !date.isBefore(startOfToday);
  }

  List<Map<String, dynamic>> _applyTab(List<Map<String, dynamic>> bookings) {
    switch (_tab) {
      case 'upcoming':
        return bookings.where(_isUpcoming).toList();
      case 'past':
        return bookings.where((b) => !_isUpcoming(b)).toList();
      default:
        return bookings;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        // Back goes to wherever the customer came from (e.g. the Book page);
        // if there is nothing to go back to (opened from the nav), Home.
        leading: CircleBackButton.appBar(
          onPressed: () {
            final nav = Navigator.of(context);
            if (nav.canPop()) {
              nav.pop();
            } else {
              nav.pushReplacementNamed('/');
            }
          },
        ),
        leadingWidth: CircleBackButton.appBarLeadingWidth,
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: const Text("My Bookings", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        centerTitle: false,
      ),
      body: _uid == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : StreamOnce<List<Map<String, dynamic>>>(
              create: () => BookingRepository.watchBookingsForUser(_uid!),
              identity: _uid,
              builder: (context, bookingSnap) {
                if (!bookingSnap.hasData) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.accent));
                }
                final bookings = bookingSnap.data!;
                if (bookings.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 84,
                            height: 84,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: AppColors.accentTint(0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.event_note_rounded, size: 38, color: AppColors.accent),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            "No bookings yet",
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppPalette.textPrimary(context)),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Reserve your first photobooth slot and it will show up here.",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, height: 1.4, color: AppPalette.textMuted(context)),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: () => Navigator.of(context).pushReplacementNamed('/book'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                              shape: const StadiumBorder(),
                            ),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text("Book a slot", style: TextStyle(fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final upcomingCount = bookings.where(_isUpcoming).length;
                final pastCount = bookings.length - upcomingCount;
                final filtered = _applyTab(bookings);

                return StreamOnce<Set<String>>(
                  create: () => FeedbackRepository.watchReviewedBookingIds(_uid!),
                  identity: _uid,
                  builder: (context, feedbackSnap) {
                    final reviewedIds = feedbackSnap.data ?? const <String>{};
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: _BookingTabBar(
                            tab: _tab,
                            onChanged: (t) => setState(() => _tab = t),
                            upcomingCount: upcomingCount,
                            pastCount: pastCount,
                            totalCount: bookings.length,
                          ),
                        ),
                        Expanded(
                          child: filtered.isEmpty
                              ? Center(
                                  child: Text(
                                    _tab == 'upcoming' ? "No upcoming bookings." : "No past bookings.",
                                    style: TextStyle(color: AppPalette.textMuted(context)),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                                  itemBuilder: (context, i) {
                                    final b = filtered[i];
                                    final alreadyReviewed = reviewedIds.contains(b['id'] as String);
                                    return _BookingCard(booking: b, alreadyReviewed: alreadyReviewed, userId: _uid!);
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }
}

/// "Upcoming / Past / All" segmented control shown above the bookings
/// list, with live counts for each tab.
class _BookingTabBar extends StatelessWidget {
  final String tab;
  final ValueChanged<String> onChanged;
  final int upcomingCount;
  final int pastCount;
  final int totalCount;

  const _BookingTabBar({
    required this.tab,
    required this.onChanged,
    required this.upcomingCount,
    required this.pastCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final tabs = [
      ('upcoming', 'Upcoming', upcomingCount),
      ('past', 'Past', pastCount),
      ('all', 'All', totalCount),
    ];
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppPalette.surface(context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (final (value, label, count) in tabs)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: tab == value ? AppPalette.cardBg(context) : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: tab == value
                        ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 1))]
                        : null,
                  ),
                  child: Text(
                    '$label ($count)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: tab == value ? FontWeight.w700 : FontWeight.w500,
                      color: tab == value ? AppColors.accent : AppPalette.textMuted(context),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final bool alreadyReviewed;
  final String userId;

  const _BookingCard({required this.booking, required this.alreadyReviewed, required this.userId});

  DateTime? get _date {
    final ts = booking['date'];
    return ts is Timestamp ? ts.toDate() : null;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':
        return const Color(0xFF2E7D32);
      case 'completed':
        return const Color(0xFF1565C0);
      case 'cancelled':
        return const Color(0xFFB3261E);
      default: // awaiting_receipt, pending_confirmation
        return const Color(0xFFB07A2A);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'awaiting_receipt':
        return 'Awaiting Receipt';
      case 'pending_confirmation':
        return 'Pending Approval';
      case 'confirmed':
        return 'Confirmed';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = booking['status'] as String? ?? '';
    final packageName = booking['packageName'] as String? ?? 'Booking';
    final time = booking['time'] as String? ?? '';
    final date = _date;
    final color = _statusColor(status);

    return Container(
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppPalette.divider(context)),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ticket-stub style date badge.
                Container(
                  width: 58,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      Text(
                        date != null ? DateFormat('MMM').format(date).toUpperCase() : '—',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        date != null ? DateFormat('d').format(date) : '?',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color, height: 1.1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              packageName,
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: AppPalette.textPrimary(context)),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                            child: Text(_statusLabel(status), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 13, color: AppPalette.textMuted(context)),
                          const SizedBox(width: 4),
                          Text(
                            date != null ? '${DateFormat('EEE, MMM d, yyyy').format(date)} · $time' : time,
                            style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)),
                          ),
                        ],
                      ),
                      if (status == 'cancelled' && (booking['refundStatus'] == 'pending' || booking['refundStatus'] == 'refunded')) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              booking['refundStatus'] == 'refunded' ? Icons.check_circle_outline : Icons.undo_rounded,
                              size: 13,
                              color: booking['refundStatus'] == 'refunded' ? const Color(0xFF2E7D32) : const Color(0xFFE08A00),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                booking['refundStatus'] == 'refunded'
                                    ? 'Refund of ${formatPeso((booking['refundAmount'] as num?)?.toInt() ?? 0)} sent'
                                        '${booking['refundedAt'] is Timestamp ? ' on ${DateFormat('MMM d, yyyy').format((booking['refundedAt'] as Timestamp).toDate())}' : ''}'
                                        '${(booking['refundReference'] ?? '').toString().trim().isEmpty ? '' : ' · GCash ref ${(booking['refundReference'] ?? '').toString().trim()}'}'
                                    : 'Refund of ${formatPeso((booking['refundAmount'] as num?)?.toInt() ?? 0)} pending — we\'ll send it to your GCash',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: booking['refundStatus'] == 'refunded' ? const Color(0xFF2E7D32) : const Color(0xFFE08A00),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (status != 'cancelled' && status != 'awaiting_receipt' && PaymentInfo.fromBooking(booking).hasBalance) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.payments_outlined, size: 13, color: Color(0xFFE08A00)),
                            const SizedBox(width: 4),
                            Text(
                              'Balance due: ${formatPeso(PaymentInfo.fromBooking(booking).balance)} (pay on event day)',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFE08A00)),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (booking['rescheduledAt'] != null) ...[
            Divider(height: 1, color: AppPalette.divider(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: _RescheduledNotice(booking: booking),
            ),
          ],
          if (BookingInvoiceScreen.isAvailable(status)) ...[
            Divider(height: 1, color: AppPalette.divider(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => BookingInvoiceScreen(booking: booking)),
                  ),
                  icon: const Icon(Icons.receipt_long_outlined, size: 16, color: AppColors.accent),
                  label: const Text("View Invoice",
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.accent)),
                ),
              ),
            ),
          ],
          if (status == 'awaiting_receipt') ...[
            Divider(height: 1, color: AppPalette.divider(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _resumeReceiptUpload(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.receipt_long, size: 16),
                  label: const Text("Upload Payment Receipt", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                ),
              ),
            ),
          ],
          // Paid (has a receipt) and confirmed: the customer can ask for a refund.
          if (status == 'confirmed' && ((booking['receiptUrl'] ?? '') as String).isNotEmpty) ...[
            Divider(height: 1, color: AppPalette.divider(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: _RefundSection(bookingId: booking['id'] as String, userId: userId),
            ),
          ],
          if ((status == 'confirmed' || status == 'completed') &&
              ((booking['eventPhotoCount'] as num?)?.toInt() ?? 0) > 0) ...[
            Divider(height: 1, color: AppPalette.divider(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EventPhotosScreen(
                        bookingId: booking['id'] as String,
                        userId: userId,
                      ),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.photo_library_outlined, size: 16),
                  label: Text(
                    "View Event Photos (${(booking['eventPhotoCount'] as num).toInt()})",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                ),
              ),
            ),
          ],
          if (status == 'completed') ...[
            Divider(height: 1, color: AppPalette.divider(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: alreadyReviewed
                  ? Row(
                      children: [
                        const Icon(Icons.check_circle, size: 14, color: AppColors.accent),
                        const SizedBox(width: 6),
                        Text("You reviewed this booking — thank you!", style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _openReviewDialog(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.accent,
                          side: const BorderSide(color: AppColors.accent),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.star_outline, size: 16),
                        label: const Text("Leave a Review", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  /// Reopens [ReceiptUploadModal] for this `awaiting_receipt` booking —
  /// this is where a customer who backed out of the modal earlier (via its
  /// back button, to go explore the app) finds their way back to sending
  /// payment. Anchored to the booking's own `holdExpiresAt`, same as when
  /// the modal first opened, so it's the real remaining time, not a fresh
  /// 15 minutes.
  Future<void> _resumeReceiptUpload(BuildContext context) async {
    final bookingId = booking['id'] as String;
    final holdExpiresAtTs = booking['holdExpiresAt'];
    if (holdExpiresAtTs is! Timestamp) {
      AppToast.show(context, "This hold already expired — please start a new booking.");
      return;
    }
    ReceiptUploadModal.show(
      context,
      bookingId: bookingId,
      userId: userId,
      holdExpiresAt: holdExpiresAtTs.toDate(),
      onExpired: () {
        if (!context.mounted) return;
        AppToast.show(context, "That hold ran out and the slot was released.");
      },
      onSubmitted: () {
        if (!context.mounted) return;
        AppToast.show(context, "Receipt sent — waiting on staff to confirm your booking.");
      },
    );
  }

  Future<void> _openReviewDialog(BuildContext context) async {
    final packageName = booking['packageName'] as String? ?? 'Booking';
    final bookingId = booking['id'] as String;
    final customerName = booking['customerName'] as String? ?? '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _ReviewDialog(
        bookingId: bookingId,
        userId: userId,
        customerName: customerName,
        packageName: packageName,
      ),
    );
  }
}

/// "Staff moved this booking — was <old>, now <current>" banner shown on
/// a booking card once `BookingRepository.rescheduleBooking` (Staff app)
/// has touched it. Reads straight off the same live booking map this
/// card already streams, so it updates the moment staff reschedules
/// again — no separate fetch needed.
class _RescheduledNotice extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _RescheduledNotice({required this.booking});

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF1565C0);
    final prevTs = booking['previousDate'];
    final prevDate = prevTs is Timestamp ? prevTs.toDate() : null;
    final prevTime = booking['previousTime'] as String? ?? '';
    final by = (booking['rescheduledByStaffName'] as String? ?? '').trim();
    final reason = (booking['rescheduleReason'] as String? ?? '').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: blue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.event_repeat, size: 16, color: blue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  by.isEmpty ? "Your schedule was moved by our team." : "Your schedule was moved by $by.",
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: blue),
                ),
                if (prevDate != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    "Previously: ${DateFormat('EEE, MMM d, yyyy').format(prevDate)}${prevTime.isEmpty ? '' : ' · $prevTime'}",
                    style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context), decoration: TextDecoration.lineThrough),
                  ),
                ],
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text("Note: $reason", style: TextStyle(fontSize: 11.5, color: AppPalette.textSecondary(context))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewDialog extends StatefulWidget {
  final String bookingId;
  final String userId;
  final String customerName;
  final String packageName;

  const _ReviewDialog({
    required this.bookingId,
    required this.userId,
    required this.customerName,
    required this.packageName,
  });

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  int _rating = 5;
  final _commentController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_commentController.text.trim().isEmpty) {
      setState(() => _error = "Tell us a bit about your experience.");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await FeedbackRepository.addFeedback(
        bookingId: widget.bookingId,
        userId: widget.userId,
        customerName: widget.customerName.isEmpty ? "Customer" : widget.customerName,
        packageName: widget.packageName,
        rating: _rating,
        comment: _commentController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      AppToast.show(context, "Thanks for the review!");
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text("Rate Your Experience"),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.packageName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final starIndex = i + 1;
                return IconButton(
                  onPressed: () => setState(() => _rating = starIndex),
                  icon: Icon(
                    starIndex <= _rating ? Icons.star : Icons.star_border,
                    color: const Color(0xFFF2B84B),
                    size: 28,
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: "What did you like? Anything we could improve?",
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFFE5484D))),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text("Cancel")),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAccent))
              : const Text("Submit"),
        ),
      ],
    );
  }
}

/// Asks for a refund on a paid booking. One open request per booking.
Future<void> _requestRefund(BuildContext context, String bookingId, String userId) async {
  // The dialog owns its text controller and does the sending itself, so the
  // controller is never disposed while the dialog is still animating closed,
  // the button can't be tapped twice, and any error shows inside the dialog.
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RefundReasonDialog(bookingId: bookingId, userId: userId),
  );
  if (result == null || !context.mounted) return;

  final msg = result == 'exists'
      ? "You already sent a refund request for this booking."
      : "Refund request sent. We'll get back to you.";
  AppToast.show(context, msg);
}

class _RefundReasonDialog extends StatefulWidget {
  final String bookingId;
  final String userId;
  const _RefundReasonDialog({required this.bookingId, required this.userId});

  @override
  State<_RefundReasonDialog> createState() => _RefundReasonDialogState();
}

class _RefundReasonDialogState extends State<_RefundReasonDialog> {
  final _reasonCtrl = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = "Please tell us the reason for your refund request.");
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      if (await RefundRequestRepository.hasRequest(bookingId: widget.bookingId, userId: widget.userId)) {
        if (mounted) Navigator.pop(context, 'exists');
        return;
      }
      await RefundRequestRepository.submit(
        bookingId: widget.bookingId,
        userId: widget.userId,
        reason: reason,
      );
      if (mounted) Navigator.pop(context, 'sent');
    } on FirebaseException catch (e) {
      debugPrint('Refund request failed: ${e.code} ${e.message}');
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.code == 'permission-denied'
            ? "This booking can't be refunded from the app anymore. Please message our staff."
            : (e.code == 'unavailable'
                ? "No connection. Please check your internet and try again."
                : "Couldn't send the request. Please try again.");
      });
    } catch (e) {
      debugPrint('Refund request failed: $e');
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = "Couldn't send the request. Please try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Request a refund"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Tell us why you're asking. Our staff will review it and get back to you.",
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonCtrl,
              enabled: !_sending,
              maxLines: 4,
              maxLength: 500,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                hintText: "Reason",
                border: const OutlineInputBorder(),
                errorText: _error,
                errorMaxLines: 3,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: _sending ? null : _send,
          child: _sending
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAccent))
              : const Text("Send request"),
        ),
      ],
    );
  }
}

/// Refund area of a confirmed, paid booking: the "Request refund" button, or
/// where the customer's request stands (waiting / declined, with the reason).
class _RefundSection extends StatelessWidget {
  final String bookingId;
  final String userId;
  const _RefundSection({required this.bookingId, required this.userId});

  @override
  Widget build(BuildContext context) {
    // Refund requests are saved under a signed-in account, so a guest can't
    // send one from the app.
    if (!AuthService.instance.isLoggedIn) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: AppPalette.textMuted(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Need a refund? Guests can't send a refund request in the app. Message our staff with your booking details and your GCash number.",
              style: TextStyle(fontSize: 12, height: 1.4, color: AppPalette.textMuted(context)),
            ),
          ),
        ],
      );
    }
    return StreamOnce<Map<String, dynamic>?>(
      create: () => RefundRequestRepository.watchLatest(bookingId: bookingId, userId: userId),
      identity: Object.hash(bookingId, userId),
      builder: (context, snap) {
        final latest = snap.data;
        final status = latest?['status'] as String?;

        if (status == 'open') {
          return Row(
            children: [
              const Icon(Icons.hourglass_top_rounded, size: 16, color: Color(0xFFE08A00)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Refund request sent. We're reviewing it and will get back to you.",
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context)),
                ),
              ),
            ],
          );
        }

        final declined = status == 'declined';
        final note = ((latest?['decisionNote'] ?? '') as String).trim();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (declined) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFB3261E).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.cancel_outlined, size: 16, color: Color(0xFFB3261E)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        note.isEmpty ? "Your refund request was declined." : "Your refund request was declined: $note",
                        style: TextStyle(fontSize: 12.5, height: 1.4, color: AppPalette.textPrimary(context)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            OutlinedButton.icon(
              onPressed: () => _requestRefund(context, bookingId, userId),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.undo_rounded, size: 16),
              label: Text(declined ? "Request again" : "Request refund", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
            ),
          ],
        );
      },
    );
  }
}
