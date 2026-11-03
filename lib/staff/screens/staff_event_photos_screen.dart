import '../../shared/top_toast.dart';
import '../../shared/upload_limit.dart';
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../models/booking_record.dart';
import '../services/auth_service.dart';
import '../services/booking_repository.dart';
import '../services/event_photo_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/staff_offline_strip.dart';

/// Staff upload the photos they take during an event. Only today's
/// confirmed/completed bookings are listed, and a photo is attached to one
/// booking — so only the customer who booked that day sees it (in their
/// My Bookings → Event Photos).
class StaffEventPhotosScreen extends StatefulWidget {
  const StaffEventPhotosScreen({super.key});

  @override
  State<StaffEventPhotosScreen> createState() => _StaffEventPhotosScreenState();
}

class _StaffEventPhotosScreenState extends State<StaffEventPhotosScreen> {
  final _picker = ImagePicker();
  String? _selectedId;
  int _photoPage = 0;
  final List<_QueuedPhoto> _queue = [];
  bool get _uploading => _queue.any((q) => q.state == _PhotoState.waiting || q.state == _PhotoState.uploading);

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  Future<void> _addPhotos(BookingRecord booking) async {
    if (_uploading) return;
    List<XFile> picked;
    try {
      // Each photo is checked against the 100 MB limit when it uploads, then
      // resized/compressed so it fits the per-photo storage cap and uploads
      // quickly on event Wi-Fi/data.
      picked = await _picker.pickMultiImage();
    } catch (e) {
      if (!mounted) return;
      TopToast.show(context, "Couldn't open your photos: $e", kind: TopToastKind.error);
      return;
    }
    if (picked.isEmpty || !mounted) return;

    setState(() {
      _queue.removeWhere((q) => q.state == _PhotoState.saved); // keep the list short
      _queue.addAll(picked.map((f) => _QueuedPhoto(file: f, booking: booking)));
    });
    await _processQueue();
  }

  /// Uploads waiting photos one at a time. If the server doesn't answer within
  /// 20 seconds (usually no signal), the photo is marked "queued" instead of
  /// failed: Firestore keeps the write on the phone and sends it once the
  /// connection is back, and the status updates by itself when it does.
  Future<void> _processQueue() async {
    final staffId = AuthService.instance.currentUid;
    final staffName = await AuthService.instance.currentStaffDisplayName();
    for (final item in _queue.where((q) => q.state == _PhotoState.waiting).toList()) {
      if (!mounted) return;
      _set(item, _PhotoState.uploading);
      try {
        final prepared = await UploadLimit.prepare(item.file, maxDimension: 1280, targetBytes: 600 * 1024, startQuality: 65);
        final write = EventPhotoRepository.add(
          bookingId: item.booking.id,
          userId: item.booking.userId,
          bytes: prepared.bytes,
          mime: prepared.mimeType,
          staffId: staffId,
          staffName: staffName,
        );
        // Whatever happens later (saved or failed) updates this row.
        write.then((_) => _set(item, _PhotoState.saved)).catchError((e) {
          _set(item, _PhotoState.failed, error: _friendly(e));
        });
        await write.timeout(const Duration(seconds: 20));
      } on TimeoutException {
        _set(item, _PhotoState.queued);
      } catch (e) {
        _set(item, _PhotoState.failed, error: _friendly(e));
      }
    }
    if (!mounted) return;
    _summarize();
  }

  Future<void> _retry(_QueuedPhoto item) async {
    if (_uploading) return;
    _set(item, _PhotoState.waiting);
    await _processQueue();
  }

  void _set(_QueuedPhoto item, _PhotoState state, {String? error}) {
    if (!mounted) return;
    setState(() {
      item.state = state;
      item.error = error;
    });
  }

  String _friendly(Object e) => e is UploadTooLargeException ? 'Over 100 MB (not accepted)' : (e.toString().contains('too large') ? 'Too large to upload' : 'Upload failed');

  void _summarize() {
    final saved = _queue.where((q) => q.state == _PhotoState.saved).length;
    final queued = _queue.where((q) => q.state == _PhotoState.queued).length;
    final failed = _queue.where((q) => q.state == _PhotoState.failed).length;
    final msg = failed == 0 && queued == 0
        ? "$saved photo${saved == 1 ? '' : 's'} uploaded."
        : "$saved uploaded"
            "${queued > 0 ? ', $queued waiting for connection' : ''}"
            "${failed > 0 ? ', $failed failed (tap Retry)' : ''}.";
    TopToast.show(context, msg);
  }

  String _progressLabel() {
    final finished = _queue.where((q) => q.state != _PhotoState.waiting && q.state != _PhotoState.uploading).length;
    return "Uploading $finished of ${_queue.length}…";
  }

  String _summaryLine() {
    int count(_PhotoState st) => _queue.where((q) => q.state == st).length;
    final parts = <String>[
      if (count(_PhotoState.saved) > 0) "${count(_PhotoState.saved)} uploaded",
      if (count(_PhotoState.queued) > 0) "${count(_PhotoState.queued)} waiting for connection",
      if (count(_PhotoState.failed) > 0) "${count(_PhotoState.failed)} failed",
      if (count(_PhotoState.uploading) + count(_PhotoState.waiting) > 0)
        "${count(_PhotoState.uploading) + count(_PhotoState.waiting)} left",
    ];
    return parts.join(' · ');
  }

  Widget _queuePanel(BuildContext context) {
    final muted = AppPalette.textMuted(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.divider(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_summaryLine(),
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
          const SizedBox(height: 6),
          for (final q in _queue)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  _stateIcon(q),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(q.file.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: muted)),
                  ),
                  Text(_stateLabel(q), style: TextStyle(fontSize: 11.5, color: _stateColor(q))),
                  if (q.state == _PhotoState.failed)
                    TextButton(
                      onPressed: _uploading ? null : () => _retry(q),
                      child: const Text('Retry'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _stateIcon(_QueuedPhoto q) {
    switch (q.state) {
      case _PhotoState.waiting:
        return const Icon(Icons.schedule_rounded, size: 16, color: Colors.grey);
      case _PhotoState.uploading:
        return const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent));
      case _PhotoState.saved:
        return const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF2E7D32));
      case _PhotoState.queued:
        return const Icon(Icons.cloud_upload_outlined, size: 16, color: Color(0xFFE08A00));
      case _PhotoState.failed:
        return const Icon(Icons.error_outline_rounded, size: 16, color: Colors.redAccent);
    }
  }

  String _stateLabel(_QueuedPhoto q) {
    switch (q.state) {
      case _PhotoState.waiting:
        return 'Waiting';
      case _PhotoState.uploading:
        return 'Uploading';
      case _PhotoState.saved:
        return 'Uploaded';
      case _PhotoState.queued:
        return 'Waiting for connection';
      case _PhotoState.failed:
        return q.error ?? 'Failed';
    }
  }

  Color _stateColor(_QueuedPhoto q) {
    switch (q.state) {
      case _PhotoState.saved:
        return const Color(0xFF2E7D32);
      case _PhotoState.queued:
        return const Color(0xFFE08A00);
      case _PhotoState.failed:
        return Colors.redAccent;
      default:
        return AppPalette.textMuted(context);
    }
  }

  Future<void> _confirmDelete(EventPhoto photo) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete this photo?"),
        content: const Text("The customer won't be able to see it anymore."),
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
    if (yes != true) return;
    try {
      await EventPhotoRepository.delete(photo);
    } catch (e) {
      if (!mounted) return;
      TopToast.show(context, "Couldn't delete: $e", kind: TopToastKind.error);
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
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BookingRecord>>(
      stream: BookingRepository.watchAllBookings(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _message(context, "Couldn't load bookings.");
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accent));
        }
        final today = snap.data!
            .where((b) => _isToday(b.date) && (b.status == 'confirmed' || b.status == 'completed'))
            .toList();

        if (today.isEmpty) {
          return _message(
            context,
            "No confirmed bookings today.\nEvent photos can be uploaded for bookings dated today.",
          );
        }

        final selected = today.firstWhere((b) => b.id == _selectedId, orElse: () => today.first);

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            const StaffOfflineStrip(),
            Text("Event photos",
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
            const SizedBox(height: 4),
            Text(
              "Pick today's booking, then add the photos you took. Only that customer can see them.",
              style: TextStyle(fontSize: 12.5, height: 1.4, color: AppPalette.textMuted(context)),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in today)
                  ChoiceChip(
                    label: Text("${b.customerName.isEmpty ? 'Customer' : b.customerName} · ${b.time}"),
                    selected: b.id == selected.id,
                    selectedColor: AppColors.accent.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: b.id == selected.id ? AppColors.accent : AppPalette.textPrimary(context),
                    ),
                    onSelected: _uploading ? null : (_) => setState(() {
                      _selectedId = b.id;
                      _photoPage = 0;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppPalette.cardBg(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppPalette.divider(context)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_outline, size: 18, color: AppColors.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(selected.customerName.isEmpty ? 'Customer' : selected.customerName,
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
                        Text("${selected.packageName} · ${DateFormat('MMM d').format(selected.date)} · ${selected.time} · #${selected.bookingRef}",
                            style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _uploading ? null : () => _addPhotos(selected),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: _uploading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add_a_photo_outlined, size: 18),
                label: Text(
                  _uploading ? _progressLabel() : "Add photos",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ),
            ),
            if (_queue.isNotEmpty) ...[
              _queuePanel(context),
              const SizedBox(height: 10),
            ],
            if (kIsWeb)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text("Tip: you can select many photos at once.",
                    style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
              ),
            const SizedBox(height: 16),
            StreamBuilder<List<EventPhoto>>(
              stream: EventPhotoRepository.watch(selected.id),
              builder: (context, ps) {
                if (ps.hasError) {
                  return Text("Couldn't load photos. Check the 'eventPhotos' Firestore rules.",
                      style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context)));
                }
                if (!ps.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
                  );
                }
                final photos = ps.data!;
                if (photos.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text("No photos uploaded yet.",
                          style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context))),
                    ),
                  );
                }
                _photoPage = PageWindow.clamp(_photoPage, photos.length);
                final pagePhotos = PageWindow.slice(photos, _photoPage);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("${photos.length} photo${photos.length == 1 ? '' : 's'}",
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppPalette.textSecondary(context))),
                    const SizedBox(height: 8),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: pagePhotos.length,
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 160,
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
          ],
        );
      },
    );
  }

  Widget _message(BuildContext context, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_library_outlined, size: 40, color: AppPalette.textMuted(context)),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.45, color: AppPalette.textMuted(context))),
            ],
          ),
        ),
      );
}

enum _PhotoState { waiting, uploading, saved, queued, failed }

/// One photo in the upload queue on this screen.
class _QueuedPhoto {
  final XFile file;
  final BookingRecord booking;
  _PhotoState state = _PhotoState.waiting;
  String? error;

  _QueuedPhoto({required this.file, required this.booking});
}
