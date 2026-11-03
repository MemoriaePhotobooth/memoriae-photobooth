import 'app_modal.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'upload_limit.dart';

/// Text stored on a message that is only a photo (no caption). Firestore
/// rules require every message to have non-empty text, and this doubles as
/// the inbox preview ("📷 Photo").
const String kPhotoMessageText = '📷 Photo';

/// A photo the person picked, already compressed and size-checked.
class ChatPickedImage {
  final Uint8List bytes;
  final String mimeType;
  const ChatPickedImage({required this.bytes, required this.mimeType});

  /// What actually gets stored in Firestore (`messageImages/{id}.data`).
  String get dataUri => 'data:$mimeType;base64,${base64Encode(bytes)}';
}

/// Everything the Admin, Staff and User chat screens share for photos and
/// for clearing a conversation.
///
/// WHY base64 in Firestore (not Firebase Storage): that's how this project
/// already stores receipts (see BookingRepository) — the project is on the
/// free Spark plan. Photos live in their own collection, `messageImages`,
/// NOT inside the `messages` documents, so the inboxes (which listen to
/// every message) stay small and fast. A bubble only fetches its photo
/// when it's actually shown, and caches it.
class ChatMedia {
  ChatMedia._();

  /// Firestore documents max out at 1 MiB. base64 inflates by ~33%, so a
  /// 600 KB photo is ~800 KB of text — under the limit with headroom.
  static const int maxBytes = 600 * 1024;

  static CollectionReference<Map<String, dynamic>> get _images => FirebaseFirestore.instance.collection('messageImages');

  static bool get _hasCamera => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// Opens the photo library (and the camera, on phones). Returns null if
  /// the person cancels or the photo is too big (a snackbar explains).
  ///
  /// [centered] opens the "photo library / camera" chooser as a popup in the
  /// middle of the screen (Admin and Staff apps) instead of a sheet that
  /// slides up from the bottom (the customer app keeps the sheet).
  static Future<ChatPickedImage?> pickImage(BuildContext context, {bool centered = false}) async {
    ImageSource source = ImageSource.gallery;
    if (_hasCamera) {
      // Always a popup in the middle of the screen (never a bottom sheet).
      final chosen = await showAppModal<ImageSource>(
        context,
        maxWidth: 440,
        builder: (ctx) => const _PhotoSourceSheet(centered: true),
      );
      if (chosen == null) return null;
      source = chosen;
    }

    try {
      final picked = await ImagePicker().pickImage(source: source);
      if (picked == null) return null;
      // Up to 100 MB is accepted; the photo is then shrunk automatically so
      // it fits in the database. Over 100 MB is rejected.
      final prepared = await UploadLimit.prepare(picked, maxDimension: 1280, targetBytes: maxBytes, startQuality: 70);
      return ChatPickedImage(bytes: prepared.bytes, mimeType: prepared.mimeType);
    } on UploadTooLargeException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
      return null;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open the photo picker. Please try again.")));
      }
      return null;
    }
  }

  static String _mimeFor(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  /// Stores a photo under [id] (use the message's own doc id so they pair up).
  static Future<void> saveImage({required String id, required String userId, required bool fromStaff, required String dataUri}) {
    return _images.doc(id).set({
      'userId': userId,
      'fromStaff': fromStaff,
      'data': dataUri,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static final Map<String, Uint8List> _cache = {};

  /// Fetches (and caches) a photo's bytes; null if it no longer exists.
  static Future<Uint8List?> loadImage(String id) async {
    final cached = _cache[id];
    if (cached != null) return cached;
    final snap = await _images.doc(id).get();
    final data = snap.data()?['data'];
    if (data is! String || !data.contains(',')) return null;
    final bytes = base64Decode(data.split(',').last);
    _cache[id] = bytes;
    return bytes;
  }

  /// Removes one chat photo (and forgets the cached copy).
  static Future<void> deleteImage(String id) async {
    await _images.doc(id).delete();
    _cache.remove(id);
  }

  /// Permanently deletes a whole conversation: every message, every photo
  /// and the closed/open marker. Firestore allows 500 writes per batch, so
  /// this works in chunks of 400. Only Staff/Admin may do this (see
  /// firestore.rules); the customer's chat becomes empty too.
  static Future<void> deleteThread(String userId) async {
    final db = FirebaseFirestore.instance;
    final msgs = await db.collection('messages').where('userId', isEqualTo: userId).get();
    final imgs = await _images.where('userId', isEqualTo: userId).get();
    final refs = <DocumentReference>[
      ...msgs.docs.map((d) => d.reference),
      ...imgs.docs.map((d) => d.reference),
      db.collection('threadStatus').doc(userId),
    ];
    for (var i = 0; i < refs.length; i += 400) {
      final end = (i + 400 < refs.length) ? i + 400 : refs.length;
      final batch = db.batch();
      for (final r in refs.sublist(i, end)) {
        batch.delete(r);
      }
      await batch.commit();
    }
    for (final d in imgs.docs) {
      _cache.remove(d.id);
    }
  }
}

/// A chat photo inside a bubble. Loads on demand, shows a placeholder
/// meanwhile, and opens a zoomable full-screen view when tapped.
class ChatImage extends StatefulWidget {
  final String imageId;
  final double maxWidth;
  final double radius;
  const ChatImage({super.key, required this.imageId, this.maxWidth = 240, this.radius = 14});

  @override
  State<ChatImage> createState() => _ChatImageState();
}

class _ChatImageState extends State<ChatImage> {
  late Future<Uint8List?> _future = ChatMedia.loadImage(widget.imageId);

  @override
  void didUpdateWidget(covariant ChatImage old) {
    super.didUpdateWidget(old);
    if (old.imageId != widget.imageId) _future = ChatMedia.loadImage(widget.imageId);
  }

  void _openFullScreen(Uint8List bytes) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _box(Widget child) => Container(
        width: widget.maxWidth < 200 ? widget.maxWidth : 200,
        height: 150,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: const Color(0x14000000), borderRadius: BorderRadius.circular(widget.radius)),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _box(const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final bytes = snap.data;
        if (snap.hasError || bytes == null) {
          return _box(const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, size: 26, color: Colors.black38),
              SizedBox(height: 6),
              Text('Photo unavailable', style: TextStyle(fontSize: 11, color: Colors.black45)),
            ],
          ));
        }
        return GestureDetector(
          onTap: () => _openFullScreen(bytes),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.radius),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: widget.maxWidth, maxHeight: 320),
              child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
            ),
          ),
        );
      },
    );
  }
}

/// The small "photo attached" thumbnail shown above the composer before sending.
class ChatAttachmentPreview extends StatelessWidget {
  final ChatPickedImage image;
  final VoidCallback? onRemove;
  const ChatAttachmentPreview({super.key, required this.image, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(image.bytes, width: 76, height: 76, fit: BoxFit.cover),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

/// The "Photo library / Take a photo" picker: a rounded sheet with a header
/// and two big tappable cards. Colours come from the active theme so it
/// matches the User, Staff and Admin apps.
class _PhotoSourceSheet extends StatelessWidget {
  /// True when shown inside the centered popup (no drag handle, no extra
  /// rounding/shadow — the popup frame provides those).
  final bool centered;
  const _PhotoSourceSheet({this.centered = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: centered ? Colors.transparent : cs.surface,
        borderRadius: centered ? null : const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: centered ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 30, offset: const Offset(0, -6))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!centered) ...[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 18),
              ] else
                const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: Icon(Icons.add_photo_alternate_rounded, color: cs.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Send a photo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface)),
                        const SizedBox(height: 2),
                        Text('Choose where to get it from', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _SourceCard(
                      icon: Icons.photo_library_rounded,
                      label: 'Photo library',
                      hint: 'Pick from gallery',
                      onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SourceCard(
                      icon: Icons.photo_camera_rounded,
                      label: 'Take a photo',
                      hint: 'Use your camera',
                      onTap: () => Navigator.of(context).pop(ImageSource.camera),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: cs.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;

  const _SourceCard({required this.icon, required this.label, required this.hint, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primary.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 6))],
                ),
                child: Icon(icon, color: cs.onPrimary, size: 26),
              ),
              const SizedBox(height: 14),
              Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
              const SizedBox(height: 2),
              Text(hint, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
