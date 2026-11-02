import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/booth_package.dart';
import '../services/booking_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Bell icon for the dashboard header. Badges with the number of the
/// customer's bookings that staff/admin just approved, declined, or
/// auto-cancelled (`notifyCustomer == true` on the `bookings` doc — see
/// `BookingRepository.watchNotifications`). Tapping it opens a sheet
/// listing those bookings; tapping a booking in that panel marks it seen
/// (`BookingRepository.markNotificationSeen`), which clears the badge.
///
/// Renders as a plain, inert bell (no stream, no badge) when [userId] is
/// null — e.g. while the current user is still loading.
class NotificationBell extends StatelessWidget {
  final String? userId;

  /// Circle colour behind the bell. Defaults to the muted surface colour;
  /// pass a card colour when the bell sits on a grouped (grey) background.
  final Color? background;

  const NotificationBell({super.key, required this.userId, this.background});

  @override
  Widget build(BuildContext context) {
    final uid = userId;
    if (uid == null) return _bellButton(context, count: 0, onTap: null);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: BookingRepository.watchNotifications(uid),
      builder: (context, snap) {
        final notifications = snap.data ?? const <Map<String, dynamic>>[];
        return _bellButton(
          context,
          count: notifications.length,
          onTap: () => _openPanel(context, uid),
        );
      },
    );
  }

  Widget _bellButton(BuildContext context, {required int count, required VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: background ?? AppPalette.surface(context), shape: BoxShape.circle),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(CupertinoIcons.bell, color: AppPalette.textPrimary(context), size: 21),
            if (count > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  constraints: const BoxConstraints(minWidth: 16),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppPalette.bg(context), width: 1.5),
                  ),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.onAccent, height: 1.2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Opens the notification panel. Wide screens get an anchored dropdown
  /// under the bell (top-right, fade + scale — same as the Admin/Staff
  /// apps); narrow/mobile screens get a panel that drops down from the top
  /// with side margins, since a 400px dropdown wouldn't fit.
  void _openPanel(BuildContext context, String uid) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    showGeneralDialog<void>(
      context: context,
      barrierLabel: 'Notifications',
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: isWide ? 0.05 : 0.30),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, __) {
        final panel = _NotificationPanel(userId: uid, isWide: isWide);
        if (isWide) {
          return Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 72, right: 24),
              child: Material(color: Colors.transparent, child: SizedBox(width: 400, child: panel)),
            ),
          );
        }
        return SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Material(color: Colors.transparent, child: panel),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        if (isWide) {
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
              alignment: Alignment.topRight,
              child: child,
            ),
          );
        }
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -0.25), end: Offset.zero).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }
}

enum _NotifFilter { all, confirmed, declined }

/// The panel itself: "Notifications" header with "Mark all as read",
/// All / Confirmed / Declined tabs with unread-count pills, and a tile per
/// booking update (tinted icon avatar, bold title, relative time + status,
/// unread dot). It keeps its own live stream and remembers every item it
/// has shown while open, so tapping one marks it seen (clearing the bell
/// badge) but the tile stays visible — with its dot gone — until you close
/// the panel, instead of vanishing under your finger.
class _NotificationPanel extends StatefulWidget {
  final String userId;
  final bool isWide;
  const _NotificationPanel({required this.userId, required this.isWide});

  @override
  State<_NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends State<_NotificationPanel> {
  _NotifFilter _filter = _NotifFilter.all;
  final Map<String, Map<String, dynamic>> _items = {};
  final Set<String> _readIds = {};
  late final Stream<List<Map<String, dynamic>>> _stream = BookingRepository.watchNotifications(widget.userId);

  DateTime _updatedAt(Map<String, dynamic> b) {
    final t = b['statusUpdatedAt'] ?? b['createdAt'];
    return t is Timestamp ? t.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _timeAgo(DateTime dt) {
    if (dt.millisecondsSinceEpoch == 0) return 'Recently';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
    if (diff.inHours < 24) return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  }

  Future<void> _markRead(String id) async {
    if (_readIds.contains(id)) return;
    setState(() => _readIds.add(id));
    try {
      await BookingRepository.markNotificationSeen(id);
    } catch (_) {
      if (mounted) setState(() => _readIds.remove(id));
    }
  }

  Future<void> _markAllRead() async {
    final ids = _items.keys.where((id) => !_readIds.contains(id)).toList();
    setState(() => _readIds.addAll(ids));
    for (final id in ids) {
      try {
        await BookingRepository.markNotificationSeen(id);
      } catch (_) {}
    }
  }

  bool _isConfirmed(Map<String, dynamic> b) => (b['status'] as String? ?? '') == 'confirmed';
  bool _isDeclined(Map<String, dynamic> b) => (b['status'] as String? ?? '') == 'cancelled';

  @override
  Widget build(BuildContext context) {
    final maxHeight = widget.isWide ? 520.0 : MediaQuery.of(context).size.height * 0.75;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card,
        border: Border.all(color: AppPalette.divider(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snap) {
          for (final b in snap.data ?? const <Map<String, dynamic>>[]) {
            final id = b['id'] as String?;
            if (id != null) _items[id] = b;
          }
          final all = _items.values.toList()..sort((a, b) => _updatedAt(b).compareTo(_updatedAt(a)));
          final visible = switch (_filter) {
            _NotifFilter.all => all,
            _NotifFilter.confirmed => all.where(_isConfirmed).toList(),
            _NotifFilter.declined => all.where(_isDeclined).toList(),
          };
          int unread(Iterable<Map<String, dynamic>> l) => l.where((b) => !_readIds.contains(b['id'])).length;
          final unreadAll = unread(all);

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 8, 4),
                child: Row(
                  children: [
                    Text("Notifications", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                    const Spacer(),
                    TextButton(
                      onPressed: unreadAll == 0 ? null : _markAllRead,
                      style: TextButton.styleFrom(foregroundColor: AppColors.accent, padding: const EdgeInsets.symmetric(horizontal: 8)),
                      child: const Text("Mark all as read", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close, size: 19, color: AppPalette.textSecondary(context)),
                      splashRadius: 18,
                      visualDensity: VisualDensity.compact,
                      tooltip: "Close",
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Row(
                  children: [
                    _NotifTabButton(
                      label: 'All',
                      count: unreadAll,
                      selected: _filter == _NotifFilter.all,
                      onTap: () => setState(() => _filter = _NotifFilter.all),
                    ),
                    const SizedBox(width: 22),
                    _NotifTabButton(
                      label: 'Confirmed',
                      count: unread(all.where(_isConfirmed)),
                      selected: _filter == _NotifFilter.confirmed,
                      onTap: () => setState(() => _filter = _NotifFilter.confirmed),
                    ),
                    const SizedBox(width: 22),
                    _NotifTabButton(
                      label: 'Declined',
                      count: unread(all.where(_isDeclined)),
                      selected: _filter == _NotifFilter.declined,
                      onTap: () => setState(() => _filter = _NotifFilter.declined),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppPalette.divider(context)),
              Flexible(
                child: visible.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text("You're all caught up.", style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context))),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: AppPalette.divider(context)),
                        itemBuilder: (context, i) {
                          final b = visible[i];
                          final id = b['id'] as String? ?? '';
                          return _NotificationTile(
                            booking: b,
                            unread: !_readIds.contains(id),
                            timeAgo: _timeAgo(_updatedAt(b)),
                            onTap: () => _markRead(id),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One tab — label, an unread-count pill, and a short accent underline
/// when active (same look as the Admin/Staff panels).
class _NotifTabButton extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _NotifTabButton({required this.label, required this.count, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppPalette.textPrimary(context) : AppPalette.textMuted(context),
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(999)),
                    child: Text('$count', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppColors.onAccent)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 2,
              width: 28,
              color: selected ? AppColors.accent : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> booking;
  final bool unread;
  final String timeAgo;
  final VoidCallback onTap;
  const _NotificationTile({required this.booking, required this.unread, required this.timeAgo, required this.onTap});

  bool get _approved => (booking['status'] as String? ?? '') == 'confirmed';
  bool get _cancelled => (booking['status'] as String? ?? '') == 'cancelled';
  /// Staff moved this booking to a new date/time — see
  /// `BookingRepository.rescheduleBooking` (Staff app) which sets
  /// `notifyType: 'rescheduled'` alongside `notifyCustomer: true`. Takes
  /// priority over the plain confirmed/declined look even if the status
  /// also happens to be `confirmed`, since "moved" is the news here.
  bool get _rescheduled => (booking['notifyType'] as String? ?? '') == 'rescheduled';

  /// Staff sent the customer's refund back by GCash — see
  /// `markRefunded` in the Staff/Admin booking repositories, which sets
  /// `notifyType: 'refunded'`. The booking itself stays `cancelled`.
  bool get _refunded => (booking['notifyType'] as String? ?? '') == 'refunded';
  int get _refundAmount => (booking['refundAmount'] as num?)?.toInt() ?? 0;
  bool get _refundPending => _cancelled && !_refunded && booking['refundStatus'] == 'pending';

  Color get _color {
    if (_refunded) return const Color(0xFF2E7D32);
    if (_rescheduled) return const Color(0xFF1565C0);
    if (_approved) return const Color(0xFF2E7D32);
    if (_cancelled) return const Color(0xFFB3261E);
    return AppColors.accent;
  }

  IconData get _icon {
    if (_refunded) return Icons.payments_rounded;
    if (_rescheduled) return Icons.event_repeat;
    if (_approved) return Icons.check_circle;
    if (_cancelled) return Icons.cancel;
    return Icons.info;
  }

  String get _title {
    if (_refunded) return "Your refund has been sent";
    if (_rescheduled) return "Your booking schedule was moved";
    if (_approved) return "Your booking is confirmed!";
    if (_cancelled) return "Your booking was declined";
    return "Booking update";
  }

  String get _category {
    if (_refunded) return "Refunded";
    if (_rescheduled) return "Rescheduled";
    if (_approved) return "Confirmed";
    if (_cancelled) return "Declined";
    return "Update";
  }

  @override
  Widget build(BuildContext context) {
    final packageName = booking['packageName'] as String? ?? 'Booking';
    final time = booking['time'] as String? ?? '';
    final ts = booking['date'];
    final date = ts is Timestamp ? ts.toDate() : null;
    final reason = booking['rejectionReason'] as String?;
    final prevTs = booking['previousDate'];
    final prevDate = prevTs is Timestamp ? prevTs.toDate() : null;
    final prevTime = booking['previousTime'] as String?;
    final rescheduleReason = booking['rescheduleReason'] as String?;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _color.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Icon(_icon, size: 18, color: _color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context)),
                  ),
                  const SizedBox(height: 3),
                  Text("$timeAgo · $_category", style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppPalette.surface(context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(packageName, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context))),
                        if (_rescheduled && prevDate != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            "Was: ${DateFormat('EEE, MMM d, yyyy').format(prevDate)}${(prevTime ?? '').isEmpty ? '' : ' · $prevTime'}",
                            style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context), decoration: TextDecoration.lineThrough),
                          ),
                          if (date != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                "Now: ${DateFormat('EEE, MMM d, yyyy').format(date)}${time.isEmpty ? '' : ' · $time'}",
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF1565C0)),
                              ),
                            ),
                        ] else if (date != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            "${DateFormat('EEE, MMM d, yyyy').format(date)}${time.isEmpty ? '' : ' · $time'}",
                            style: TextStyle(fontSize: 11.5, color: AppPalette.textSecondary(context)),
                          ),
                        ],
                        if (_rescheduled && rescheduleReason != null && rescheduleReason.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text("Note: $rescheduleReason", style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
                        ],
                        if (_cancelled && !_refunded && reason != null && reason.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text("Reason: $reason", style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
                        ],
                        if (_refunded) ...[
                          const SizedBox(height: 4),
                          Text(
                            "${formatPeso(_refundAmount)} was sent to your GCash.",
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32)),
                          ),
                        ],
                        if (_refundPending) ...[
                          const SizedBox(height: 4),
                          Text(
                            "Refund of ${formatPeso(_refundAmount)} pending — we'll send it to your GCash.",
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFE08A00)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (unread)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
              ),
          ],
        ),
      ),
    );
  }
}