import 'dart:typed_data';

import 'photo_download_stub.dart' if (dart.library.js_interop) 'photo_download_web.dart' as impl;

/// Saves a photo to the browser's downloads. Only used on web; mobile saves
/// to the photo library through `gal` instead.
Future<void> downloadPhoto(Uint8List bytes, String mime, String filename) =>
    impl.downloadPhoto(bytes, mime, filename);
