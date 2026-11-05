<<<<<<< HEAD
import 'package:cloud_firestore/cloud_firestore.dart';
=======
>>>>>>> 991372238794561fb409ddfdfc599edcc62a5186
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import '../services/event_photo_repository.dart';
import '../services/photo_download.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
<<<<<<< HEAD
import '../widgets/circle_back_button.dart';
import '../widgets/stream_once.dart';
=======
>>>>>>> 991372238794561fb409ddfdfc599edcc62a5186

/// The photos our staff took at the customer's event. Opened from a
/// booking in My Bookings, so a customer only ever sees photos from their
/// own bookings (and Firestore rules enforce that on the server too).
class EventPhotosScreen extends StatelessWidget {
  final String bookingId;
  final String userId;
  final String title;

  const EventPhotosScreen({super.key, required this.bookingId, required this.userId, this.title = 'Event Photos'});

  void _openViewer(BuildContext context, List<EventPhoto> photos, int start) {
    showDialog<void>(
      context: context,
      builder: (_) => _PhotoViewer(photos: photos, initialIndex: start),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Photos are protected by sign-in. Guest checkouts have no account, so
    // there's no way to prove the photos are theirs.
    final signedIn = FirebaseAuth.instance.currentUser != null;

    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppPalette.textPrimary(context)),
        title: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
      ),
      body: !signedIn
          ? _message(context, Icons.lock_outline,
              "Sign in to your account to see your event photos.\nGuest bookings can't view them.")
          : StreamOnce<List<EventPhoto>>(
              create: () => EventPhotoRepository.watchForBooking(bookingId: bookingId, userId: userId),
              identity: Object.hash(bookingId, userId),
              builder: (context, snap) {
                if (snap.hasError) {
                  final denied = snap.error is FirebaseException && (snap.error as FirebaseException).code == 'permission-denied';
                  return _message(
                    context,
                    Icons.error_outline,
                    denied ? "You don't have access to these photos." : "Couldn't load your photos. Please try again.",
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.accent));
                }
                final photos = snap.data!;
                if (photos.isEmpty) {
                  return _message(context, Icons.photo_library_outlined,
                      "No photos yet.\nOur staff will upload them during your event.");
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10, left: 2),
                      child: Text(
                        "${photos.length} photo${photos.length == 1 ? '' : 's'} · only you can see these",
                        style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context)),
                      ),
                    ),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: photos.length,
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 180,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      itemBuilder: (context, i) => GestureDetector(
                        onTap: () => _openViewer(context, photos, i),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(photos[i].bytes, fit: BoxFit.cover, cacheWidth: 400, gaplessPlayback: true),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _message(BuildContext context, IconData icon, String text) => Center(
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

/// Full-screen swipeable viewer with pinch-to-zoom.
class _PhotoViewer extends StatefulWidget {
  final List<EventPhoto> photos;
  final int initialIndex;
  const _PhotoViewer({required this.photos, required this.initialIndex});

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _busy = false;
  String? _status;

  EventPhoto get _current => widget.photos[_index];

  String get _mime {
    final uri = _current.dataUri;
    final semi = uri.indexOf(';');
    return semi > 5 ? uri.substring(5, semi) : 'image/jpeg';
  }

  String get _ext => _mime == 'image/png' ? 'png' : 'jpg';

  void _setStatus(String? msg) {
    if (mounted) setState(() => _status = msg);
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      if (kIsWeb) {
        await downloadPhoto(_current.bytes, _mime, 'memoriae_${_current.id}.$_ext');
        _setStatus('Download started.');
      } else {
        await Gal.putImageBytes(_current.bytes, name: 'memoriae_${_current.id}', album: 'Memoriae');
        _setStatus('Saved to your photos.');
      }
    } on GalException catch (e) {
      _setStatus(e.type == GalExceptionType.accessDenied
          ? 'Allow photo access in Settings to save.'
          : "Couldn't save the photo. Please try again.");
    } catch (_) {
      _setStatus("Couldn't save the photo. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await Share.shareXFiles(
        [XFile.fromData(_current.bytes, mimeType: _mime, name: 'memoriae_${_current.id}.$_ext')],
        text: 'Our photobooth moment',
      );
    } catch (_) {
      _setStatus("Couldn't open sharing. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.photos.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => InteractiveViewer(
              maxScale: 5,
              child: Center(child: Image.memory(widget.photos[i].bytes, fit: BoxFit.contain, cacheWidth: 1600, gaplessPlayback: true)),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
          ),
          Positioned(
            top: 12,
            left: 16,
            child: Text("${_index + 1} / ${widget.photos.length}",
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
          if (_status != null)
            Positioned(
              bottom: 66,
              left: 16,
              right: 16,
              child: Text(_status!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 12.5)),
            ),
          Positioned(
            bottom: 12,
            left: 12,
            right: 12,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _busy ? null : _share,
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    label: const Text('Share', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
