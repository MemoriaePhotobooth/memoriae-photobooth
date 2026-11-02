import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// What we managed to read off a GCash receipt screenshot.
///
/// Every field is nullable: OCR is a best-effort helper, never a gate. The
/// customer can always submit; staff still verify the receipt by eye.
class ReceiptOcrResult {
  /// Peso amount ("Total Amount Sent" / "Amount"), e.g. 500.0.
  final double? amount;

  /// GCash reference number, digits only (13 digits normally).
  final String? referenceNo;

  /// Recipient mobile number, normalised to 09XXXXXXXXX.
  final String? recipientNumber;

  /// Whether the text looks like a GCash receipt at all.
  final bool looksLikeGcash;

  /// Whether the text looks like proof of a payment from *any* wallet or
  /// bank (GCash, Maya, GoTyme, InstaPay, bank transfer, …).
  final bool looksLikePayment;

  /// Full recognised text, kept for debugging / future parsing.
  final String rawText;

  const ReceiptOcrResult({
    this.amount,
    this.referenceNo,
    this.recipientNumber,
    required this.looksLikeGcash,
    this.looksLikePayment = false,
    required this.rawText,
  });

  bool get foundAnything => amount != null || referenceNo != null || recipientNumber != null;

  /// "1234 567 890123" style, easier to read than 13 bare digits.
  String? get referenceDisplay {
    final r = referenceNo;
    if (r == null || r.length != 13) return r;
    return '${r.substring(0, 4)} ${r.substring(4, 7)} ${r.substring(7)}';
  }
}

/// Outcome of [ReceiptOcr.verify]: the customer may only confirm the booking
/// when there are no [problems].
class ReceiptVerdict {
  final List<String> problems;
  const ReceiptVerdict(this.problems);

  bool get accepted => problems.isEmpty;
}

/// On-device OCR for GCash receipts, using Google ML Kit (Latin script).
///
/// Runs fully offline on the phone — the receipt image never leaves the
/// device for scanning. ML Kit only supports Android and iOS, so on Flutter
/// Web [scan] simply returns `null` and the upload flow carries on as before.
class ReceiptOcr {
  const ReceiptOcr._();

  static bool get isSupported => !kIsWeb;

  /// Scans the image at [imagePath] (the path `image_picker` hands back on
  /// mobile). Returns `null` if OCR isn't available or fails.
  static Future<ReceiptOcrResult?> scan(String imagePath) async {
    if (!isSupported) return null;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFilePath(imagePath);
      final recognized = await recognizer.processImage(input);
      return parse(recognized.text);
    } catch (_) {
      return null; // never let OCR trouble block a booking
    } finally {
      await recognizer.close();
    }
  }

  /// Pulls the useful fields out of raw OCR text. Public + pure so it can be
  /// unit-tested without a device.
  static ReceiptOcrResult parse(String text) {
    final flat = text.replaceAll('\r', '');
    final lower = flat.toLowerCase();

    final looksLikeGcash = lower.contains('gcash') ||
        (lower.contains('ref no') && lower.contains('amount')) ||
        lower.contains('express send');

    final amount = _findAmount(flat);
    final reference = _findReference(flat);

    // Other wallets / banks are fine too — what matters is that it is proof
    // of a transfer, not which app it came from.
    const paymentWords = [
      'gcash', 'maya', 'paymaya', 'gotyme', 'seabank', 'shopeepay', 'grabpay',
      'instapay', 'pesonet', 'express send', 'bank transfer', 'fund transfer',
      'transfer successful', 'transaction successful', 'payment successful',
      'bdo', 'bpi', 'unionbank', 'metrobank', 'landbank', 'security bank',
      'rcbc', 'chinabank', 'pnb', 'eastwest',
    ];
    final looksLikePayment = looksLikeGcash ||
        paymentWords.any(lower.contains) ||
        (reference != null && amount != null);

    return ReceiptOcrResult(
      amount: amount,
      referenceNo: reference,
      recipientNumber: _findPhone(flat),
      looksLikeGcash: looksLikeGcash,
      looksLikePayment: looksLikePayment,
      rawText: text,
    );
  }

  /// Decides whether a scanned receipt proves the money reached the studio's
  /// account. Pure (no Flutter / ML Kit) so it can be unit-tested.
  ///
  /// A receipt passes only when ALL of these hold:
  ///  1. it looks like a payment receipt (any wallet or bank),
  ///  2. it shows the studio's account (number, even partly masked, or name),
  ///  3. the amount sent is at least [amountDue] (when known).
  /// Sending more than due is allowed; sending less is not.
  static ReceiptVerdict verify(
    ReceiptOcrResult ocr, {
    required num? amountDue,
    required String accountNumber,
    required String accountName,
  }) {
    final problems = <String>[];

    if (!ocr.looksLikePayment) {
      problems.add("This doesn't look like a payment receipt. Upload the screenshot you got after sending the payment (GCash, Maya, or your bank app).");
      return ReceiptVerdict(problems);
    }

    if (!_sentToAccount(ocr.rawText, accountNumber, accountName)) {
      problems.add("We can't see our account on this receipt. Make sure you sent it to $accountName ($accountNumber).");
    }

    final amount = ocr.amount;
    if (amount == null) {
      problems.add("We couldn't read the amount on this receipt. Upload a clearer, full screenshot.");
    } else if (amountDue != null && amount < amountDue - 0.5) {
      problems.add("The receipt shows ₱${amount.toStringAsFixed(0)} but the amount due is ₱${amountDue.toStringAsFixed(0)}. Send the remaining balance, then upload the receipt.");
    }

    return ReceiptVerdict(problems);
  }

  /// True when the receipt text shows the studio's number (also when the app
  /// masks the middle digits, e.g. "0975 *** 9253") or at least two parts of
  /// the account name (also when masked, e.g. "MA** LY*").
  static bool _sentToAccount(String rawText, String accountNumber, String accountName) {
    final digitsOnly = accountNumber.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length == 11 && digitsOnly.startsWith('09')) {
      final prefix = digitsOnly.substring(1, 4);
      final suffix = digitsOnly.substring(7);
      final compact = rawText.toLowerCase().replaceAll(RegExp(r'[\s\-.]'), '');
      if (RegExp('$prefix[\\d*•xX]{3}$suffix').hasMatch(compact)) return true;
    }

    final words = accountName
        .toLowerCase()
        .split(RegExp(r'[^a-z]+'))
        .where((w) => w.length >= 2)
        .toList();
    if (words.isEmpty) return false;
    final lower = rawText.toLowerCase();
    // Each name part must match a *different* spot in the text, so a masked
    // "MA***" can't be counted for both "Mary" and "Marbella".
    final used = <int>{};
    var hits = 0;
    for (final w in words) {
      final masked = '${w.substring(0, 2)}[*•xX]+[a-z]?';
      final re = RegExp('(?:\\b$w\\b|\\b$masked)');
      for (final m in re.allMatches(lower)) {
        if (used.add(m.start)) {
          hits++;
          break;
        }
      }
    }
    return hits >= (words.length >= 3 ? 2 : words.length);
  }

  // ₱ is frequently misread as P, #, B or F, so accept those as a prefix.
  static const _peso = r'[₱P#BF]?\s?';
  static const _money = r'(\d{1,3}(?:,\d{3})*(?:\.\d{2})|\d+\.\d{2})';

  static double? _findAmount(String text) {
    // Prefer "Total Amount Sent", then plain "Amount".
    for (final label in const [r'total\s*amount\s*sent', r'amount\s*sent', r'amount']) {
      final re = RegExp('$label[\\s:]{0,12}$_peso$_money', caseSensitive: false);
      final m = re.firstMatch(text);
      if (m != null) return _toDouble(m.group(1)!);
    }
    // Fallback: the largest peso-looking figure on the receipt.
    final all = RegExp('$_peso$_money').allMatches(text);
    double? best;
    for (final m in all) {
      final v = _toDouble(m.group(1)!);
      if (v != null && (best == null || v > best)) best = v;
    }
    return best;
  }

  static double? _toDouble(String s) => double.tryParse(s.replaceAll(',', ''));

  static String? _findReference(String text) {
    final labelled = RegExp(r'ref\.?\s*no\.?[\s:.]{0,4}((?:\d[\s]?){10,16})', caseSensitive: false).firstMatch(text);
    if (labelled != null) {
      final digits = labelled.group(1)!.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 10) return digits.length > 13 ? digits.substring(0, 13) : digits;
    }
    // GCash reference numbers are printed as 4-3-6 digit groups.
    final grouped = RegExp(r'\b(\d{4})\s(\d{3})\s(\d{6})\b').firstMatch(text);
    if (grouped != null) return '${grouped.group(1)}${grouped.group(2)}${grouped.group(3)}';
    return null;
  }

  static String? _findPhone(String text) {
    final m = RegExp(r'(?:\+?63|0)\s?(9\d{2})[\s-]?(\d{3})[\s-]?(\d{4})').firstMatch(text);
    if (m == null) return null;
    return '0${m.group(1)}${m.group(2)}${m.group(3)}';
  }

  /// Normalises any PH mobile number to 09XXXXXXXXX for comparison.
  static String normalizeNumber(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('63') && d.length == 12) d = '0${d.substring(2)}';
    if (d.length == 10 && d.startsWith('9')) d = '0$d';
    return d;
  }
}
