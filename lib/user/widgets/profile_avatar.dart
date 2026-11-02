import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// Round avatar for the customer: their profile picture when they have one,
/// otherwise [fallback] (initials or an icon). Listens to [AuthService.photo],
/// so every avatar on screen changes together as soon as the picture is
/// added, replaced or removed.
class ProfileAvatar extends StatelessWidget {
  final double size;
  final Color color;
  final Widget fallback;
  final BoxBorder? border;
  final List<BoxShadow>? shadow;

  const ProfileAvatar({
    super.key,
    required this.size,
    required this.color,
    required this.fallback,
    this.border,
    this.shadow,
  });

  // Decoding base64 on every rebuild would be wasteful, so keep the last one.
  static String? _lastUri;
  static Uint8List? _lastBytes;

  static Uint8List? _decode(String? uri) {
    if (uri == null) return null;
    if (uri != _lastUri) {
      _lastUri = uri;
      _lastBytes = _tryDecode(uri);
    }
    return _lastBytes;
  }

  static Uint8List? _tryDecode(String uri) {
    try {
      return base64Decode(uri.split(',').last);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: AuthService.photo,
      builder: (context, uri, _) {
        final bytes = _decode(uri);
        return Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color, border: border, boxShadow: shadow),
          child: bytes != null
              ? Image.memory(bytes, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true)
              : fallback,
        );
      },
    );
  }
}
