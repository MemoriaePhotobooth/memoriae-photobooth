import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../shared/chat_media.dart';
import '../models/booth_package.dart';
import '../models/camera_rental.dart';
import '../models/message_record.dart';
import '../services/booking_repository.dart';
import '../services/camera_rental_repository.dart';
import '../services/pricing_repository.dart';
import '../services/auth_service.dart';
import '../services/message_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import 'booking_invoice_screen.dart';
import '../widgets/app_toast.dart';
import '../widgets/centered_modal.dart';

/// A single support thread between this customer and staff. Unlike the
/// Staff app (which has an inbox of many customers), a customer only ever
/// has one thread — their own — so this goes straight to the chat view.
class UserMessagesScreen extends StatefulWidget {
  /// Set when the customer came from a camera's "Message staff about this
  /// camera" button: shown as an "Asking about" chip and sent to staff,
  /// as a camera card, together with the customer's next message.
  final CameraChatRef? cameraRef;

  const UserMessagesScreen({super.key, this.cameraRef});

  @override
  State<UserMessagesScreen> createState() => _UserMessagesScreenState();
}

class _UserMessagesScreenState extends State<UserMessagesScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  ChatPickedImage? _attachment;
  AppUser? _user;

  /// Camera the customer is asking about. Shown as a chip above the input
  /// and attached to the next message they send, so staff see the camera
  /// right next to the question.
  CameraChatRef? _pendingCamera;

  /// Booking picked from "Share with staff". Same idea as the camera: it
  /// waits above the input and is sent with the customer's next message.
  CameraChatRef? _pendingBooking;

  @override
  void initState() {
    super.initState();
    // Came from a camera's "Message staff" button: show it as a chip above
    // the input. It goes out together with the customer's next message.
    _pendingCamera = widget.cameraRef;
    AuthService.instance.me().then((u) {
      if (mounted) setState(() => _user = u);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _attach() async {
    final image = await ChatMedia.pickImage(context);
    if (image != null && mounted) setState(() => _attachment = image);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final image = _attachment;
    final user = _user;
    final hasRef = _pendingCamera != null || _pendingBooking != null;
    if ((text.isEmpty && image == null && !hasRef) || user == null || _sending) return;
    setState(() => _sending = true);
    try {
      final booking = _pendingBooking;
      final ref = booking ?? _pendingCamera;
      await MessageRepository.sendMessage(
        userId: user.uid,
        customerName: user.fullName,
        // A booking/camera with no typed text still needs a caption.
        text: text.isEmpty && image == null && ref != null
            ? (booking != null ? 'I have a question about this booking.' : 'Is this camera available?')
            : text,
        image: image,
        refType: ref == null ? '' : (booking != null ? 'booking' : 'camera'),
        refId: ref?.id ?? '',
        refTitle: ref?.name ?? '',
        refSubtitle: ref?.subtitle ?? '',
      );
      _controller.clear();
      if (mounted) {
        setState(() {
          _attachment = null;
          _pendingCamera = null; // the camera/booking now travels with the sent message
          _pendingBooking = null;
        });
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, "Couldn't send your message. Please try again.");
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _fmtValue(dynamic v) {
    if (v == null) return '';
    if (v is Timestamp) return DateFormat('MMM d, y').format(v.toDate());
    return v.toString().replaceAll('_', ' ');
  }

  /// Bottom sheet to pick a booking or a camera to share in the chat.
  /// Compact rows with thumbnails so the whole list fits on screen.
  void _openSharePicker(AppUser user) {
    showDialog<void>(
      context: context,
      builder: (sheetContext) {
        return CenteredModal(
          child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Share with staff',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: AppPalette.textPrimary(sheetContext)),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Pick a booking or camera to ask about.',
                              style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(sheetContext)),
                            ),
                          ],
                        ),
                      ),
                      Material(
                        color: AppPalette.surface(sheetContext),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => Navigator.of(sheetContext).pop(),
                          child: SizedBox(width: 34, height: 34, child: Icon(Icons.close_rounded, size: 18, color: AppPalette.textSecondary(sheetContext))),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sheetSection(sheetContext, 'My bookings', icon: CupertinoIcons.calendar),
                        _bookingsList(sheetContext, user),
                        const SizedBox(height: 12),
                        _sheetSection(sheetContext, 'Cameras', icon: CupertinoIcons.camera_fill),
                        _camerasList(sheetContext, user),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        );
      },
    );
  }

  Future<void> _confirmDeleteMessage(MessageRecord m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text("This removes the message from the chat for you and for staff. This can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await MessageRepository.deleteMessage(m);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, "Couldn't delete that message. Check your connection and try again.");
    }
  }

  Widget _sheetSection(BuildContext context, String label, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10, left: 2),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: AppColors.accent),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context)),
          ),
        ],
      ),
    );
  }

  /// Rounded photo tile for the share list. Handles `data:` URIs and
  /// http(s) URLs. When there is no photo (for example a booking whose
  /// package was later removed) it shows a soft branded placeholder instead
  /// of a blank box.
  Widget _sheetThumb(BuildContext context, String imageUrl, IconData fallback, {double size = 56}) {
    final placeholder = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accentTint(0.16), AppColors.accentTint(0.06)],
        ),
      ),
      child: Icon(fallback, size: size * 0.42, color: AppColors.accent.withValues(alpha: 0.75)),
    );
    Widget child = placeholder;
    final bytes = decodeDataUriImage(imageUrl);
    if (bytes != null) {
      child = Image.memory(bytes, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder);
    } else if (imageUrl.startsWith('http')) {
      child = Image.network(imageUrl, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(14), child: SizedBox(width: size, height: size, child: child));
  }

  Widget _shareRow(
    BuildContext context, {
    required Widget thumb,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? badge,
    Color? badgeColor,
    bool dimmed = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: dimmed ? 0.62 : 1,
        child: Material(
          color: AppPalette.surface(context),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  thumb,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context)),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, height: 1.3, color: AppPalette.textMuted(context)),
                        ),
                        if (badge != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (badgeColor ?? AppColors.accent).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: badgeColor ?? AppColors.accent),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: AppColors.accentTint(0.10), shape: BoxShape.circle),
                    child: const Icon(Icons.add_rounded, size: 20, color: AppColors.accent),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bookingsList(BuildContext context, AppUser user) {
    return StreamBuilder<List<BoothPackage>>(
      stream: PricingRepository.watchPackages(),
      builder: (context, pkgSnap) {
        final packages = pkgSnap.data ?? const <BoothPackage>[];
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: BookingRepository.watchBookingsForUser(user.uid),
          builder: (context, snap) {
            final bookings = snap.data ?? const <Map<String, dynamic>>[];
            if (bookings.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('No bookings yet.', style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context))),
              );
            }
            return Column(
              children: [
                for (final b in bookings.take(10))
                  Builder(builder: (_) {
                    final name = _fmtValue(b['packageName']).isEmpty ? 'Booking' : _fmtValue(b['packageName']);
                    final subtitle = [_fmtValue(b['date']), _fmtValue(b['time']), _fmtValue(b['status'])]
                        .where((x) => x.isNotEmpty)
                        .join(' · ');
                    final image = _packageImageFor(packages, b);
                    final status = (b['status'] ?? '').toString();
                    final inactive = status == 'cancelled' || status == 'rejected';
                    final when = [_fmtValue(b['date']), _fmtValue(b['time'])].where((x) => x.isNotEmpty).join(' · ');
                    return _shareRow(
                      context,
                      thumb: _sheetThumb(context, image, CupertinoIcons.calendar),
                      title: name,
                      subtitle: when,
                      badge: _statusLabel(status),
                      badgeColor: inactive ? const Color(0xFFB3261E) : _statusColor(status),
                      dimmed: inactive,
                      onTap: () {
                        Navigator.of(context).pop();
                        setState(() {
                          _pendingCamera = null;
                          _pendingBooking = CameraChatRef(id: (b['id'] ?? '').toString(), name: name, subtitle: subtitle);
                        });
                      },
                    );
                  }),
              ],
            );
          },
        );
      },
    );
  }

  Widget _camerasList(BuildContext context, AppUser user) {
    return StreamBuilder<List<CameraOption>>(
      stream: PricingRepository.watchCameraOptions(),
      builder: (context, snap) {
        final cameras = snap.data ?? const <CameraOption>[];
        if (cameras.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('No cameras listed.', style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context))),
          );
        }
        return Column(
          children: [
            for (final c in cameras)
              _shareRow(
                context,
                thumb: _sheetThumb(context, c.imageUrl, CupertinoIcons.camera_fill),
                title: c.name,
                subtitle: 'from ${formatPeso(c.dailyRate)} / day',
                onTap: () {
                  Navigator.of(context).pop();
                  setState(() {
                    _pendingBooking = null;
                    _pendingCamera = CameraChatRef(id: c.id, name: c.name, subtitle: 'from ${formatPeso(c.dailyRate)} / day');
                  });
                },
              ),
          ],
        );
      },
    );
  }

  /// Shows the shared item as a card. Cameras get a live availability
  /// check; bookings show the details captured when they were shared.
  Widget _refCard(BuildContext context, MessageRecord m, List<Map<String, dynamic>> bookings) {
    final isCamera = m.refType == 'camera';
    if (!isCamera) {
      for (final b in bookings) {
        if ((b['id'] ?? '').toString() == m.refId) {
          return Container(margin: const EdgeInsets.only(bottom: 8), child: _confirmationCard(context, b, shadow: false));
        }
      }
    }
    final textCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isCamera ? 'CAMERA' : 'BOOKING',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: AppPalette.textMuted(context)),
        ),
        const SizedBox(height: 2),
        Text(m.refTitle, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
        if (m.refSubtitle.isNotEmpty)
          Text(m.refSubtitle, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
        if (isCamera) ...[
          const SizedBox(height: 6),
          _cameraAvailability(context, m.refId),
        ],
      ],
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.divider(context)),
      ),
      child: isCamera
          ? StreamBuilder<List<CameraOption>>(
              stream: PricingRepository.watchCameraOptions(),
              builder: (context, snap) {
                var image = '';
                for (final c in snap.data ?? const <CameraOption>[]) {
                  if (c.id == m.refId) image = c.imageUrl;
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sheetThumb(context, image, CupertinoIcons.camera_fill, size: 64),
                    const SizedBox(width: 12),
                    Expanded(child: textCol),
                  ],
                );
              },
            )
          : textCol,
    );
  }

  Widget _cameraAvailability(BuildContext context, String cameraId) {
    return StreamBuilder<List<CameraRental>>(
      stream: CameraRentalRepository.watchAllActiveRentals(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Text('Checking availability…', style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)));
        }
        final rented = snap.data!.any((r) => r.cameraId == cameraId);
        final color = rented ? Colors.redAccent : const Color(0xFF34C759);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(
              rented ? 'Rented out right now' : 'Available now',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // Auto "Booking confirmation" card (like a Shopee order confirmation)
  // ---------------------------------------------------------------------

  /// The customer's newest booking that isn't cancelled/rejected. It is
  /// shown in the thread automatically — nothing is written to Firestore.
  Map<String, dynamic>? _latestActiveBooking(List<Map<String, dynamic>> bookings) {
    for (final b in bookings) {
      final status = (b['status'] ?? '').toString();
      if (status == 'cancelled' || status == 'rejected') continue;
      return b;
    }
    return null;
  }

  DateTime _bookingTime(Map<String, dynamic> b) {
    final ts = b['createdAt'];
    return ts is Timestamp ? ts.toDate() : DateTime.now();
  }

  num _num(dynamic v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

  String _statusLabel(String status) {
    switch (status) {
      case 'awaiting_receipt':
        return 'Awaiting payment';
      case 'pending_confirmation':
        return 'Pending confirmation';
      case 'confirmed':
        return 'Confirmed';
      case 'completed':
        return 'Completed';
      default:
        final t = status.replaceAll('_', ' ');
        return t.isEmpty ? 'Booked' : t[0].toUpperCase() + t.substring(1);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':
      case 'completed':
        return const Color(0xFF34C759);
      case 'pending_confirmation':
        return const Color(0xFFE0A100);
      default:
        return AppColors.accent;
    }
  }

  void _viewBooking(Map<String, dynamic> b) {
    final status = (b['status'] ?? '').toString();
    if (BookingInvoiceScreen.isAvailable(status)) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookingInvoiceScreen(booking: b)));
    } else {
      Navigator.of(context).pushNamed('/bookings');
    }
  }

  Widget _confirmRow(BuildContext context, String label, String value, {Color? valueColor, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: valueColor ?? AppPalette.textPrimary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The package photo for a booking. Matches on the booking's `packageId`
  /// first (it survives a package being renamed), then on the saved name.
  String _packageImageFor(List<BoothPackage> packages, Map<String, dynamic> b) {
    final packageId = (b['packageId'] ?? '').toString();
    final name = _fmtValue(b['packageName']).trim().toLowerCase();
    if (packageId.isNotEmpty) {
      for (final p in packages) {
        if (p.id == packageId && p.imageUrl.isNotEmpty) return p.imageUrl;
      }
    }
    if (name.isNotEmpty) {
      for (final p in packages) {
        if (p.name.trim().toLowerCase() == name && p.imageUrl.isNotEmpty) return p.imageUrl;
      }
    }
    return '';
  }

  /// Package photo for the booking card: handles `data:` URIs and http(s)
  /// URLs, with an icon fallback while loading or when there is no photo.
  Widget _bookingThumb(BuildContext context, String imageUrl, {double size = 64}) {
    final fallback = Container(
      width: size,
      height: size,
      color: AppPalette.cardBg(context),
      alignment: Alignment.center,
      child: Icon(CupertinoIcons.calendar, size: 22, color: AppPalette.textMuted(context)),
    );
    Widget child = fallback;
    final bytes = decodeDataUriImage(imageUrl);
    if (bytes != null) {
      child = Image.memory(bytes, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback);
    } else if (imageUrl.startsWith('http')) {
      child = Image.network(imageUrl, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: size, height: size, child: child));
  }

  /// "Booking confirmation" card: package photo, booking ID, date, time,
  /// guests, location, status and a "View details" button. Used for the
  /// automatic card and for bookings shared in the chat.
  Widget _confirmationCard(BuildContext context, Map<String, dynamic> b, {bool shadow = true}) {
    final status = (b['status'] ?? '').toString();
    final name = _fmtValue(b['packageName']).isEmpty ? 'Booking' : _fmtValue(b['packageName']);
    final addOns = b['addOns'] is List ? (b['addOns'] as List).length : 0;
    final total = _num(b['price']) + _num(b['addOnsPrice']);
    final id = (b['id'] ?? '').toString();
    final bookingId = (b['invoiceNo'] ?? '').toString().isNotEmpty
        ? b['invoiceNo'].toString()
        : (id.length > 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase());
    final location = (b['location'] ?? '').toString();
    final summary = [
      if (addOns > 0) '$addOns add-on${addOns == 1 ? '' : 's'}',
      formatPeso(total.round()),
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.divider(context)),
        boxShadow: shadow ? AppShadows.soft : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded, size: 16, color: AppColors.accent),
              const SizedBox(width: 6),
              Text('Booking confirmation', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                StreamBuilder<List<BoothPackage>>(
                  stream: PricingRepository.watchPackages(),
                  builder: (context, snap) {
                    return _bookingThumb(context, _packageImageFor(snap.data ?? const <BoothPackage>[], b));
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
                      const SizedBox(height: 2),
                      Text(summary, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _confirmRow(context, 'Booking ID', bookingId),
          _confirmRow(context, 'Date', _fmtValue(b['date'])),
          _confirmRow(context, 'Time', _fmtValue(b['time'])),
          if (_num(b['guests']) > 0) _confirmRow(context, 'Guests', _num(b['guests']).toInt().toString()),
          if (location.isNotEmpty) _confirmRow(context, 'Location', location),
          _confirmRow(context, 'Status', _statusLabel(status), valueColor: _statusColor(status), bold: true),
          const SizedBox(height: 10),
          Material(
            color: AppPalette.surface(context),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _viewBooking(b),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text('View details', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Staff greeting + "Booking confirmation" card for the customer's booking.
  Widget _bookingMessage(BuildContext context, Map<String, dynamic> b, DateTime at) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: const BoxConstraints(maxWidth: 300),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Memoriae Staff", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppPalette.textMuted(context))),
                  const SizedBox(height: 3),
                  Text(
                    'Thanks for your booking! Please confirm that your details are correct.',
                    style: TextStyle(fontSize: 13, color: AppPalette.textPrimary(context)),
                  ),
                  const SizedBox(height: 4),
                  Text(DateFormat('MMM d, h:mm a').format(at), style: TextStyle(fontSize: 10, color: AppPalette.textMuted(context))),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _confirmationCard(context, b),
          ],
        ),
      ),
    );
  }

  /// "Asking about: <camera>" chip above the input, with an X to remove it.
  Widget _cameraChip(BuildContext context, CameraChatRef cam, {bool booking = false, VoidCallback? onRemove}) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: AppColors.accentTint(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accentTint(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(booking ? CupertinoIcons.calendar : CupertinoIcons.camera_fill, size: 15, color: AppColors.accent),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Asking about', style: TextStyle(fontSize: 10, color: AppPalette.textMuted(context))),
                Text(
                  cam.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context)),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'Remove',
            onPressed: _sending ? null : (onRemove ?? () => setState(() => _pendingCamera = null)),
            icon: Icon(Icons.close, size: 16, color: AppPalette.textMuted(context)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.accentTint(0.12), shape: BoxShape.circle),
                child: const Icon(Icons.support_agent, size: 20, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Chat with Staff", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                    Text("Questions about your booking? Message us here.", style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: user == null
              ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
              : StreamBuilder<List<MessageRecord>>(
                  stream: MessageRepository.watchThread(user.uid),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            "Couldn't load your messages. Check your connection and try again.",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
                          ),
                        ),
                      );
                    }
                    final thread = snapshot.data ?? const <MessageRecord>[];

                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
                    }
                    return StreamBuilder<List<Map<String, dynamic>>>(
                      stream: BookingRepository.watchBookingsForUser(user.uid),
                      builder: (context, bookingSnap) {
                    final latest = _latestActiveBooking(bookingSnap.data ?? const <Map<String, dynamic>>[]);
                    final items = <_ChatItem>[
                      for (final m in thread) _ChatItem(at: m.sentAt, message: m),
                      if (latest != null) _ChatItem(at: _bookingTime(latest), booking: latest),
                    ]..sort((a, b) => a.at.compareTo(b.at));

                    if (items.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            "No messages yet — say hi! Staff usually reply within the day.",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
                          ),
                        ),
                      );
                    }

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_scrollController.hasClients) {
                        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                      }
                    });

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final item = items[i];
                        if (item.booking != null) return _bookingMessage(context, item.booking!, item.at);
                        final m = item.message!;
                        return Align(
                          alignment: m.fromStaff ? Alignment.centerLeft : Alignment.centerRight,
                          child: GestureDetector(
                            // Press and hold your own message to delete it.
                            onLongPress: m.fromStaff ? null : () => _confirmDeleteMessage(m),
                            onSecondaryTap: m.fromStaff ? null : () => _confirmDeleteMessage(m),
                            child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            constraints: const BoxConstraints(maxWidth: 280),
                            decoration: BoxDecoration(
                              color: m.fromStaff ? AppPalette.surface(context) : AppColors.accent,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (m.fromStaff)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 3),
                                    child: Text(
                                      "Memoriae Staff",
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppPalette.textMuted(context)),
                                    ),
                                  ),
                                if (m.hasRef) _refCard(context, m, bookingSnap.data ?? const <Map<String, dynamic>>[]),
                                if (m.hasImage)
                                  Padding(
                                    padding: EdgeInsets.only(bottom: m.caption.isNotEmpty ? 6 : 0),
                                    child: ChatImage(imageId: m.imageId, maxWidth: 240, radius: 12),
                                  ),
                                if (m.caption.isNotEmpty)
                                  Text(
                                    m.caption,
                                    style: TextStyle(fontSize: 13, color: m.fromStaff ? AppPalette.textPrimary(context) : AppColors.onAccent),
                                  ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      DateFormat('MMM d, h:mm a').format(m.sentAt),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: m.fromStaff ? AppPalette.textMuted(context) : AppColors.onAccent.withValues(alpha: 0.65),
                                      ),
                                    ),
                                    if (!m.fromStaff) ...[
                                      const SizedBox(width: 10),
                                      InkWell(
                                        onTap: () => _confirmDeleteMessage(m),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Padding(
                                          padding: const EdgeInsets.all(3),
                                          child: Icon(Icons.delete_outline_rounded, size: 15, color: AppColors.onAccent.withValues(alpha: 0.8)),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          ),
                        );
                      },
                    );
                      },
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_pendingCamera != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 0, 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _cameraChip(context, _pendingCamera!),
                    ),
                  ),
                if (_pendingBooking != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 0, 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _cameraChip(context, _pendingBooking!, booking: true, onRemove: () => setState(() => _pendingBooking = null)),
                    ),
                  ),
                if (_attachment != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 0, 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ChatAttachmentPreview(image: _attachment!, onRemove: _sending ? null : () => setState(() => _attachment = null)),
                    ),
                  ),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Share a booking or camera',
                      onPressed: (_sending || user == null) ? null : () => _openSharePicker(user),
                      icon: Icon(Icons.ios_share, color: AppPalette.textMuted(context)),
                    ),
                    IconButton(
                      tooltip: 'Send a photo',
                      onPressed: (_sending || user == null) ? null : _attach,
                      icon: Icon(Icons.add_photo_alternate_outlined, color: AppPalette.textMuted(context)),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        style: TextStyle(color: AppPalette.textPrimary(context)),
                        decoration: InputDecoration(
                          hintText: _attachment != null
                              ? "Add a caption…"
                              : (_pendingCamera != null
                                  ? "Ask about this camera…"
                                  : (_pendingBooking != null ? "Ask about this booking…" : "Type a message…")),
                          hintStyle: TextStyle(color: AppPalette.textMuted(context), fontSize: 13),
                          filled: true,
                          fillColor: AppPalette.surface(context),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: (_sending || user == null) ? null : _send,
                      style: IconButton.styleFrom(backgroundColor: AppColors.accent),
                      icon: const Icon(Icons.send, size: 18, color: AppColors.onAccent),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One row of the chat list: either a real message or the auto booking card.
class _ChatItem {
  final DateTime at;
  final MessageRecord? message;
  final Map<String, dynamic>? booking;
  const _ChatItem({required this.at, this.message, this.booking});
}