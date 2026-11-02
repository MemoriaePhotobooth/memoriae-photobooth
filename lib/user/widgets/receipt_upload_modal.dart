import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/booth_package.dart';
import '../services/booking_repository.dart';
import '../services/business_settings_repository.dart';
import '../services/payment_settings_repository.dart';
import '../services/receipt_ocr.dart';
import '../services/server_clock.dart';
import '../services/studio_payment_account.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import 'countdown_timer.dart';
import 'receipt_upload.dart';
import 'circle_back_button.dart';
import 'app_toast.dart';

/// Modal that opens right after [BookingRepository.reserveSlot] places a
/// hold, so the 15-minute countdown starts the moment the customer needs
/// to act on it — not while they're still picking a date/package.
///
/// The countdown is anchored to [holdExpiresAt] — the exact moment
/// Firestore's `holdExpiresAt` field says the hold lapses — rather than a
/// local counter that just ticks down from 15:00. Every tick (and every
/// time the app comes back from the background) recomputes "seconds left"
/// as `holdExpiresAt.difference(DateTime.now())`, so the number on screen
/// is always correct even if:
///  - the customer backgrounds the app for a while (mobile OSes throttle
///    or pause timers in the background — a plain decrementing counter
///    would freeze and then be wrong by however long it was paused; this
///    one just recomputes against the fixed deadline and catches up), or
///  - a stray missed tick or two happens for any other reason.
///
/// If it reaches zero before a receipt is attached, the hold is
/// auto-rejected via [BookingRepository.expireHold] and [onExpired] fires
/// so the caller can show the "slot expired" messaging and reset checkout.
/// Submitting a receipt in time calls [BookingRepository.attachReceipt]
/// and fires [onSubmitted] instead. Either way the modal closes itself —
/// callers just react to which callback ran.
///
/// Tapping outside still does nothing (`barrierDismissible: false`), but
/// the back button (top-left, and the hardware/gesture back action) lets
/// the customer step away and keep exploring the rest of the app: it just
/// closes this dialog and fires [onMinimized] — it does NOT expire the
/// hold. The booking already exists in Firestore as `awaiting_receipt`
/// from the moment [BookingRepository.reserveSlot] ran, so the countdown
/// keeps running server-side regardless of whether this modal happens to
/// be on screen. The customer can always get back to it from My Bookings,
/// which lists it as "Awaiting Receipt" with its own "Upload Receipt"
/// button that reopens this same modal.
class ReceiptUploadModal extends StatefulWidget {
  final String bookingId;
  final String userId;
  final DateTime holdExpiresAt;
  final int holdDurationSeconds;
  final VoidCallback onExpired;
  final VoidCallback onSubmitted;
  final VoidCallback onMinimized;

  const ReceiptUploadModal({
    super.key,
    required this.bookingId,
    required this.userId,
    required this.holdExpiresAt,
    required this.onExpired,
    required this.onSubmitted,
    this.onMinimized = _noop,
    this.holdDurationSeconds = 15 * 60,
  });

  static void _noop() {}

  /// Shows the modal as a dialog on top of [context]. Tapping the barrier
  /// still does nothing, but the back button lets the customer minimize it
  /// (see the class doc) — [onMinimized] is optional since not every
  /// caller needs to react to that.
  static Future<void> show(
    BuildContext context, {
    required String bookingId,
    required String userId,
    required DateTime holdExpiresAt,
    required VoidCallback onExpired,
    required VoidCallback onSubmitted,
    VoidCallback onMinimized = _noop,
    int holdDurationSeconds = 15 * 60,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReceiptUploadModal(
        bookingId: bookingId,
        userId: userId,
        holdExpiresAt: holdExpiresAt,
        onExpired: onExpired,
        onSubmitted: onSubmitted,
        onMinimized: onMinimized,
        holdDurationSeconds: holdDurationSeconds,
      ),
    );
  }

  @override
  State<ReceiptUploadModal> createState() => _ReceiptUploadModalState();
}

class _ReceiptUploadModalState extends State<ReceiptUploadModal> with WidgetsBindingObserver {
  late int _secondsLeft = _computeSecondsLeft();
  Timer? _timer;
  ReceiptFile? _receipt;
  bool _submitting = false;

  // Payment choice. [_total] / [_settings] load asynchronously after the
  // modal opens; until then (or if loading fails) the modal behaves like
  // before: full payment, no selector shown.
  int? _total;
  PaymentSettings _settings = PaymentSettings.defaults;
  BusinessSettings _business = const BusinessSettings();
  bool _payFull = false;

  // Guards against the periodic timer and a just-tapped submit racing each
  // other right at the 0-second mark — whichever gets here first wins, and
  // the modal only ever closes/calls back once.
  bool _settled = false;

  int _computeSecondsLeft() {
    final diff = widget.holdExpiresAt.difference(ServerClock.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    _loadPaymentOptions();
  }

  Future<void> _loadPaymentOptions() async {
    final results = await Future.wait([
      BookingRepository.fetchTotal(widget.bookingId),
      PaymentSettingsRepository.fetch(),
      BusinessSettingsRepository.fetch(),
    ]);
    if (!mounted) return;
    setState(() {
      _total = results[0] as int?;
      _settings = results[1] as PaymentSettings;
      _business = results[2] as BusinessSettings;
      // Downpayment is the default when it's on offer.
      _payFull = !(_total != null && _settings.canSplit(_total!));
    });
  }

  bool get _canSplit => _total != null && _settings.canSplit(_total!);

  /// What the customer should send right now.
  int? get _amountDueNow {
    final t = _total;
    if (t == null) return null;
    return (_canSplit && !_payFull) ? _settings.downpaymentFor(t) : t;
  }

  /// Re-derives seconds-left from the fixed [widget.holdExpiresAt] deadline
  /// rather than decrementing — called every tick, and also right away
  /// when the app comes back to the foreground, so a paused/throttled
  /// timer never leaves a stale number on screen.
  void _refresh() {
    if (!mounted || _settled) return;
    final left = _computeSecondsLeft();
    setState(() => _secondsLeft = left);
    if (left <= 0) _handleExpired();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _handleExpired() async {
    if (_settled) return;
    _settled = true;
    _timer?.cancel();
    try {
      await BookingRepository.expireHold(widget.bookingId);
    } catch (_) {
      // Best-effort — the staff/admin stale-hold sweep will catch it even
      // if this particular call fails (offline, etc.).
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onExpired();
  }

  /// The attached screenshot is NOT a payment receipt at all (checked by
  /// on-device OCR the moment it is attached). GCash, Maya, GoTyme, bank
  /// transfers, InstaPay and other wallets all count; a random photo or
  /// screenshot doesn't, and can't be submitted.
  bool get _notReceipt {
    final ocr = _receipt?.ocr;
    return ocr != null && !ocr.looksLikePayment;
  }

  /// OCR is available on this device but couldn't read the screenshot at
  /// all, so we can't tell whether it is a payment receipt. (On web OCR isn't
  /// available, so this is never true there and staff check by eye.)
  bool get _unreadable => _receipt != null && ReceiptOcr.isSupported && _receipt!.ocr == null;

  /// Whether the booking can be submitted with the current screenshot.
  bool get _canSubmit => _receipt != null && !_notReceipt && !_unreadable && !_submitting;

  Future<void> _handleSubmitReceipt() async {
    if (!_canSubmit || _settled) return;
    setState(() => _submitting = true);
    try {
      await BookingRepository.attachReceipt(
        bookingId: widget.bookingId,
        userId: widget.userId,
        receiptBytes: _receipt!.bytes,
        receiptFileName: _receipt!.name,
        paymentOption: (_canSplit && !_payFull) ? 'downpayment' : 'full',
        amountPaid: _amountDueNow,
        receiptRefNo: _receipt!.ocr?.referenceNo,
        receiptOcrAmount: _receipt!.ocr?.amount,
      );
      if (_settled) return; // the countdown beat us to it
      _settled = true;
      _timer?.cancel();
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSubmitted();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppToast.show(context, "Couldn't submit your receipt: $e");
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  /// Closes the dialog without touching the hold at all — the booking
  /// stays `awaiting_receipt` in Firestore exactly as it was, countdown
  /// and all. Used by both the back-button tap and the hardware/gesture
  /// back action, so however the customer backs out, [onMinimized] fires
  /// the same way and the caller can update its own state accordingly.
  void _handleMinimize() {
    if (_settled) return;
    _timer?.cancel();
    Navigator.of(context).pop();
    widget.onMinimized();
  }

  /// Where to send the payment — the studio's InstaPay / GCash QR with the
  /// account name and number, plus one-tap copy and tap-to-enlarge QR.
  Widget _buildGcashDetails(BuildContext context) {
    final textPrimary = AppPalette.textPrimary(context);
    final textMuted = AppPalette.textMuted(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.surface(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.qr_code_scanner_rounded, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text("Scan to pay via InstaPay",
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: textPrimary)),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _showQrFullscreen(context),
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white, // scanners need a light background, even in dark mode
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Image.asset(
                    StudioPaymentAccount.qrAsset,
                    width: 190,
                    height: 190,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      width: 190,
                      height: 190,
                      child: Center(child: Icon(Icons.qr_code_2_rounded, size: 80, color: Colors.black26)),
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.all(6),
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                  child: const Icon(Icons.zoom_out_map_rounded, size: 13, color: AppColors.onAccent),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text("Tap the QR to enlarge", style: TextStyle(fontSize: 10.5, color: textMuted)),
          const SizedBox(height: 14),
          Divider(height: 1, color: AppPalette.divider(context)),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 18, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Account name", style: TextStyle(fontSize: 11, color: textMuted)),
                    const SizedBox(height: 2),
                    Text(StudioPaymentAccount.accountName,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.phone_iphone_rounded, size: 18, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("GCash / InstaPay number", style: TextStyle(fontSize: 11, color: textMuted)),
                    const SizedBox(height: 2),
                    Text(StudioPaymentAccount.formattedNumber,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: textPrimary)),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: StudioPaymentAccount.accountNumber));
                  AppToast.show(context, "Number copied");
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text("Copy"),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  backgroundColor: AppColors.accent.withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showQrFullscreen(BuildContext context) {
    final maxQrHeight = MediaQuery.of(context).size.height * 0.5;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          // Scrollable so it can never overflow on short screens.
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxQrHeight),
                  child: InteractiveViewer(
                    maxScale: 4,
                    child: Image.asset(StudioPaymentAccount.qrAsset, fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(StudioPaymentAccount.accountName,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black87)),
                const SizedBox(height: 2),
                Text(StudioPaymentAccount.formattedNumber,
                    style: const TextStyle(fontSize: 14, color: Colors.black54, letterSpacing: 0.6)),
                const SizedBox(height: 8),
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Close")),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentChoice(BuildContext context) {
    final total = _total!;
    final down = _settings.downpaymentFor(total);
    Widget option({
      required bool selected,
      required String title,
      required String amount,
      required String subtitle,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: _submitting ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected ? AppColors.accent.withValues(alpha: 0.08) : AppPalette.surface(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? AppColors.accent : AppPalette.divider(context), width: selected ? 1.6 : 1),
            ),
            child: Row(
              children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                    size: 20, color: selected ? AppColors.accent : AppPalette.textMuted(context)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
                      const SizedBox(height: 2),
                      Text(subtitle, style: TextStyle(fontSize: 11.5, height: 1.3, color: AppPalette.textMuted(context))),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(amount,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800, color: selected ? AppColors.accent : AppPalette.textPrimary(context))),
              ],
            ),
          ),
        ),
      );
    }

    if (!_canSplit) {
      // Full payment only — just state the amount to send.
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(14)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Amount to send", style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context))),
            Text(formatPeso(total),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.accent)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("How much will you pay now?",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
        const SizedBox(height: 8),
        option(
          selected: !_payFull,
          title: "Downpayment (${_settings.label})",
          amount: formatPeso(down),
          subtitle: "Reserves your date. Pay the remaining ${formatPeso(total - down)} on the event day.",
          onTap: () => setState(() => _payFull = false),
        ),
        option(
          selected: _payFull,
          title: "Full payment",
          amount: formatPeso(total),
          subtitle: "Nothing left to pay later.",
          onTap: () => setState(() => _payFull = true),
        ),
        Text(
          "Send exactly ${formatPeso(_amountDueNow ?? total)} via InstaPay / GCash, then upload the receipt below.",
          style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
        ),
      ],
    );
  }

  /// A red card shown the instant a non-receipt (or unreadable) screenshot is
  /// attached, explaining why Submit is disabled.
  Widget _buildRejectedCard(BuildContext context, {required String title, required String body}) {
    const red = Color(0xFFDC2626);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: red.withValues(alpha: 0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.block_rounded, size: 18, color: red),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
                const SizedBox(height: 3),
                Text(body, style: TextStyle(fontSize: 11.5, height: 1.35, color: AppPalette.textSecondary(context))),
              ],
            ),
          ),
          IconButton(
            onPressed: _submitting ? null : () => setState(() => _receipt = null),
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove and upload another',
            icon: Icon(Icons.delete_outline_rounded, size: 18, color: AppPalette.textSecondary(context)),
          ),
        ],
      ),
    );
  }

  /// Shows what OCR read off the receipt and flags anything that doesn't
  /// line up with what the customer should have sent. A screenshot that
  /// isn't a payment receipt (or can't be read at all) blocks submitting; the
  /// amount / recipient warnings below stay advisory — staff still verify.
  Widget _buildOcrCheck(BuildContext context) {
    if (_notReceipt) {
      return _buildRejectedCard(
        context,
        title: "This doesn't look like a payment receipt",
        body: "You can't book with this screenshot. Upload the receipt you got after sending the payment — "
            "GCash, Maya, or your bank app all work (it should show the amount and the reference no.).",
      );
    }
    if (_unreadable) {
      return _buildRejectedCard(
        context,
        title: "We couldn't read this screenshot",
        body: "We need to confirm it's a payment receipt before you can book. Upload a clearer, full screenshot of the receipt.",
      );
    }
    final ocr = _receipt?.ocr;
    if (ocr == null) return const SizedBox.shrink();

    final warnings = <String>[];
    final due = _amountDueNow;
    if (ocr.amount != null && due != null && (ocr.amount! - due).abs() >= 0.5) {
      warnings.add("The receipt shows ${formatPeso(ocr.amount!.round())} but the amount due is ${formatPeso(due)}.");
    }
    if (ocr.recipientNumber != null) {
      final studio = ReceiptOcr.normalizeNumber(StudioPaymentAccount.accountNumber);
      if (studio.isNotEmpty && ocr.recipientNumber != studio) {
        warnings.add("The receipt was sent to ${ocr.recipientNumber}, not the studio's account number.");
      }
    }

    final ok = ocr.foundAnything && warnings.isEmpty;
    final color = ok ? AppColors.success : Colors.orange;

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
              Text(value,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
            ],
          ),
        );

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ok ? Icons.verified_outlined : Icons.info_outline, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                ok
                    ? "Receipt scanned"
                    : ocr.foundAnything
                        ? "Please double-check your receipt"
                        : "Couldn't read this receipt clearly",
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context)),
              ),
            ],
          ),
          if (ocr.amount != null) row("Amount", formatPeso(ocr.amount!.round())),
          if (ocr.referenceDisplay != null) row("Ref No.", ocr.referenceDisplay!),
          if (ocr.recipientNumber != null) row("Sent to", ocr.recipientNumber!),
          for (final w in warnings)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(w, style: TextStyle(fontSize: 11.5, height: 1.35, color: AppPalette.textSecondary(context))),
            ),
          if (!ocr.foundAnything && warnings.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text("You can still submit — staff will check it manually.",
                  style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // The hardware/gesture back action is routed through the same
      // _handleMinimize() the visible back button uses, rather than being
      // allowed to pop (and thus close) the dialog on its own — that way
      // onMinimized always fires no matter how the customer backs out.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleMinimize();
      },
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: AppPalette.bg(context),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Lets the customer step away and browse the rest of the app
              // without losing the hold — see the class doc. Doesn't touch
              // the countdown or the booking; just closes this dialog.
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    CircleBackButton(
                      onPressed: _handleMinimize,
                      tooltip: "Explore the app — come back to this later",
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "You can browse the app and finish this from My Bookings later.",
                        style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
                      ),
                    ),
                  ],
                ),
              ),
              // Presentational only here — this modal drives the real
              // countdown itself (anchored to holdExpiresAt), so onTick is
              // a no-op.
              CountdownTimer(
                seconds: _secondsLeft,
                onTick: (_) {},
                totalSeconds: widget.holdDurationSeconds,
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Send Your Payment Receipt",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "We're holding your slot for 15 minutes. Upload your payment receipt before the timer runs out, "
                        "or the booking will be automatically rejected and the date released.",
                        style: TextStyle(fontSize: 12.5, height: 1.4, color: AppPalette.textMuted(context)),
                      ),
                      if (_total != null) ...[
                        const SizedBox(height: 16),
                        _buildPaymentChoice(context),
                      ],
                      const SizedBox(height: 12),
                      _buildGcashDetails(context),
                      const SizedBox(height: 20),
                      ReceiptUpload(
                        receipt: _receipt,
                        rejected: _notReceipt || _unreadable,
                        onChanged: (r) => setState(() => _receipt = r),
                      ),
                      _buildOcrCheck(context),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _canSubmit ? _handleSubmitReceipt : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (_receipt != null && !_notReceipt && !_unreadable) ? AppColors.accent : AppPalette.surface(context),
                      disabledBackgroundColor: AppPalette.surface(context),
                      foregroundColor: (_receipt != null && !_notReceipt && !_unreadable) ? AppColors.onAccent : const Color(0xFF9CA3AF),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAccent),
                          )
                        : Text(
                            _notReceipt || _unreadable
                                ? "Upload a valid payment receipt to continue"
                                : _receipt != null
                                    ? "Confirm & Submit Booking"
                                    : "Upload a receipt to continue",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
