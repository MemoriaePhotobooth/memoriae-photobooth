import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/receipt_ocr.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import 'app_toast.dart';

/// Simple data holder mirroring the React `{ name, url }` receipt state.
///
/// Holds raw bytes rather than a `dart:io File` on purpose: `File` doesn't
/// work on Flutter Web (there's no real filesystem in the browser — an
/// `XFile`'s "path" there is just a blob URL), so bytes are the one
/// representation that previews with `Image.memory` and uploads via
/// `putData` identically on every platform.
class ReceiptFile {
  final String name;
  final Uint8List bytes;

  /// What OCR read off the screenshot (null on web, or if scanning failed).
  final ReceiptOcrResult? ocr;
  const ReceiptFile({required this.name, required this.bytes, this.ocr});
}

/// Port of `ReceiptUpload`. Uses `image_picker` in place of the browser
/// `<input type="file">` + `FileReader` combo from the React version.
class ReceiptUpload extends StatefulWidget {
  final ReceiptFile? receipt;
  final ValueChanged<ReceiptFile?> onChanged;

  /// True when the attached screenshot failed the receipt check — the preview
  /// then shows a red "Not accepted" badge instead of the green "Attached".
  final bool rejected;

  const ReceiptUpload({super.key, required this.receipt, required this.onChanged, this.rejected = false});

  @override
  State<ReceiptUpload> createState() => _ReceiptUploadState();
}

class _ReceiptUploadState extends State<ReceiptUpload> {
  bool _scanning = false;

  ReceiptFile? get receipt => widget.receipt;

  Future<void> _pickImage(BuildContext context) async {
    final picker = ImagePicker();
    // maxWidth/maxHeight + imageQuality keep the encoded result comfortably
    // under Firestore's ~1MB document limit — receipts are stored as a
    // base64 string directly in the booking document (see
    // BookingRepository), not Firebase Storage, so size matters here in a
    // way it wouldn't for a Storage upload.
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1280,
      maxHeight: 1280,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (bytes.lengthInBytes > 700 * 1024) {
      if (context.mounted) {
        AppToast.show(context, "That image is too large (${(bytes.lengthInBytes / 1024).round()} KB) — please pick a smaller screenshot.");
      }
      return;
    }

    // OCR the screenshot on-device (no-op on web). Attaching always works;
    // the booking modal uses the result to decide whether it can submit.
    ReceiptOcrResult? ocr;
    if (ReceiptOcr.isSupported) {
      setState(() => _scanning = true);
      ocr = await ReceiptOcr.scan(picked.path);
      if (mounted) setState(() => _scanning = false);
    }
    if (!mounted) return;
    widget.onChanged(ReceiptFile(name: picked.name, bytes: bytes, ocr: ocr));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.upload, size: 16, color: AppColors.accent),
            const SizedBox(width: 8),
            Text("Upload Payment Receipt", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context))),
          ],
        ),
        const SizedBox(height: 12),
        if (receipt == null)
          GestureDetector(
            onTap: _scanning ? null : () => _pickImage(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              decoration: BoxDecoration(
                color: AppPalette.surface(context),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppPalette.divider(context), width: 2, style: BorderStyle.solid),
              ),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppPalette.cardBg(context),
                      shape: BoxShape.circle,
                      boxShadow: AppShadows.soft,
                    ),
                    child: _scanning
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accent),
                          )
                        : const Icon(Icons.upload, color: AppColors.accent, size: 24),
                  ),
                  const SizedBox(height: 12),
                  Text(_scanning ? "Reading your receipt…" : "Tap to upload screenshot",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context))),
                  const SizedBox(height: 4),
                  Text(_scanning ? "Checking the amount and reference no." : "GCash or bank transfer receipt only · PNG, JPG",
                      style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
                ],
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppPalette.cardBg(context),
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppShadows.card,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  color: AppPalette.surface(context),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(10)),
                        alignment: Alignment.center,
                        child: const Icon(Icons.receipt_long_rounded, size: 17, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Payment Receipt", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                            Text(receipt!.name, style: TextStyle(fontSize: 10, color: AppPalette.textMuted(context)), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => widget.onChanged(null),
                        icon: Icon(Icons.close, size: 18, color: AppPalette.textSecondary(context)),
                        splashRadius: 18,
                      ),
                    ],
                  ),
                ),
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 208),
                      color: AppPalette.divider(context),
                      alignment: Alignment.center,
                      child: AspectRatio(
                        aspectRatio: 3 / 4,
                        child: Image.memory(receipt!.bytes, fit: BoxFit.contain, cacheWidth: 1000, gaplessPlayback: true),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: widget.rejected ? const Color(0xFFDC2626) : AppColors.success,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(widget.rejected ? Icons.close : Icons.check, size: 12, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(widget.rejected ? "Not accepted" : "Attached", style: const TextStyle(fontSize: 10, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}