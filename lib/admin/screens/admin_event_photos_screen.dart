import '../../shared/top_toast.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../services/event_photo_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/admin_offline_strip.dart';
import '../widgets/pagination_bar.dart';

const Color _accentDark = Color(0xFF3F0F11);

bool _isToday(DateTime d) {
  final n = DateTime.now();
  return d.year == n.year && d.month == n.month && d.day == n.day;
}

/// Keeps content readable on very wide screens.
Widget _centered(Widget child) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 980), child: child),
    );

/// Admin view of event photos. Lists today's confirmed bookings (so photos can
/// be added right away) plus any booking that already has photos. Open one to
/// add photos (today only), look through them, or remove a wrong one.
class AdminEventPhotosScreen extends StatefulWidget {
  const AdminEventPhotosScreen({super.key});

  @override
  State<AdminEventPhotosScreen> createState() => _AdminEventPhotosScreenState();
}

class _AdminEventPhotosScreenState extends State<AdminEventPhotosScreen> {
  int _page = 0;

  static List<EventPhotoBooking> _merge(List<EventPhotoBooking> today, List<EventPhotoBooking> withPhotos) {
    final byId = {for (final b in today) b.id: b};
    for (final b in withPhotos) {
      byId[b.id] = b;
    }
    return byId.values.toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<EventPhotoBooking>>(
      stream: EventPhotoRepository.watchTodayBookings(),
      builder: (context, todaySnap) => StreamBuilder<List<EventPhotoBooking>>(
        stream: EventPhotoRepository.watchBookingsWithPhotos(),
        builder: (context, photoSnap) {
          if (todaySnap.hasError || photoSnap.hasError) {
            return _message(context, Icons.error_outline, "Couldn't load event photos.");
          }
          if (!todaySnap.hasData || !photoSnap.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.accent));
          }
          final bookings = _merge(todaySnap.data!, photoSnap.data!);
          _page = PageWindow.clamp(_page, bookings.length);
          final totalPhotos = bookings.fold<int>(0, (sum, b) => sum + b.count);
          return Column(
            children: [
              const AdminOfflineStrip(),
              Expanded(
                child: bookings.isEmpty
                    ? _message(context, Icons.photo_library_outlined, "No event photos yet",
                        "Today's confirmed bookings will appear here so you can add photos right away.")
                    : Column(
                        children: [
                          Expanded(
                            child: _centered(
                              ListView.separated(
                                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                                itemCount: PageWindow.slice(bookings, _page).length + 1,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (context, i) {
                                  if (i == 0) return _summary(context, bookings.length, totalPhotos);
                                  return _bookingTile(context, PageWindow.slice(bookings, _page)[i - 1]);
                                },
                              ),
                            ),
                          ),
                          PaginationBar(
                            page: _page,
                            pageCount: PageWindow.pageCount(bookings.length),
                            onPageChanged: (p) => setState(() => _page = p),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _summary(BuildContext context, int albums, int photos) {
    Widget stat(IconData icon, String value, String label) => Expanded(
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1)),
                  Text(label, style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.75))),
                ],
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [AppColors.accent, _accentDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: AppShadows.accentGlowSmall,
      ),
      child: Row(
        children: [
          stat(Icons.photo_library_rounded, "$albums", albums == 1 ? "event album" : "event albums"),
          stat(Icons.photo_camera_rounded, "$photos", photos == 1 ? "photo taken" : "photos taken"),
        ],
      ),
    );
  }

  Widget _bookingTile(BuildContext context, EventPhotoBooking b) {
    final today = _isToday(b.date);
    final name = b.customerName.trim().isEmpty ? 'Customer' : b.customerName.trim();
    final muted = AppPalette.textMuted(context);
    Widget meta(IconData icon, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: muted),
            const SizedBox(width: 4),
            Text(text, style: TextStyle(fontSize: 11.5, color: AppPalette.textSecondary(context))),
          ],
        );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => _AdminBookingPhotosPage(booking: b)),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppPalette.cardBg(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: today ? AppColors.accent.withValues(alpha: 0.35) : AppPalette.divider(context)),
            boxShadow: AppShadows.soft,
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(colors: [AppColors.accent, _accentDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: Text(name[0].toUpperCase(),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
                        ),
                        if (today) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                            child: const Text("TODAY",
                                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: Color(0xFF15803D))),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(8)),
                      child: Text(b.packageName,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accent)),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 12,
                      runSpacing: 3,
                      children: [
                        meta(Icons.calendar_today_rounded, DateFormat('MMM d, yyyy').format(b.date)),
                        meta(Icons.schedule_rounded, b.time),
                        meta(Icons.tag_rounded, b.bookingRef),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              b.count > 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                      decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.photo_camera_rounded, size: 15, color: AppColors.accent),
                          const SizedBox(height: 2),
                          Text("${b.count}",
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.accent, height: 1.1)),
                        ],
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.add_a_photo_outlined, size: 14, color: AppColors.accent),
                          SizedBox(width: 5),
                          Text("Add", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent)),
                        ],
                      ),
                    ),
              Icon(Icons.chevron_right_rounded, color: muted),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _message(BuildContext context, IconData icon, String title, [String? subtitle]) => Center(
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

class _AdminBookingPhotosPage extends StatefulWidget {
  final EventPhotoBooking booking;
  const _AdminBookingPhotosPage({required this.booking});

  @override
  State<_AdminBookingPhotosPage> createState() => _AdminBookingPhotosPageState();
}

class _AdminBookingPhotosPageState extends State<_AdminBookingPhotosPage> {
  final _picker = ImagePicker();
  bool _uploading = false;
  int _done = 0;
  int _total = 0;
  int _photoPage = 0;

  EventPhotoBooking get booking => widget.booking;

  /// Uploads are only for the event day, same as the Firestore rule.
  bool get _canUpload {
    return _isToday(booking.date) && (booking.status == 'confirmed' || booking.status == 'completed');
  }

  String _mimeFor(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  void _snack(String msg) {
    if (!mounted) return;
    TopToast.show(context, msg);
  }

  Future<void> _addPhotos() async {
    if (_uploading) return;
    List<XFile> picked;
    try {
      picked = await _picker.pickMultiImage(maxWidth: 1280, imageQuality: 65);
    } catch (e) {
      _snack("Couldn't open your photos: $e");
      return;
    }
    if (picked.isEmpty || !mounted) return;

    setState(() {
      _uploading = true;
      _done = 0;
      _total = picked.length;
    });
    var queued = 0;
    var failed = 0;
    for (final file in picked) {
      try {
        final bytes = await file.readAsBytes();
        final write = EventPhotoRepository.add(
          bookingId: booking.id,
          userId: booking.userId,
          bytes: bytes,
          mime: _mimeFor(file.name),
        );
        try {
          await write.timeout(const Duration(seconds: 20));
        } on TimeoutException {
          // No signal: Firestore keeps the write and sends it when back online.
          queued++;
          write.catchError((_) => _snack("A photo failed to upload. Try adding it again."));
        }
      } catch (_) {
        failed++;
      }
      if (!mounted) return;
      setState(() => _done++);
    }
    if (!mounted) return;
    setState(() => _uploading = false);
    final ok = picked.length - queued - failed;
    final parts = [
      "$ok uploaded",
      if (queued > 0) "$queued waiting for connection",
      if (failed > 0) "$failed failed (too large or no connection)",
    ];
    _snack("${parts.join(', ')}.");
  }

  Future<void> _confirmDelete(EventPhoto photo) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete this photo?"),
        content: const Text("The customer won't be able to see it anymore. This can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await EventPhotoRepository.delete(photo);
    } catch (e) {
      _snack("Couldn't delete: $e");
    }
  }

  /// Full-screen viewer: swipe (or use the arrows) through every photo.
  void _openViewer(List<EventPhoto> photos, int start) {
    final controller = PageController(initialPage: start);
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        var index = start;
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              final p = photos[index];
              Widget arrow(IconData icon, bool left) {
                final enabled = left ? index > 0 : index < photos.length - 1;
                if (!enabled) return const SizedBox(width: 48);
                return IconButton(
                  iconSize: 30,
                  color: Colors.white,
                  icon: Icon(icon),
                  onPressed: () => controller.animateToPage(index + (left ? -1 : 1),
                      duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                );
              }

              return SafeArea(
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: controller,
                      itemCount: photos.length,
                      onPageChanged: (i) => setLocal(() => index = i),
                      itemBuilder: (_, i) => InteractiveViewer(
                        maxScale: 5,
                        child: Center(child: Image.memory(photos[i].bytes, fit: BoxFit.contain, gaplessPlayback: true)),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 12,
                      right: 8,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                            child: Text("${index + 1} / ${photos.length}",
                                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    Positioned(left: 4, top: 0, bottom: 0, child: Center(child: arrow(Icons.chevron_left_rounded, true))),
                    Positioned(right: 4, top: 0, bottom: 0, child: Center(child: arrow(Icons.chevron_right_rounded, false))),
                    if (p.uploadedByName.isNotEmpty)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 16,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                            child: Text("Photo by ${p.uploadedByName}", style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    ).then((_) => controller.dispose());
  }

  Widget _hero(BuildContext context, int? count) {
    final b = booking;
    final name = b.customerName.trim().isEmpty ? 'Customer' : b.customerName.trim();
    final white70 = Colors.white.withValues(alpha: 0.78);
    Widget meta(IconData icon, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: white70),
            const SizedBox(width: 5),
            Text(text, style: TextStyle(fontSize: 12.5, color: white70)),
          ],
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(colors: [AppColors.accent, _accentDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: AppShadows.accentGlowSmall,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text("EVENT ALBUM",
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: AppColors.highlight.withValues(alpha: 0.95))),
              const Spacer(),
              if (_isToday(b.date))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                  child: const Text("TODAY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Colors.white)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white, height: 1.15)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
            child: Text(b.packageName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              meta(Icons.calendar_today_rounded, DateFormat('EEE, MMM d, yyyy').format(b.date)),
              meta(Icons.schedule_rounded, b.time),
              meta(Icons.tag_rounded, b.bookingRef),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(count == null ? "—" : "$count",
                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(count == 1 ? "photo" : "photos", style: TextStyle(fontSize: 13, color: white70)),
              ),
              const Spacer(),
              if (_canUpload)
                FilledButton.icon(
                  onPressed: _uploading ? null : _addPhotos,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.accent,
                    disabledBackgroundColor: Colors.white.withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                  label: Text(_uploading ? "Uploading…" : "Add photos", style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
            ],
          ),
          if (_uploading) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _total == 0 ? null : _done / _total,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
            const SizedBox(height: 6),
            Text("$_done of $_total uploaded", style: TextStyle(fontSize: 11.5, color: white70)),
          ],
        ],
      ),
    );
  }

  Widget _emptyPhotos(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: const Icon(Icons.add_photo_alternate_outlined, size: 42, color: AppColors.accent),
          ),
          const SizedBox(height: 16),
          Text("No photos yet",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
          const SizedBox(height: 6),
          Text(
            _canUpload
                ? "Tap \"Add photos\" above to upload today's shots.\nThe customer will see them right away."
                : "Photos can only be added on the day of the event.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, height: 1.5, color: AppPalette.textMuted(context)),
          ),
        ],
      ),
    );
  }

  Widget _photoTile(EventPhoto p, List<EventPhoto> all) {
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: AppShadows.soft),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: () => _openViewer(all, all.indexOf(p)),
              child: Image.memory(p.bytes, fit: BoxFit.cover, cacheWidth: 500, gaplessPlayback: true),
            ),
            // soft fade so the labels stay readable on any photo
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 56,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xB3000000)],
                    ),
                  ),
                ),
              ),
            ),
            if (p.uploadedByName.isNotEmpty)
              Positioned(
                left: 10,
                right: 10,
                bottom: 8,
                child: Row(
                  children: [
                    const Icon(Icons.photo_camera_rounded, size: 11, color: Colors.white70),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(p.uploadedByName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.45),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _confirmDelete(p),
                  child: const Padding(
                    padding: EdgeInsets.all(7),
                    child: Icon(Icons.delete_outline_rounded, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.surface(context),
      appBar: AppBar(
        backgroundColor: AppPalette.surface(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: AppPalette.textPrimary(context)),
        title: Text("Event Photos",
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
      ),
      body: Column(
        children: [
          const AdminOfflineStrip(),
          Expanded(
            child: StreamBuilder<List<EventPhoto>>(
              stream: EventPhotoRepository.watch(booking.id),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text("Couldn't load photos. Check the 'eventPhotos' Firestore rules.",
                        style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context))),
                  );
                }
                final photos = snap.data;
                if (photos != null) _photoPage = PageWindow.clamp(_photoPage, photos.length);
                final pagePhotos = photos == null ? const <EventPhoto>[] : PageWindow.slice(photos, _photoPage);
                return _centered(
                  ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      _hero(context, photos?.length),
                      const SizedBox(height: 18),
                      if (photos == null)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
                        )
                      else if (photos.isEmpty)
                        _emptyPhotos(context)
                      else ...[
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: pagePhotos.length,
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 220,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                          ),
                          itemBuilder: (context, i) => _photoTile(pagePhotos[i], photos),
                        ),
                        const SizedBox(height: 12),
                        PaginationBar(
                          page: _photoPage,
                          pageCount: PageWindow.pageCount(photos.length),
                          onPageChanged: (p) => setState(() => _photoPage = p),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
