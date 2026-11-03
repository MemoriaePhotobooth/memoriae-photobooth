import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// The biggest file the system accepts from a person: 100 MB.
/// Anything bigger is rejected right away with a clear message.
const int kMaxUploadBytes = 100 * 1024 * 1024;

/// Thrown when the picked file is over [kMaxUploadBytes].
class UploadTooLargeException implements Exception {
  final int bytes;
  const UploadTooLargeException(this.bytes);

  @override
  String toString() => 'That file is too large (${UploadLimit.mb(bytes)}). The limit is 100 MB.';
}

/// A picked photo that passed the 100 MB check and was shrunk (if needed) so
/// it fits in a Firestore document (photos are stored as base64 text there,
/// and one Firestore document can only hold ~1 MiB).
class PreparedImage {
  final Uint8List bytes;
  final String mimeType;
  final String name;
  const PreparedImage({required this.bytes, required this.mimeType, required this.name});
}

class UploadLimit {
  UploadLimit._();

  static String mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  /// Throws [UploadTooLargeException] if [file] is over 100 MB.
  static Future<void> ensureWithinLimit(XFile file) async {
    final size = await file.length();
    if (size > kMaxUploadBytes) throw UploadTooLargeException(size);
  }

  static String mimeFor(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  /// 1) Rejects the file if it is over 100 MB.
  /// 2) Accepts it, and if it is bigger than [targetBytes] (what the database
  ///    can store) it is resized/compressed automatically so the upload works.
  ///
  /// Throws [UploadTooLargeException] (over 100 MB) or a plain [Exception]
  /// with a friendly message if the picture can't be processed.
  static Future<PreparedImage> prepare(
    XFile file, {
    required int maxDimension,
    required int targetBytes,
    int startQuality = 80,
  }) async {
    await ensureWithinLimit(file);
    final original = await file.readAsBytes();
    final mime = mimeFor(file.name);

    if (original.lengthInBytes <= targetBytes) {
      return PreparedImage(bytes: original, mimeType: mime, name: file.name);
    }

    final Uint8List? out = await compute(_compress, <String, Object>{
      'bytes': original,
      'maxDim': maxDimension,
      'target': targetBytes,
      'quality': startQuality,
    });
    if (out == null) {
      throw Exception("Couldn't process that photo. Please pick a different one.");
    }
    final dot = file.name.lastIndexOf('.');
    final base = dot > 0 ? file.name.substring(0, dot) : file.name;
    return PreparedImage(bytes: out, mimeType: 'image/jpeg', name: '$base.jpg');
  }
}

Uint8List? _compress(Map<String, Object> args) {
  try {
    final bytes = args['bytes'] as Uint8List;
    final maxDim = args['maxDim'] as int;
    final target = args['target'] as int;
    final startQuality = args['quality'] as int;

    var decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    decoded = img.bakeOrientation(decoded);

    var dim = maxDim;
    for (var round = 0; round < 7; round++) {
      var work = decoded;
      if (math.max(work.width, work.height) > dim) {
        work = work.width >= work.height ? img.copyResize(work, width: dim) : img.copyResize(work, height: dim);
      }
      for (var quality = startQuality; quality >= 40; quality -= 10) {
        final out = Uint8List.fromList(img.encodeJpg(work, quality: quality));
        if (out.lengthInBytes <= target) return out;
      }
      dim = (dim * 0.75).round();
      if (dim < 200) break;
    }
  } catch (_) {}
  return null;
}
