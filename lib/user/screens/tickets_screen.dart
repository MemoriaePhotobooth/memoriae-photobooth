import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/booth_package.dart';
import '../services/auth_service.dart';
import '../services/booking_repository.dart';
import '../services/payment_info.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/circle_back_button.dart';
import '../widgets/stream_once.dart';

/// "Tickets" = a digital event pass for each booking.
///
/// Once staff approve a booking it becomes an *active* pass: it shows the
/// invoice number, package, date/time, location, any balance still due on
/// the event day, and a QR code staff can scan (or read the invoice number
/// from) when the customer arrives. Requests still waiting for approval
/// show as a locked pass, and finished events as "used".
///
/// Everything is read live from the customer's own `bookings` — nothing
/// new is stored.
class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key});

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  String? _uid;
  bool _loadingUser = true;

  @override
  void initState() {
    super.initState();
    AuthService.instance.me().then((u) {
      if (mounted) {
        setState(() {
          _uid = u?.uid;
          _loadingUser = false;
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => _loadingUser = false);
    });
  }

  static bool _isTicket(Map<String, dynamic> b) {
    final s = b['status'] as String? ?? '';
    return s == 'confirmed' || s == 'pending_confirmation' || s == 'completed';
  }

  static DateTime _dateOf(Map<String, dynamic> b) {
    final ts = b['date'];
    return ts is Timestamp ? ts.toDate() : DateTime(2100);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        leading: const CircleBackButton.appBar(),
        leadingWidth: CircleBackButton.appBarLeadingWidth,
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: Text('Tickets', style: TextStyle(color: AppPalette.textPrimary(context), fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      body: SafeArea(
        child: _loadingUser
            ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
            : _uid == null
                ? _message(context, Icons.confirmation_number_outlined, 'No tickets yet', 'Book a photobooth and your pass will show up here.')
                : StreamOnce<List<Map<String, dynamic>>>(
                    create: () => BookingRepository.watchBookingsForUser(_uid!),
                    identity: _uid,
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return _message(context, Icons.error_outline, "Couldn't load your tickets", 'Check your connection and try again.');
                      }
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator(color: AppColors.accent));
                      }
                      final all = snap.data!.where(_isTicket).toList();
                      if (all.isEmpty) {
                        return _message(context, Icons.confirmation_number_outlined, 'No tickets yet',
                            'Once you book a photobooth, your event pass will appear here.');
                      }
                      // Active first (soonest date on top), then pending, then used.
                      int rank(Map<String, dynamic> b) {
                        switch (b['status']) {
                          case 'confirmed':
                            return 0;
                          case 'pending_confirmation':
                            return 1;
                          default:
                            return 2;
                        }
                      }

                      all.sort((a, b) {
                        final r = rank(a).compareTo(rank(b));
                        return r != 0 ? r : _dateOf(a).compareTo(_dateOf(b));
                      });
                      return ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: all.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return Text(
                              'Show the QR code to our staff when you arrive. Tap a pass to enlarge it.',
                              style: TextStyle(fontSize: 12.5, height: 1.5, color: AppPalette.textSecondary(context)),
                            );
                          }
                          return _TicketCard(booking: all[i - 1]);
                        },
                      );
                    },
                  ),
      ),
    );
  }

  Widget _message(BuildContext context, IconData icon, String title, String body) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.accent),
            const SizedBox(height: 14),
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.5, color: AppPalette.textSecondary(context))),
          ],
        ),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.booking});
  final Map<String, dynamic> booking;

  String get _status => booking['status'] as String? ?? '';
  bool get _active => _status == 'confirmed';

  /// What the QR encodes — the booking id plus the human-readable invoice
  /// number, so staff can either scan it or just search the invoice no.
  String get _qrData {
    final id = booking['id'] as String? ?? '';
    final inv = (booking['invoiceNo'] as String? ?? '').trim();
    return 'MEMORIAE|$id|$inv';
  }

  @override
  Widget build(BuildContext context) {
    final ts = booking['date'];
    final date = ts is Timestamp ? ts.toDate() : null;
    final time = booking['time'] as String? ?? '';
    final pkg = booking['packageName'] as String? ?? 'Photobooth';
    final invoice = (booking['invoiceNo'] as String? ?? '').trim();
    final location = (booking['location'] as String? ?? '').trim();
    final pay = PaymentInfo.fromBooking(booking);

    final String badge;
    final Color badgeColor;
    switch (_status) {
      case 'confirmed':
        badge = 'ACTIVE';
        badgeColor = const Color(0xFF2E7D32);
        break;
      case 'pending_confirmation':
        badge = 'AWAITING APPROVAL';
        badgeColor = const Color(0xFFE08A00);
        break;
      default:
        badge = 'USED';
        badgeColor = AppPalette.textMuted(context);
    }

    final dark = Theme.of(context).brightness == Brightness.dark;
    final top = _active ? AppColors.accent : (dark ? const Color(0xFF2A2624) : AppColors.stone900.withValues(alpha: 0.82));

    return GestureDetector(
      onTap: () => _showBig(context, pkg, date, time, invoice),
      child: Container(
        decoration: BoxDecoration(
          color: AppPalette.cardBg(context),
          borderRadius: BorderRadius.circular(22),
          boxShadow: AppShadows.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Coloured header
            Container(
              color: top,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Row(
                children: [
                  const Icon(Icons.confirmation_number_outlined, color: AppColors.brandCream, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(pkg,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.brandCream, letterSpacing: -0.3)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.brandCream, borderRadius: BorderRadius.circular(999)),
                    child: Text(badge, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: badgeColor)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _field(context, 'DATE', date != null ? DateFormat('EEE, MMM d, yyyy').format(date) : '—'),
                        const SizedBox(height: 12),
                        _field(context, 'TIME', time.isEmpty ? '—' : time),
                        if (location.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _field(context, 'LOCATION', location),
                        ],
                        const SizedBox(height: 12),
                        _field(context, 'INVOICE', invoice.isEmpty ? 'Being prepared' : invoice),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  _qr(context, 104),
                ],
              ),
            ),
            if (_active && pay.hasBalance)
              Container(
                width: double.infinity,
                color: AppColors.highlight.withValues(alpha: 0.22),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                child: Text(
                  'Balance due on the event day: ${formatPeso(pay.balance)}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context)),
                ),
              ),
            if (_status == 'pending_confirmation')
              Container(
                width: double.infinity,
                color: const Color(0xFFE08A00).withValues(alpha: 0.12),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                child: Text(
                  'Staff are reviewing your receipt. This pass activates once approved.',
                  style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _field(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: AppPalette.textMuted(context))),
        const SizedBox(height: 3),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
      ],
    );
  }

  /// QR is always on a white tile (scanners need contrast, even in dark
  /// mode). Greyed out until the booking is approved.
  Widget _qr(BuildContext context, double size) {
    return Opacity(
      opacity: _active ? 1 : 0.28,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
        child: QrImageView(
          data: _qrData,
          size: size,
          padding: EdgeInsets.zero,
          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.stone900),
          dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: AppColors.stone900),
        ),
      ),
    );
  }

  void _showBig(BuildContext context, String pkg, DateTime? date, String time, String invoice) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(pkg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.stone900)),
              const SizedBox(height: 4),
              Text(
                [if (date != null) DateFormat('MMM d, yyyy').format(date), if (time.isNotEmpty) time].join(' · '),
                style: const TextStyle(fontSize: 12.5, color: AppColors.stone500),
              ),
              const SizedBox(height: 18),
              Opacity(
                opacity: _active ? 1 : 0.28,
                child: QrImageView(
                  data: _qrData,
                  size: 230,
                  padding: EdgeInsets.zero,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.stone900),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: AppColors.stone900),
                ),
              ),
              const SizedBox(height: 14),
              Text(invoice.isEmpty ? 'Invoice being prepared' : invoice,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.accent)),
              if (!_active) ...[
                const SizedBox(height: 8),
                Text(
                  _status == 'completed' ? 'This event is already done.' : 'Not valid until staff approve your booking.',
                  style: const TextStyle(fontSize: 12, color: AppColors.stone500),
                ),
              ],
              const SizedBox(height: 18),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
