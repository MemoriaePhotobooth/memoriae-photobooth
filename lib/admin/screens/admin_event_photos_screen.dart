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
          return Column(
            children: [
              const AdminOfflineStrip(),
              Expanded(
                child: bookings.isEmpty
                    ? _message(context, Icons.photo_library_outlined,
                        "No event photos yet.\nToday's confirmed bookings will appear here.")
                    : Column(
                        children: [
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                              itemCount: PageWindow.slice(bookings, _page).length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, i) => _bookingTile(context, PageWindow.slice(bookings, _page)[i]),
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

  Widget _bookingTile(BuildContext context, EventPhotoBooking b) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _AdminBookingPhotosPage(booking: b)),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppPalette.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppPalette.divider(context)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.photo_library_outlined, size: 20, color: AppColors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.customerName.isEmpty ? 'Customer' : b.customerName,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
                  const SizedBox(height: 2),
                  Text(
                    "${b.packageName} · ${DateFormat('MMM d, yyyy').format(b.date)} · ${b.time} · #${b.bookingRef}",
                    style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text("${b.count}",
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.accent)),
            ),
            Icon(Icons.chevron_right_rounded, color: AppPalette.textMuted(context)),
          ],
        ),
      ),
    );
  }

  static Widget _message(BuildContext context, IconData icon, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: AppPalette.textMuted(context)),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.45, color: AppPalette.textMuted(context))),
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
    final n = DateTime.now();
    final isToday = booking.date.year == n.year && booking.date.month == n.month && booking.date.day == n.day;
    return isToday && (booking.status == 'confirmed' || booking.status == 'completed');
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

  void _openViewer(EventPhoto photo) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(maxScale: 5, child: Center(child: Image.memory(photo.bytes, fit: BoxFit.contain))),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppPalette.textPrimary(context)),
        title: Text(booking.customerName.isEmpty ? 'Event Photos' : booking.customerName,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
        actions: [
          if (_canUpload)
            TextButton.icon(
              onPressed: _uploading ? null : _addPhotos,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: Text(_uploading ? "$_done of $_total" : "Add photos",
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
        ],
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
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.accent));
                }
                final photos = snap.data!;
                if (photos.isEmpty) {
                  return Center(
                    child: Text(
                      _canUpload ? "No photos yet. Tap Add photos." : "No photos.",
                      style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
                    ),
                  );
                }
                _photoPage = PageWindow.clamp(_photoPage, photos.length);
                final pagePhotos = PageWindow.slice(photos, _photoPage);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10, left: 2),
                      child: Text(
                        "${booking.packageName} · ${DateFormat('MMM d, yyyy').format(booking.date)} · ${photos.length} photo${photos.length == 1 ? '' : 's'}",
                        style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context)),
                      ),
                    ),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: pagePhotos.length,
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 180,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      itemBuilder: (context, i) {
                        final p = pagePhotos[i];
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              GestureDetector(
                                onTap: () => _openViewer(p),
                                child: Image.memory(p.bytes, fit: BoxFit.cover, cacheWidth: 400, gaplessPlayback: true),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: InkWell(
                                  onTap: () => _confirmDelete(p),
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                    child: const Icon(Icons.delete_outline, size: 15, color: Colors.white),
                                  ),
                                ),
                              ),
                              if (p.uploadedByName.isNotEmpty)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    color: Colors.black45,
                                    child: Text("by ${p.uploadedByName}",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white, fontSize: 9.5)),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    PaginationBar(
                      page: _photoPage,
                      pageCount: PageWindow.pageCount(photos.length),
                      onPageChanged: (p) => setState(() => _photoPage = p),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
