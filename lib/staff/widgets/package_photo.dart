import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A package's photo, exactly as Admin saved it on the Pricing screen:
/// either a `data:` URI (base64, the usual case) or an http(s) URL.
///
/// The base64 is decoded once (and again only when the URL actually
/// changes), not on every rebuild — the walk-in form rebuilds on every
/// keystroke and the pricing stream re-emits often, and re-decoding a
/// photo each time would make the form stutter.
///
/// When the package has no photo (or it fails to load) a soft maroon
/// placeholder with a camera icon is shown instead, so a card never ends
/// up with an empty hole.
class PackagePhoto extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;

  const PackagePhoto({super.key, required this.imageUrl, this.fit = BoxFit.cover});

  /// True when [imageUrl] is something we can try to draw.
  static bool hasPhoto(String imageUrl) => imageUrl.startsWith('data:') || imageUrl.startsWith('http');

  @override
  State<PackagePhoto> createState() => _PackagePhotoState();
}

class _PackagePhotoState extends State<PackagePhoto> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(covariant PackagePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) _decode();
  }

  void _decode() {
    final url = widget.imageUrl;
    if (url.startsWith('data:') && url.contains(',')) {
      try {
        _bytes = base64Decode(url.substring(url.indexOf(',') + 1));
      } catch (_) {
        _bytes = null;
      }
    } else {
      _bytes = null;
    }
  }

  Widget _placeholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accentTint(0.16), AppColors.accentTint(0.06)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final side = c.biggest.shortestSide;
          final iconSize = (side.isFinite ? side * 0.38 : 36.0).clamp(18.0, 56.0).toDouble();
          return Center(child: Icon(Icons.photo_camera_outlined, size: iconSize, color: AppColors.accent.withValues(alpha: 0.55)));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.imageUrl;
    if (_bytes != null) {
      return Image.memory(
        _bytes!,
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    if (url.startsWith('http')) {
      return Image.network(
        url,
        fit: widget.fit,
        errorBuilder: (_, __, ___) => _placeholder(),
        loadingBuilder: (context, child, progress) => progress == null ? child : _placeholder(),
      );
    }
    return _placeholder();
  }
}
