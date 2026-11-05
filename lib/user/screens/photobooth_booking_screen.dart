import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/booth_package.dart';
import '../services/auth_service.dart';
import '../services/booking_hours.dart';
import '../services/booking_repository.dart';
import '../services/pricing_repository.dart';
import '../services/server_clock.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/date_selector.dart';
import '../widgets/time_selector.dart';
import '../widgets/package_selector.dart';
import '../widgets/addon_selector.dart';
import '../widgets/receipt_upload_modal.dart';
import '../widgets/location_picker_screen.dart';
import 'booking_success_screen.dart';
import '../widgets/stream_once.dart';

/// Port of the default-exported `PhotoboothBooking` component.
///
/// This is used as the `child` content inside `AppLayoutShell` (which now
/// supplies the phone-frame chrome, drag handle, and floating bottom nav),
/// so this widget only builds the scrollable form and the fixed submit
/// bar. Booking no longer holds the slot the moment this screen opens —
/// tapping the submit bar places the hold and immediately opens
/// [ReceiptUploadModal], which is where the 15-minute countdown and the
/// payment-receipt upload actually live.
class PhotoboothBookingScreen extends StatefulWidget {
  /// Optional pre-fill, e.g. when the user taps a specific date or package
  /// on Home, or submits Home's search bar (which also carries a guest
  /// count) and gets routed here with it already chosen.
  final BookingIntent? intent;

  const PhotoboothBookingScreen({super.key, this.intent});

  @override
  State<PhotoboothBookingScreen> createState() => _PhotoboothBookingScreenState();
}

class _PhotoboothBookingScreenState extends State<PhotoboothBookingScreen> with WidgetsBindingObserver {
  static const int _holdDurationSeconds = 15 * 60;

  late DateTime? _selectedDate;
  RangeValues _timeRange = const RangeValues(10, 12); // 10:00 AM – 12:00 PM (2-hour package)
  late BoothPackage? _selectedPkg;
  final Set<String> _selectedAddOnIds = {};
  late int? _guests;
  PickedLocation? _location;
  bool _submitted = false;
  bool _submitting = false;

  /// Re-checks the 12 AM–6 AM booking curfew so the button/banner flip
  /// on their own the moment the clock crosses midnight or 6:00 AM.
  Timer? _hoursTimer;
  bool _bookingOpen = BookingHours.isOpen();

  /// Id of the `awaiting_receipt` hold placed by [_handleBookNow], live
  /// only for the moment between placing it and the receipt modal
  /// resolving (submitted or expired) — the calendar/date step above never
  /// holds anything on its own.
  String? _holdId;

  /// The exact hold deadline for [_holdId], kept around so the modal can
  /// be reopened from this screen (e.g. via [_resumeReceiptModal]) with
  /// the same countdown it started with, instead of a fresh 15 minutes.
  DateTime? _holdExpiresAt;

  /// True once the customer has backed out of [ReceiptUploadModal] via its
  /// back button without resolving it (sent, or expired). The hold is
  /// still alive in Firestore either way — this only means [dispose]
  /// shouldn't treat leaving this screen as "abandoned checkout" and
  /// cancel it. See [ReceiptUploadModal]'s class doc.
  bool _holdMinimized = false;

  String get _timeLabel => formatTimeRangeLabel(_timeRange);

  /// No network call — nothing is held until [_handleBookNow] runs, so
  /// changing dates while filling out the form is just local state.
  void _onDateChanged(DateTime date) => setState(() => _selectedDate = date);

  void _showDateTakenSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(builder: (_) => LocationPickerScreen(initial: _location)),
    );
    if (result != null) setState(() => _location = result);
  }

  @override
  void initState() {
    super.initState();
    final d = DateTime.now();
    final fallbackDate = DateTime(d.year, d.month, d.day + 2);
    _selectedDate = widget.intent?.date ?? fallbackDate;
    _selectedPkg = widget.intent?.package ?? kPackages[1]; // "premium" matches the original default
    _guests = widget.intent?.guests;
    WidgetsBinding.instance.addObserver(this);
    _hoursTimer = Timer.periodic(const Duration(seconds: 20), (_) => _refreshBookingOpen());
    // Measure Firebase's clock once up front, then re-check the curfew.
    unawaited(ServerClock.sync().then((_) => _refreshBookingOpen()));
  }

  /// Re-reads the device clock and flips the closed banner / button if the
  /// 12 AM–6 AM window has started or ended.
  void _refreshBookingOpen() {
    final open = BookingHours.isOpen();
    if (mounted && open != _bookingOpen) setState(() => _bookingOpen = open);
  }

  /// Timers can be paused while the app is backgrounded, so re-check the
  /// clock the moment the customer comes back to the app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshBookingOpen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hoursTimer?.cancel();
    // Safety net only: normally the receipt modal itself owns the hold
    // from the moment it's placed and releases it on expiry/submit. This
    // only fires if the screen gets torn down in between (e.g. the hold
    // just landed but the modal never got a chance to show) — NOT when the
    // customer used the modal's back button to go explore the app, since
    // then the hold is meant to keep living on in My Bookings until it's
    // resolved or its own countdown runs out.
    final id = _holdId;
    if (id != null && !_submitted && !_holdMinimized) {
      BookingRepository.expireHold(id, reason: 'Customer left checkout before sending a receipt.');
    }
    super.dispose();
  }

  List<BoothAddOn> get _selectedAddOns =>
      kAddOns.where((a) => _selectedAddOnIds.contains(a.id)).toList();

  int get _addOnsTotal => _selectedAddOns.fold(0, (sum, a) => sum + a.price);

  int get _grandTotal => (_selectedPkg?.price ?? 0) + _addOnsTotal;

  void _toggleAddOn(BoothAddOn addOn) {
    setState(() {
      if (_selectedAddOnIds.contains(addOn.id)) {
        _selectedAddOnIds.remove(addOn.id);
      } else {
        _selectedAddOnIds.add(addOn.id);
      }
    });
  }

  bool get _canSubmit =>
      _bookingOpen &&
      !_submitting &&
      _selectedDate != null &&
      _selectedPkg != null &&
      _location != null &&
      (_timeRange.end - _timeRange.start) <= kMaxBookingHours + 0.001; // max 2 hours

  /// The single next thing standing between the customer and booking —
  /// shown both in the progress strip and on the CTA button itself, so
  /// they never have to guess or scroll around to find what's missing.
  String get _nextStepLabel {
    if (!_bookingOpen) return "Booking closed · opens 6:00 AM";
    if (_selectedDate == null) return "Pick a date to continue";
    if (_location == null) return "Pin your event location to continue";
    if (_selectedPkg == null) return "Choose a package to continue";
    return "Ready — hold your slot and send payment next";
  }

  /// Short version of [_nextStepLabel] for the button (it shares the bar
  /// with the running total, so it has less room).
  String get _ctaLabel {
    if (!_bookingOpen) return "Booking closed";
    if (_selectedDate == null) return "Pick a date";
    if (_location == null) return "Pin location";
    if (_selectedPkg == null) return "Choose a package";
    return "Book & hold slot";
  }

  /// Card wrapper shared by every form section so the page reads as a
  /// stack of clear, separate steps.
  Widget _sectionCard(BuildContext context, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppPalette.divider(context)),
        boxShadow: AppShadows.soft,
      ),
      child: child,
    );
  }

  /// Places the 15-minute hold for whatever's currently selected, then
  /// immediately opens [ReceiptUploadModal] — that's where the countdown
  /// actually starts and where the customer sends their payment receipt.
  Future<void> _handleBookNow() async {
    if (!BookingHours.isOpen()) {
      setState(() => _bookingOpen = false);
      _showDateTakenSnack(BookingHours.closedMessage);
      return;
    }
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    try {
      final user = await AuthService.instance.me();
      if (user == null) throw Exception("Could not sign in");

      final hold = await BookingRepository.reserveSlot(
        userId: user.uid,
        customerName: user.fullName,
        package: _selectedPkg!,
        addOns: _selectedAddOns,
        date: _selectedDate!,
        time: _timeLabel,
        guests: _guests,
        location: _location!.address,
        locationLat: _location!.lat,
        locationLng: _location!.lng,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _holdId = hold.id;
        _holdExpiresAt = hold.holdExpiresAt;
        _holdMinimized = false;
      });
      _openReceiptModal(userId: user.uid, holdExpiresAt: hold.holdExpiresAt);
    } on BookingClosedException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _bookingOpen = false;
      });
      _showDateTakenSnack(e.message);
    } on DateUnavailableException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showDateTakenSnack(e.message);
    } catch (e, stackTrace) {
      debugPrint('Booking hold failed: $e');
      debugPrintStack(stackTrace: stackTrace);

      final message = e is FirebaseException
          ? (e.message ?? e.code ?? 'Unknown Firebase error')
          : e.toString();

      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't hold that slot: $message")),
      );
    }
  }

  /// Opens the receipt-upload modal for the hold just placed, anchored to
  /// [holdExpiresAt] (the server-computed moment the hold actually lapses)
  /// rather than a fresh local 15-minute count — see
  /// [ReceiptUploadModal] for why that distinction matters.
  void _openReceiptModal({required String userId, required DateTime holdExpiresAt}) {
    final id = _holdId;
    if (id == null) return;
    ReceiptUploadModal.show(
      context,
      bookingId: id,
      userId: userId,
      holdExpiresAt: holdExpiresAt,
      holdDurationSeconds: _holdDurationSeconds,
      onExpired: () {
        _holdId = null;
        _holdExpiresAt = null;
        _showExpiredDialog();
      },
      onSubmitted: () {
        if (!mounted) return;
        setState(() {
          _submitted = true;
          _holdId = null;
          _holdExpiresAt = null;
        });
      },
      onMinimized: () {
        if (!mounted) return;
        setState(() => _holdMinimized = true);
      },
    );
  }

  /// Reopens [ReceiptUploadModal] for the hold this screen already placed
  /// — used by the "Continue to Payment" banner that replaces the booking
  /// form once the customer has minimized the modal at least once. Reuses
  /// the same [_holdExpiresAt] rather than starting a fresh 15 minutes.
  Future<void> _resumeReceiptModal() async {
    final userId = await AuthService.instance.me().then((u) => u?.uid);
    final expiresAt = _holdExpiresAt;
    if (!mounted || userId == null || expiresAt == null) return;
    setState(() => _holdMinimized = false);
    _openReceiptModal(userId: userId, holdExpiresAt: expiresAt);
  }

  void _handleReset() {
    setState(() {
      _submitted = false;
      _holdId = null;
    });
  }

  Future<void> _showExpiredDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Your held slot expired"),
        content: const Text(
          "The 15-minute hold ran out before your payment receipt came through, so the booking was "
          "automatically rejected and the date was released. You can try booking again.",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacementNamed('/');
            },
            child: const Text("Back to Home"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Try Again"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return BookingSuccessScreen(
        pkg: _selectedPkg!,
        addOns: _selectedAddOns,
        date: _selectedDate!,
        time: _timeLabel,
        location: _location?.address,
        onReset: _handleReset,
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.of(context).pushReplacementNamed('/'),
                            child: Container(
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: AppPalette.surface(context), shape: BoxShape.circle),
                              child: Icon(Icons.arrow_back_rounded, size: 22, color: AppPalette.textPrimary(context)),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Book your booth",
                                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: AppPalette.textPrimary(context)),
                                ),
                                const SizedBox(height: 2),
                                Text("Capture moments worth keeping", style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context))),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 44,
                            height: 44,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: AppColors.brandCream, borderRadius: BorderRadius.circular(16)),
                            child: Image.asset('assets/images/memoriae_logo.webp', fit: BoxFit.contain),
                          ),
                        ],
                      ),
                    ),
                    if (!_bookingOpen)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: _buildClosedBanner(context),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: _buildProgressStrip(context),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 130),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionCard(context, StreamOnce<Set<DateTime>>(
                            create: () => BookingRepository.watchBookedDates(ignoreBookingId: _holdId),
                            identity: _holdId,
                            builder: (context, snapshot) {
                              return DateSelector(
                                selectedDate: _selectedDate,
                                bookedDates: snapshot.data ?? const {},
                                onSelect: _onDateChanged,
                              );
                            },
                          )),
                          const SizedBox(height: 16),
                          _sectionCard(
                            context,
                            TimeSelector(
                              range: _timeRange,
                              onChanged: (r) => setState(() => _timeRange = r),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _sectionCard(context, _buildLocationSection(context)),
                          const SizedBox(height: 16),
                          _sectionCard(context, StreamOnce<List<BoothPackage>>(
                            create: () => PricingRepository.watchPackages(),
                            builder: (context, snapshot) {
                              final packages = (snapshot.data == null || snapshot.data!.isEmpty) ? kPackages : snapshot.data!;
                              return PackageSelector(
                                packages: packages,
                                selectedPkg: _selectedPkg,
                                onSelect: (p) => setState(() => _selectedPkg = p),
                              );
                            },
                          )),
                          const SizedBox(height: 16),
                          _sectionCard(
                            context,
                            AddOnSelector(
                              selectedIds: _selectedAddOnIds,
                              onToggle: _toggleAddOn,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildSummary(context),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
              decoration: BoxDecoration(
                color: AppPalette.cardBg(context),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: AppPalette.divider(context)),
                boxShadow: AppShadows.card,
              ),
              child: Row(
                children: [
                  if (!_holdMinimized) ...[
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Total", style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
                        Text(
                          formatPeso(_grandTotal),
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppPalette.textPrimary(context)),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        // While a hold is minimized, this bar's only job is
                        // getting the customer back to the receipt they still owe
                        // — tapping "Book" again here would try to place a
                        // second hold on top of the one already sitting in
                        // My Bookings as "Awaiting Receipt".
                        onPressed: _holdMinimized
                            ? _resumeReceiptModal
                            : (_canSubmit ? () => _handleBookNow() : null),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: (_holdMinimized || _canSubmit) ? AppColors.accent : AppPalette.surface(context),
                          disabledBackgroundColor: AppPalette.surface(context),
                          foregroundColor: (_holdMinimized || _canSubmit) ? Colors.white : const Color(0xFF9CA3AF),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          elevation: 0,
                          shape: const StadiumBorder(),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_submitting) ...[
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              ),
                              const SizedBox(width: 10),
                              const Flexible(
                                child: Text("Holding…", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                              ),
                            ] else if (_holdMinimized) ...[
                              const Icon(Icons.receipt_long_rounded, size: 18, color: Colors.white),
                              const SizedBox(width: 8),
                              const Flexible(
                                child: Text("Continue to payment", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                              ),
                            ] else ...[
                              Flexible(
                                child: Text(
                                  _ctaLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                ),
                              ),
                              if (_canSubmit) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.arrow_forward_rounded, size: 18),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildClosedBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accentTint(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accentTint(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.nightlight_round, size: 18, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Bookings are closed for now",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.accent),
                ),
                const SizedBox(height: 2),
                Text(
                  "We don't accept bookings from 12:00 AM to 6:00 AM. You can book again starting 6:00 AM.",
                  style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressStrip(BuildContext context) {
    const labels = ["Date", "Time", "Location", "Package"];
    const icons = [Icons.event_rounded, Icons.schedule_rounded, Icons.location_on_rounded, Icons.photo_camera_rounded];
    final done = [
      _selectedDate != null,
      true, // a time range is always set (defaults to 10 AM–5 PM)
      _location != null,
      _selectedPkg != null,
    ];
    final allDone = done.every((d) => d);
    final accentText = Theme.of(context).brightness == Brightness.dark ? const Color(0xFFE57F84) : AppColors.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 19, left: 6, right: 6),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 2,
                      decoration: BoxDecoration(
                        color: done[i - 1] && done[i] ? AppColors.accent : AppPalette.divider(context),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done[i] ? AppColors.accent : AppPalette.surface(context),
                      boxShadow: done[i] ? AppShadows.accentGlowSmall : null,
                    ),
                    child: Icon(
                      done[i] ? Icons.check_rounded : icons[i],
                      size: 18,
                      color: done[i] ? Colors.white : AppPalette.textMuted(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: done[i] ? AppPalette.textPrimary(context) : AppPalette.textMuted(context),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: allDone ? AppColors.accentTint(0.08) : AppPalette.surface(context),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(allDone ? Icons.check_circle_rounded : Icons.info_outline_rounded, size: 16, color: allDone ? accentText : AppPalette.textMuted(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _nextStepLabel,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: allDone ? accentText : AppPalette.textSecondary(context)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLocationSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.location_on_outlined, size: 16, color: AppColors.accent),
            const SizedBox(width: 8),
            Text("Event Location", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context))),
          ],
        ),
        const SizedBox(height: 12),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _pickLocation,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppPalette.surface(context),
                borderRadius: BorderRadius.circular(20),
                border: _location == null ? Border.all(color: AppColors.accentTint(0.3)) : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.accentTint(0.12), shape: BoxShape.circle),
                    child: const Icon(Icons.map_outlined, size: 18, color: AppColors.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _location?.address ?? "Pin your event location",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _location != null
                              ? '${_location!.lat.toStringAsFixed(4)}° N, ${_location!.lng.toStringAsFixed(4)}° E'
                              : "Tap to drop a pin on the map",
                          style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context)),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: AppPalette.textMuted(context)),
                ],
              ),
            ),
          ),
        ),
        if (_location != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 90,
              width: double.infinity,
              color: AppPalette.surface(context),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_on, color: Color(0xFFD32F2F), size: 22),
                  const SizedBox(width: 8),
                  Text(
                    '${_location!.lat.toStringAsFixed(4)}° N, ${_location!.lng.toStringAsFixed(4)}° E',
                    style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSummary(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.accent, Color(0xFF3A1214)]),
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppShadows.accentGlow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text("Booking Summary", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          _summaryRow(context, "Package", _selectedPkg?.name ?? "—"),
          _summaryRow(
            context,
            "Date & Time",
            "${_selectedDate != null ? DateFormat('MMM d').format(_selectedDate!) : '—'} · $_timeLabel",
          ),
          _summaryRow(context, "Location", _location?.address ?? "—"),
          _summaryRow(context, "Duration", _selectedPkg?.duration ?? "—"),
          if (_guests != null) _summaryRow(context, "Guests", '$_guests'),
          for (final a in _selectedAddOns) _summaryRow(context, a.name, "+${formatPeso(a.price)}"),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: Colors.white24)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Total", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
              Text(
                formatPeso(_grandTotal),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
        ],
      ),
    );
  }
}