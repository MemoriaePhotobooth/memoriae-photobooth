import 'dart:typed_data';

Future<void> downloadPhoto(Uint8List bytes, String mime, String filename) =>
    throw UnsupportedError('Browser downloads are only available on web.');
