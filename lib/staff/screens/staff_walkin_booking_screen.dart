import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/pricing_item_record.dart';
import '../../shared/text_draft.dart';
import '../../shared/top_toast.dart';
import '../services/auth_service.dart';
import '../services/staff_settings.dart';
import '../services/booking_repository.dart';
import '../services/pricing_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/dashboard_kit.dart';
import '../widgets/package_photo.dart';
import '../../user/services/studio_payment_account.dart';

String _peso(int amount) => '₱${NumberFormat('#,##0').format(amount)}';

/// One-stop walk-in flow: book a package for a customer standing right
/// in front of staff, and ring up their payment (Cash or GCash)
/// in the same step — see `BookingRepository.createWalkInBookingWithPayment`
/// for how this stays a single atomic write.
///
/// Redesigned as sectioned cards (Customer / Package / Schedule /
/// Payment) with a sticky total + confirm bar. Packages are shown as photo
/// cards (the same photos Admin uploads on the Pricing screen), and picking
/// GCash reveals the studio's InstaPay QR for the customer to scan. Fixes
/// vs. the old form:
///  * the date picker no longer crashes when today is already locked
///    (`initialDate` must satisfy `selectableDayPredicate`) — it now
///    starts on the first free date;
///  * the package is tracked by id, not by object, so the selection
///    survives the pricing stream re-emitting (the old Dropdown threw
///    "exactly one item with value" because the record has no `==`);
///  * the email lookup can no longer hang the spinner or throw an
///    unhandled Firestore error (permission-denied / offline);
///  * Firestore failures show readable messages instead of raw
///    `[cloud_firestore/...]` strings, and the write has a timeout.
class StaffWalkInBookingScreen extends StatefulWidget {
  const StaffWalkInBookingScreen({super.key});

  @override
  State<StaffWalkInBookingScreen> createState() => _StaffWalkInBookingScreenState();
}

class _StaffWalkInBookingScreenState extends State<StaffWalkInBookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _contactController = TextEditingController();
  final _guestsController = TextEditingController();
  final _occasionController = TextEditingController();
  final _cashReceivedController = TextEditingController();
  late final TextDraft _draft;
  final _emailFocus = FocusNode();

  DateTime _date = DateTime.now();
  bool _dateTouched = false;
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  String? _selectedPackageId;
  String _paymentMethod = StaffSettings.defaultPayment.value;
  bool _lookingUp = false;
  String? _matchedUserId;
  String _lastLookedUpEmail = '';
  bool _submitting = false;
  String? _error;
  bool _packageError = false;

  static final _emailPattern = RegExp(r'^[\w\.\-\+]+@[\w\-]+\.[\w\-\.]+$');

  /// Hard limits — the fields stop accepting input once these are reached.
  static const int _nameMax = 30;
  static const int _phoneLen = 11;

  /// Newest set of taken dates from the live stream, so the date picker and
  /// the pick-check always use fresh data (not what it was when it opened).
  Set<DateTime> _latestLocked = <DateTime>{};

  @override
  void initState() {
    super.initState();
    _draft = TextDraft('walkin_booking_draft_v1', {
      'name': _nameController,
      'email': _emailController,
      'contact': _contactController,
      'guests': _guestsController,
      'occasion': _occasionController,
    });
    _draft.restore(() {
      _sanitizeRestored();
      if (mounted) setState(() {});
    });
    _emailFocus.addListener(() {
      if (!_emailFocus.hasFocus) _lookupEmail();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    _guestsController.dispose();
    _occasionController.dispose();
    _cashReceivedController.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  // ───────────────────────── helpers ─────────────────────────

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  String _clipName(String s) {
    final v = s.trim();
    return v.length > _nameMax ? v.substring(0, _nameMax).trimRight() : v;
  }

  String _cleanPhone(String s) {
    final digits = s.replaceAll(RegExp(r'\D'), '');
    return digits.length > _phoneLen ? digits.substring(0, _phoneLen) : digits;
  }

  /// A saved draft (or an autofilled customer) can hold text from before the
  /// limits existed — trim it to what the fields would accept.
  void _sanitizeRestored() {
    final n = _clipName(_nameController.text);
    if (n != _nameController.text) _nameController.text = n;
    final p = _cleanPhone(_contactController.text);
    if (p != _contactController.text) _contactController.text = p;
  }

  bool _isLocked(DateTime d, Set<DateTime> locked) => locked.any((l) => _day(l) == _day(d));

  DateTime _firstFree(Set<DateTime> locked) {
    var d = _day(DateTime.now());
    for (var i = 0; i < 366 && _isLocked(d, locked); i++) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  String _formatTime(TimeOfDay t) {
    final dt = DateTime(2000, 1, 1, t.hour, t.minute);
    return DateFormat('h:mm a').format(dt);
  }

  int get _cashReceived => int.tryParse(_cashReceivedController.text.trim()) ?? 0;

  /// Turns Firestore/Exception errors into something staff can act on.
  String _friendlyError(Object e) {
    if (e is TimeoutException) {
      return "Connection is slow — the booking may not have saved. Check the Bookings list before trying again.";
    }
    if (e is FirebaseException) {
      switch (e.code) {
        case 'permission-denied':
          return "You don't have permission to do that. Ask the admin to check your staff account / Firestore rules.";
        case 'unavailable':
        case 'network-request-failed':
          return "No connection to the server. Check the internet and try again.";
        case 'deadline-exceeded':
          return "The server took too long to respond. Try again in a moment.";
        case 'aborted':
          return "Another booking was saved at the same moment. Please try again.";
        case 'failed-precondition':
          return "Firestore isn't set up for this action yet (missing index or rule).";
        default:
          return "Something went wrong (${e.code}). Please try again.";
      }
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  Future<void> _lookupEmail() async {
    final email = _emailController.text.trim();
    if (!_emailPattern.hasMatch(email) || _vEmail(email) != null || email == _lastLookedUpEmail) return;
    _lastLookedUpEmail = email;
    setState(() => _lookingUp = true);
    try {
      final match = await BookingRepository.findCustomerByEmail(email).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() {
        _matchedUserId = match?['uid'] as String?;
        if (match != null) {
          if (_nameController.text.trim().isEmpty) _nameController.text = _clipName((match['fullName'] ?? '') as String);
          if (_contactController.text.trim().isEmpty) _contactController.text = _cleanPhone((match['contactNumber'] ?? '') as String);
        }
      });
    } catch (_) {
      // Lookup is a convenience only — if it fails (offline, rules) the
      // walk-in can still be booked as a guest, so never block on it.
      if (mounted) setState(() => _matchedUserId = null);
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  Future<void> _pickDate(Set<DateTime> locked) async {
    final first = _day(DateTime.now());
    var initial = _day(_date);
    if (initial.isBefore(first) || _isLocked(initial, locked)) initial = _firstFree(locked);
    final picked = await showDatePicker(
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: first.add(const Duration(days: 365)),
      helpText: 'Select an available date',
      // Read the live set so a date someone books while this calendar is
      // open greys out right away.
      selectableDayPredicate: (d) => !_isLocked(d, _latestLocked),
    );
    if (picked != null && _isLocked(picked, _latestLocked)) {
      if (mounted) {
        TopToast.show(context, "That date was just taken by another booking — pick a different date.", kind: TopToastKind.error);
      }
      return;
    }
    if (picked != null) {
      setState(() {
      _date = picked;
      _dateTouched = true;
    });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  // ───────────────────────── validators ─────────────────────────

  String? _vName(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return "Enter the customer's name.";
    if (s.length < 2) return "Name is too short.";
    if (s.length > _nameMax) return "Name can be $_nameMax characters at most.";
    if (!RegExp(r"^[\p{L}][\p{L}\s.'\-]*$", unicode: true).hasMatch(s)) {
      return "Letters only — no numbers or symbols.";
    }
    return null;
  }

  /// Same email rules as the User app's register screen, so a walk-in
  /// customer's address is checked exactly like an online sign-up.
  String? _vEmail(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return "Enter an email address.";
    if (value.length > 254) return "Email is too long.";
    if (RegExp(r'\s').hasMatch(value)) return "Email can't contain spaces.";
    if (value.contains('..')) return "Email can't have two dots in a row.";
    final atIndex = value.indexOf('@');
    if (atIndex > 0 && value.substring(0, atIndex).endsWith('.')) {
      return "Enter a valid email address.";
    }
    if (!RegExp(
      r"^[A-Za-z0-9][A-Za-z0-9._%+\-]*@(?:[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}$",
    ).hasMatch(value)) {
      return "Enter a valid email address.";
    }
    final suggestion = _suggestEmailFix(value);
    if (suggestion != null) return "Did you mean $suggestion?";
    return null;
  }

  /// Common domain typos -> the domain people almost certainly meant.
  static const Map<String, String> _domainTypos = {
    'gmial.com': 'gmail.com', 'gmai.com': 'gmail.com', 'gmal.com': 'gmail.com', 'gamil.com': 'gmail.com',
    'gmaill.com': 'gmail.com', 'gmail.co': 'gmail.com', 'gmail.cm': 'gmail.com', 'gmil.com': 'gmail.com',
    'gnail.com': 'gmail.com', 'yaho.com': 'yahoo.com', 'yahho.com': 'yahoo.com', 'yahoo.co': 'yahoo.com',
    'yahooo.com': 'yahoo.com', 'hotmial.com': 'hotmail.com', 'hotmal.com': 'hotmail.com',
    'outlok.com': 'outlook.com', 'outloo.com': 'outlook.com', 'iclod.com': 'icloud.com', 'icoud.com': 'icloud.com',
  };

  /// Returns the corrected address if the domain looks like a typo of a
  /// well-known provider (or ends in ".con"), otherwise null.
  static String? _suggestEmailFix(String email) {
    final at = email.lastIndexOf('@');
    if (at < 1) return null;
    final local = email.substring(0, at);
    final domain = email.substring(at + 1).toLowerCase();
    final fixed = _domainTypos[domain];
    if (fixed != null) return '$local@$fixed';
    if (domain.endsWith('.con')) return '$local@${domain.substring(0, domain.length - 1)}m';
    return null;
  }

  String? _vPhone(String? v) {
    final digits = (v ?? '').trim();
    if (digits.isEmpty) return "Enter a contact number.";
    if (!RegExp(r'^\d+$').hasMatch(digits)) return "Numbers only, please.";
    final head = digits.length >= 2 ? digits.substring(0, 2) : digits;
    if (!'09'.startsWith(head)) return "Mobile numbers start with 09.";
    if (digits.length < _phoneLen) return "Enter all $_phoneLen digits (e.g. 09171234567).";
    if (digits.length > _phoneLen) return "Mobile numbers are exactly $_phoneLen digits.";
    return null;
  }

  String? _vGuests(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    final n = int.tryParse(s);
    if (n == null || n < 1) return "Must be at least 1.";
    if (n > 500) return "That's a lot — max 500.";
    return null;
  }

  String? _vCash(String? v) {
    if (_paymentMethod != 'cash') return null;
    final s = (v ?? '').trim();
    if (s.isEmpty) return "Enter the cash received.";
    final n = int.tryParse(s);
    if (n == null) return "Numbers only.";
    if (n < _total(_packages)) return "Less than the total (${_peso(_total(_packages))}).";
    return null;
  }

  List<PricingItemRecord> _packages = const [];
  PricingItemRecord? get _selected {
    for (final p in _packages) {
      if (p.id == _selectedPackageId) return p;
    }
    return null;
  }

  int _total(List<PricingItemRecord> _) => _selected?.price ?? 0;

  Future<void> _submit(Set<DateTime> locked) async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();

    final pkg = _selected;
    setState(() => _packageError = pkg == null);
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid || pkg == null) {
      setState(() => _error = "Please fix the highlighted fields.");
      return;
    }
    if (pkg.price <= 0) {
      setState(() => _error = "This package has no price set. Ask the admin to update Pricing first.");
      return;
    }
    if (_day(_date).isBefore(_day(DateTime.now()))) {
      setState(() => _error = "The date is in the past — pick today or later.");
      return;
    }
    if (_isLocked(_date, locked)) {
      setState(() => _error = "That date is already taken. Pick a different date.");
      return;
    }

    final int? amountReceived = _paymentMethod == 'cash' ? _cashReceived : null;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final staffId = AuthService.instance.currentUid ?? '';
      final staffEmail = AuthService.instance.currentEmail ?? '';
      if (staffId.isEmpty) {
        throw Exception("Your session expired. Please sign in again.");
      }
      await BookingRepository.createWalkInBookingWithPayment(
        existingUserId: _matchedUserId,
        customerName: _nameController.text.trim(),
        customerEmail: _emailController.text.trim().toLowerCase(),
        customerContact: _contactController.text.trim(),
        packageId: pkg.id,
        packageName: pkg.name,
        duration: pkg.unit,
        price: pkg.price,
        date: _date,
        time: _formatTime(_time),
        guests: int.tryParse(_guestsController.text.trim()),
        occasion: _occasionController.text.trim(),
        paymentMethod: _paymentMethod,
        amountReceived: amountReceived,
        staffId: staffId,
        staffEmail: staffEmail,
      ).timeout(const Duration(seconds: 20));
      await _draft.clear();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _friendlyError(e);
      });
    }
  }

  // ───────────────────────── UI ─────────────────────────

  InputDecoration _decor(BuildContext context, {required String label, IconData? icon, Widget? suffix, String? prefixText, String? hint}) {
    OutlineInputBorder b(Color c, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c, width: w));
    return InputDecoration(
      isDense: true,
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: AppPalette.textMuted(context), fontSize: 13),
      floatingLabelStyle: const TextStyle(color: AppColors.accent, fontSize: 11.5, fontWeight: FontWeight.w600),
      hintStyle: TextStyle(color: AppPalette.textMuted(context), fontSize: 13),
      prefixText: prefixText,
      prefixStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context)),
      prefixIcon: icon == null ? null : Icon(icon, size: 17, color: AppColors.accent.withValues(alpha: 0.75)),
      prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 0),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppPalette.surface(context),
      contentPadding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
      border: b(AppPalette.divider(context)),
      enabledBorder: b(AppPalette.divider(context)),
      focusedBorder: b(AppColors.accent, 1.5),
      errorBorder: b(AppColors.accent, 1.2),
      focusedErrorBorder: b(AppColors.accent, 1.5),
      errorStyle: const TextStyle(fontSize: 11, color: AppColors.accent),
    );
  }

  Widget _section(
    BuildContext context, {
    required int step,
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppShadows.soft,
        border: Border.all(color: AppPalette.divider(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.accent, Color(0xFF9A3236)],
                  ),
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: AppShadows.accentGlowSmall,
                ),
                child: Icon(icon, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STEP $step',
                      style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: AppColors.accent),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      title,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: AppPalette.textPrimary(context)),
                    ),
                    if (subtitle != null)
                      Text(subtitle, style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _pickerField(BuildContext context, {required IconData icon, required String label, required String value, required VoidCallback onTap, bool error = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: _decor(
          context,
          label: label,
          icon: icon,
          suffix: Icon(Icons.expand_more_rounded, size: 18, color: AppPalette.textMuted(context)),
        ).copyWith(
          // Empty errorText = red border only; the message sits under the row.
          errorText: error ? '' : null,
          errorStyle: const TextStyle(fontSize: 0, height: 0),
        ),
        child: Text(value, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.surface(context),
      appBar: AppBar(
        backgroundColor: AppPalette.surface(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: const Text("New Walk-in Booking", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
      ),
      body: StreamBuilder<Set<DateTime>>(
        stream: BookingRepository.watchLockedDates(),
        builder: (context, lockedSnap) {
          final locked = lockedSnap.data ?? <DateTime>{};
          _latestLocked = locked;

          // If the default date (today) is already taken and staff haven't
          // chosen one yet, quietly move to the first free day.
          if (!_dateTouched && _isLocked(_date, locked)) {
            final free = _firstFree(locked);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_dateTouched) setState(() => _date = free);
            });
          }

          return StreamBuilder<List<PricingItemRecord>>(
            stream: PricingRepository.watchAllPricing(),
            builder: (context, pricingSnap) {
              if (pricingSnap.hasError) {
                return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text("Couldn't load packages: ${_friendlyError(pricingSnap.error!)}", textAlign: TextAlign.center, style: TextStyle(color: AppPalette.textMuted(context)))));
              }
              if (!pricingSnap.hasData) {
                return const Center(child: CircularProgressIndicator(color: AppColors.accent));
              }
              _packages = pricingSnap.data!.where((p) => p.category == 'Booth Package').toList();
              if (_selectedPackageId != null && _selected == null) _selectedPackageId = null;
              final total = _total(_packages);
              final dateTaken = _isLocked(_date, locked);

              return Column(
                children: [
                  Expanded(
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: _responsiveSections(
                        context,
                        header: const DashboardHeroBanner(
                          watermarkIcon: Icons.person_add_alt_1,
                          pillLabel: "WALK-IN",
                          title: "Book & pay in one step",
                          subtitle: "Add the customer, pick a package and take payment — all on this screen.",
                        ),
                        items: [
                          _section(
                            context,
                            step: 1,
                            icon: Icons.person_outline,
                            title: "Customer",
                            subtitle: "Who's booking?",
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: _nameController,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  maxLength: _nameMax,
                                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                                  decoration: _decor(context, label: "Full name", icon: Icons.badge_outlined),
                                  validator: _vName,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _emailController,
                                  focusNode: _emailFocus,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s')), LengthLimitingTextInputFormatter(254)],
                                  onChanged: (_) {
                                    if (_matchedUserId != null) setState(() => _matchedUserId = null);
                                    _lastLookedUpEmail = '';
                                  },
                                  onEditingComplete: () {
                                    _lookupEmail();
                                    FocusScope.of(context).nextFocus();
                                  },
                                  decoration: _decor(
                                    context,
                                    label: "Email",
                                    icon: Icons.mail_outline,
                                    suffix: _lookingUp
                                        ? const Padding(padding: EdgeInsets.all(13), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)))
                                        : (_matchedUserId != null ? const Icon(Icons.check_circle, color: AppColors.success) : null),
                                  ),
                                  validator: _vEmail,
                                ),
                                if (_matchedUserId != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6, left: 2),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text("Matched an existing customer — booking will show in their account.", style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _contactController,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  maxLength: _phoneLen,
                                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  decoration: _decor(context, label: "Contact number", icon: Icons.phone_outlined, hint: "09171234567"),
                                  validator: _vPhone,
                                ),
                              ],
                            ),
                          ),
                          _section(
                            context,
                            step: 2,
                            icon: Icons.photo_camera_back_outlined,
                            title: "Package",
                            subtitle: "Tap a photo to choose",
                            trailing: _packageError
                                ? const Text("Choose one", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.accent))
                                : (_selected != null
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                        decoration: BoxDecoration(color: AppColors.accentTint(0.10), borderRadius: BorderRadius.circular(999)),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.check_circle_rounded, size: 13, color: AppColors.accent),
                                            SizedBox(width: 4),
                                            Text("Selected", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accent)),
                                          ],
                                        ),
                                      )
                                    : null),
                            child: packages_empty(context)
                                ? Text("No booth packages yet — add them in Admin › Pricing.", style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context)))
                                : _packageGrid(context),
                          ),
                          _section(
                            context,
                            step: 3,
                            icon: Icons.event_outlined,
                            title: "Schedule",
                            subtitle: "When is the session?",
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: _pickerField(context, icon: Icons.calendar_today_outlined, label: "Date", value: DateFormat('EEE, MMM d, yyyy').format(_date), onTap: () => _pickDate(locked), error: dateTaken),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 2,
                                      child: _pickerField(context, icon: Icons.schedule, label: "Time", value: _formatTime(_time), onTap: _pickTime),
                                    ),
                                  ],
                                ),
                                if (dateTaken)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.block, size: 14, color: AppColors.accent),
                                        const SizedBox(width: 6),
                                        const Expanded(
                                          child: Text(
                                            "This date is already booked — pick another so it doesn't double-book.",
                                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.accent),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _guestsController,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                                        decoration: _decor(context, label: "Guests (optional)", icon: Icons.groups_outlined),
                                        validator: _vGuests,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _occasionController,
                                        textCapitalization: TextCapitalization.sentences,
                                        inputFormatters: [LengthLimitingTextInputFormatter(60)],
                                        decoration: _decor(context, label: "Occasion (optional)", icon: Icons.celebration_outlined),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          _section(
                            context,
                            step: 4,
                            icon: Icons.payments_outlined,
                            title: "Payment",
                            subtitle: _paymentMethod == 'cash' ? "Collect at the counter" : "Customer scans the QR below",
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: _paymentChip('cash', "Cash", "At the counter", Icons.payments_outlined)),
                                    const SizedBox(width: 10),
                                    Expanded(child: _paymentChip('gcash', "GCash", "Scan QR code", Icons.qr_code_2_rounded)),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 240),
                                  curve: Curves.easeOutCubic,
                                  alignment: Alignment.topCenter,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    switchInCurve: Curves.easeOut,
                                    switchOutCurve: Curves.easeIn,
                                    layoutBuilder: (current, previous) => Stack(
                                      alignment: Alignment.topCenter,
                                      children: [...previous, if (current != null) current],
                                    ),
                                    child: _paymentMethod == 'cash' ? _cashPanel(context, total) : _gcashPanel(context, total),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_error != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(color: AppColors.accentTint(0.08), borderRadius: BorderRadius.circular(12)),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.error_outline, size: 16, color: AppColors.accent),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.accent, fontSize: 12.5))),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  _bottomBar(context, total, locked),
                ],
              );
            },
          );
        },
      ),
    );
  }

  bool packages_empty(BuildContext context) => _packages.isEmpty;

  /// Packages as photo cards, two or three to a row depending on the width
  /// of the card they sit in. Every card has the same height (the name area
  /// is fixed to two lines) so the grid stays tidy whatever the names are.
  Widget _packageGrid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 10.0;
        final cols = c.maxWidth >= 600 ? 3 : 2;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final p in _packages) SizedBox(width: w, child: _packageCard(context, p)),
          ],
        );
      },
    );
  }

  Widget _packageCard(BuildContext context, PricingItemRecord p) {
    final selected = p.id == _selectedPackageId;
    final hasPhoto = PackagePhoto.hasPhoto(p.imageUrl);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() {
          _selectedPackageId = p.id;
          _packageError = false;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: selected ? AppColors.accentTint(0.05) : AppPalette.surface(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? AppColors.accent : AppPalette.divider(context), width: selected ? 2 : 1),
            boxShadow: selected ? AppShadows.accentGlowSmall : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PackagePhoto(imageUrl: p.imageUrl),
                    // Soft dark fade at the bottom so the duration chip is
                    // readable on any photo.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 52,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.45)],
                          ),
                        ),
                      ),
                    ),
                    if (p.unit.isNotEmpty)
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(999)),
                            child: Text(
                              p.unit.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    if (hasPhoto)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _previewPackage(p),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                            child: const Icon(Icons.zoom_out_map_rounded, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: AnimatedScale(
                        scale: selected ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutBack,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                          child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 32,
                      child: Text(
                        p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, height: 1.25, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context)),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _peso(p.price),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.accent),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bigger look at a package's photo (pinch/scroll to zoom) with its
  /// inclusions, so staff can show the customer what they get.
  void _previewPackage(PricingItemRecord p) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppPalette.cardBg(ctx),
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: InteractiveViewer(
                    maxScale: 4,
                    child: SizedBox.expand(child: PackagePhoto(imageUrl: p.imageUrl)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(p.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(ctx))),
                          ),
                          const SizedBox(width: 10),
                          Text(_peso(p.price), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.accent)),
                        ],
                      ),
                      if (p.unit.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(p.unit, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(ctx))),
                      ],
                      if (p.features.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        for (final f in p.features.take(6))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(Icons.check_circle_rounded, size: 14, color: AppColors.accent),
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(f, style: TextStyle(fontSize: 12.5, color: AppPalette.textSecondary(ctx)))),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppPalette.textSecondary(ctx),
                            side: BorderSide(color: AppPalette.divider(ctx)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text("Close"),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _selectedPackageId = p.id;
                              _packageError = false;
                            });
                            Navigator.of(ctx).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text("Select package", style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Narrow windows (phones): one scrolling column — the hero header, then
  /// the sections. Wide windows (desktop): the hero header across the top,
  /// then two columns side by side, Customer + Package on the left,
  /// Schedule + Payment on the right.
  Widget _responsiveSections(BuildContext context, {required Widget header, required List<Widget> items}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
            children: [header, const SizedBox(height: 14), ...items],
          );
        }
        final left = items.take(2).toList();
        final right = items.skip(2).toList();
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: left,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: right,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _quickCash(String label, int amount) {
    final active = _cashReceivedController.text.trim() == amount.toString();
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? Colors.white : AppPalette.textPrimary(context))),
      selected: active,
      showCheckmark: false,
      selectedColor: AppColors.accent,
      backgroundColor: AppPalette.surface(context),
      side: BorderSide(color: active ? AppColors.accent : AppPalette.divider(context)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      onSelected: (_) => setState(() => _cashReceivedController.text = amount.toString()),
    );
  }

  Widget _paymentChip(String value, String label, String caption, IconData icon) {
    final selected = _paymentMethod == value;
    return GestureDetector(
      onTap: () => setState(() => _paymentMethod = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.accent, Color(0xFF9A3236)])
              : null,
          color: selected ? null : AppPalette.surface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppColors.accent : AppPalette.divider(context)),
          boxShadow: selected ? AppShadows.accentGlowSmall : null,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: 0.18) : AppColors.accentTint(0.10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 17, color: selected ? Colors.white : AppColors.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: selected ? Colors.white : AppPalette.textPrimary(context)),
                  ),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: selected ? Colors.white70 : AppPalette.textMuted(context)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Cash: amount received, quick-pick chips, and the change to hand back.
  Widget _cashPanel(BuildContext context, int total) {
    final received = _cashReceived;
    final showChange = total > 0 && _cashReceivedController.text.isNotEmpty && received >= total;
    return Column(
      key: const ValueKey('cash'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _cashReceivedController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
          onChanged: (_) => setState(() {}),
          decoration: _decor(context, label: "Cash received", prefixText: '₱ '),
          validator: _vCash,
        ),
        if (total > 0) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _quickCash("Exact", total),
              for (final v in const [500, 1000, 2000, 5000])
                if (v > total) _quickCash(_peso(v), v),
            ],
          ),
        ],
        if (showChange)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.price_check_rounded, size: 20, color: Color(0xFF15803D)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text("Change to give back", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppPalette.textSecondary(context))),
                ),
                Text(_peso(received - total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: Color(0xFF15803D))),
              ],
            ),
          ),
      ],
    );
  }

  /// GCash: the studio's InstaPay QR for the customer to scan, the amount
  /// to send, and the account it goes to. The QR sits on a white tile with
  /// scanner-style corner brackets (scanners need a light background, even
  /// in dark mode). Tap it to enlarge.
  Widget _gcashPanel(BuildContext context, int total) {
    final textPrimary = AppPalette.textPrimary(context);
    final textMuted = AppPalette.textMuted(context);
    return Container(
      key: const ValueKey('gcash'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accentTint(0.08), AppColors.accentTint(0.02)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accentTint(0.25)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.qr_code_scanner_rounded, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text("Scan to pay with GCash", style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: textPrimary)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(color: AppPalette.cardBg(context), borderRadius: BorderRadius.circular(999), border: Border.all(color: AppPalette.divider(context))),
            child: total > 0
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("Amount to pay  ", style: TextStyle(fontSize: 12, color: textMuted)),
                      Text(_peso(total), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.accent)),
                    ],
                  )
                : Text("Pick a package to see the amount", style: TextStyle(fontSize: 12, color: textMuted)),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => _showQrFullscreen(total),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 236),
              child: AspectRatio(
                aspectRatio: 1,
                child: CustomPaint(
                  foregroundPainter: const _ScanFramePainter(AppColors.accent),
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 5))],
                    ),
                    child: Image.asset(
                      StudioPaymentAccount.qrAsset,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.qr_code_2_rounded, size: 80, color: Colors.black26)),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.zoom_out_map_rounded, size: 12, color: textMuted),
              const SizedBox(width: 5),
              Text("Tap the QR to enlarge", style: TextStyle(fontSize: 10.5, color: textMuted)),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: AppPalette.divider(context)),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.account_circle_outlined, size: 20, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(StudioPaymentAccount.accountName, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: textPrimary)),
                    const SizedBox(height: 1),
                    Text(StudioPaymentAccount.formattedNumber, style: TextStyle(fontSize: 12.5, letterSpacing: 0.5, color: AppPalette.textSecondary(context))),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: StudioPaymentAccount.accountNumber));
                  TopToast.show(context, "Account number copied", kind: TopToastKind.info);
                },
                icon: const Icon(Icons.copy_rounded, size: 15),
                label: const Text("Copy", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: AppPalette.cardBg(context), borderRadius: BorderRadius.circular(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 15, color: textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Once the customer has paid, check that it shows up in the studio's account before you tap Confirm.",
                    style: TextStyle(fontSize: 11.5, height: 1.35, color: textMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showQrFullscreen(int total) {
    final maxQrHeight = MediaQuery.of(context).size.height * 0.5;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (total > 0) ...[
                  const Text("Amount to pay", style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 2),
                  Text(_peso(total), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppColors.accent)),
                  const SizedBox(height: 14),
                ],
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxQrHeight),
                  child: InteractiveViewer(
                    maxScale: 4,
                    child: Image.asset(StudioPaymentAccount.qrAsset, fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  StudioPaymentAccount.accountName,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black87),
                ),
                const SizedBox(height: 2),
                Text(StudioPaymentAccount.formattedNumber, style: const TextStyle(fontSize: 14, color: Colors.black54, letterSpacing: 0.6)),
                const SizedBox(height: 8),
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Close")),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar(BuildContext context, int total, Set<DateTime> locked) {
    final pkg = _selected;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Row(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 170),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pkg == null ? "Total" : "Total · ${pkg.name}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppPalette.textMuted(context)),
                      ),
                      Text(_peso(total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppColors.accent)),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: _submitting ? null : AppShadows.accentGlowSmall,
                    ),
                    child: ElevatedButton(
                      onPressed: _submitting ? null : () => _submit(locked),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.accentTint(0.5),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle_outline_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    "Confirm Booking & Payment",
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Four rounded "scanner" corner brackets drawn around the QR tile.
class _ScanFramePainter extends CustomPainter {
  final Color color;
  const _ScanFramePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    const l = 24.0; // arm length
    const r = 14.0; // corner radius
    final w = size.width;
    final h = size.height;
    final path = Path()
      // top-left
      ..moveTo(0, l)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..lineTo(l, 0)
      // top-right
      ..moveTo(w - l, 0)
      ..lineTo(w - r, 0)
      ..quadraticBezierTo(w, 0, w, r)
      ..lineTo(w, l)
      // bottom-right
      ..moveTo(w, h - l)
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h)
      ..lineTo(w - l, h)
      // bottom-left
      ..moveTo(l, h)
      ..lineTo(r, h)
      ..quadraticBezierTo(0, h, 0, h - r)
      ..lineTo(0, h - l);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ScanFramePainter old) => old.color != color;
}
