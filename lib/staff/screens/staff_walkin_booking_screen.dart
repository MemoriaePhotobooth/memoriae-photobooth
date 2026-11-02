import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/pricing_item_record.dart';
import '../../shared/text_draft.dart';
import '../services/auth_service.dart';
import '../services/staff_settings.dart';
import '../services/booking_repository.dart';
import '../services/pricing_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

String _peso(int amount) => '₱${NumberFormat('#,##0').format(amount)}';

/// One-stop walk-in flow: book a package for a customer standing right
/// in front of staff, and ring up their payment (Cash or GCash)
/// in the same step — see `BookingRepository.createWalkInBookingWithPayment`
/// for how this stays a single atomic write.
///
/// Redesigned as sectioned cards (Customer / Package / Schedule /
/// Payment) with a sticky total + confirm bar. Fixes vs. the old form:
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
    if (!_emailPattern.hasMatch(email) || email == _lastLookedUpEmail) return;
    _lastLookedUpEmail = email;
    setState(() => _lookingUp = true);
    try {
      final match = await BookingRepository.findCustomerByEmail(email).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() {
        _matchedUserId = match?['uid'] as String?;
        if (match != null) {
          if (_nameController.text.trim().isEmpty) _nameController.text = (match['fullName'] ?? '') as String;
          if (_contactController.text.trim().isEmpty) _contactController.text = (match['contactNumber'] ?? '') as String;
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
      selectableDayPredicate: (d) => !_isLocked(d, locked),
    );
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
    if (RegExp(r'^[\d\W]+$').hasMatch(s)) return "Enter a real name.";
    return null;
  }

  String? _vEmail(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return "Enter an email address.";
    if (!_emailPattern.hasMatch(s)) return "That email doesn't look right.";
    return null;
  }

  String? _vPhone(String? v) {
    final digits = (v ?? '').replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
    if (digits.isEmpty) return "Enter a contact number.";
    if (!RegExp(r'^\d+$').hasMatch(digits)) return "Numbers only, please.";
    if (digits.length < 10 || digits.length > 13) return "Enter a valid mobile number (e.g. 09171234567).";
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

  Widget _section(BuildContext context, {required IconData icon, required String title, required Widget child, Widget? trailing}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.soft,
        border: Border.all(color: AppPalette.divider(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.accentTint(0.10), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 16, color: AppColors.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context)),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _pickerField(BuildContext context, {required IconData icon, required String label, required String value, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: _decor(
          context,
          label: label,
          icon: icon,
          suffix: Icon(Icons.expand_more_rounded, size: 18, color: AppPalette.textMuted(context)),
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
                      child: _responsiveSections(context, [
                          _section(
                            context,
                            icon: Icons.person_outline,
                            title: "Customer",
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: _nameController,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  inputFormatters: [LengthLimitingTextInputFormatter(60)],
                                  decoration: _decor(context, label: "Full name", icon: Icons.badge_outlined),
                                  validator: _vName,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _emailController,
                                  focusNode: _emailFocus,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
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
                                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]')), LengthLimitingTextInputFormatter(20)],
                                  decoration: _decor(context, label: "Contact number", icon: Icons.phone_outlined, hint: "09XX XXX XXXX"),
                                  validator: _vPhone,
                                ),
                              ],
                            ),
                          ),
                          _section(
                            context,
                            icon: Icons.photo_camera_back_outlined,
                            title: "Package",
                            trailing: _packageError
                                ? const Text("Choose one", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.accent))
                                : null,
                            child: packages_empty(context)
                                ? Text("No booth packages yet — add them in Admin › Pricing.", style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context)))
                                : Column(children: [for (final p in _packages) _packageTile(context, p)]),
                          ),
                          _section(
                            context,
                            icon: Icons.event_outlined,
                            title: "Schedule",
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: _pickerField(context, icon: Icons.calendar_today_outlined, label: "Date", value: DateFormat('EEE, MMM d, yyyy').format(_date), onTap: () => _pickDate(locked)),
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
                                        Expanded(child: Text("This date is already booked — pick another.", style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)))),
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
                            icon: Icons.payments_outlined,
                            title: "Payment",
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: _paymentChip('cash', "Cash", Icons.payments_outlined)),
                                    const SizedBox(width: 10),
                                    Expanded(child: _paymentChip('gcash', "GCash", Icons.qr_code_2_rounded)),
                                  ],
                                ),
                                if (_paymentMethod == 'cash') ...[
                                  const SizedBox(height: 14),
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
                                  if (_cashReceived >= total && total > 0 && _cashReceivedController.text.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Text("Change: ${_peso(_cashReceived - total)}", style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppColors.accent)),
                                    ),
                                ] else
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Text("Confirm the GCash payment on the customer's phone before you tap Confirm.", style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
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
                      ]),
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

  Widget _packageTile(BuildContext context, PricingItemRecord p) {
    final selected = p.id == _selectedPackageId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() {
            _selectedPackageId = p.id;
            _packageError = false;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.accentTint(0.06) : AppPalette.surface(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.accent : AppPalette.divider(context),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.accent : AppColors.accentTint(0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    selected ? Icons.check_rounded : Icons.photo_camera_outlined,
                    size: 16,
                    color: selected ? Colors.white : AppColors.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context)),
                      ),
                      if (p.unit.isNotEmpty)
                        Text(p.unit, style: TextStyle(fontSize: 10.5, color: AppPalette.textMuted(context))),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _peso(p.price),
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Narrow windows (phones): one scrolling column of sections.
  /// Wide windows (desktop): two columns side by side,
  /// Customer + Package on the left, Schedule + Payment on the right.
  Widget _responsiveSections(BuildContext context, List<Widget> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
            children: items,
          );
        }
        final left = items.take(2).toList();
        final right = items.skip(2).toList();
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Row(
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
            ),
          ),
        );
      },
    );
  }

  Widget _quickCash(String label, int amount) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      backgroundColor: AppPalette.surface(context),
      side: BorderSide(color: AppPalette.divider(context)),
      onPressed: () => setState(() => _cashReceivedController.text = amount.toString()),
    );
  }

  Widget _paymentChip(String value, String label, IconData icon) {
    final selected = _paymentMethod == value;
    return GestureDetector(
      onTap: () => setState(() => _paymentMethod = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppPalette.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.accent : AppPalette.divider(context)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : AppPalette.textMuted(context)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppPalette.textPrimary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(BuildContext context, int total, Set<DateTime> locked) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, -3)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Total", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppPalette.textMuted(context))),
                Text(_peso(total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.accent)),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 46,
                child: ElevatedButton(
                  onPressed: _submitting ? null : () => _submit(locked),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.accentTint(0.5),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            "Confirm Booking & Payment",
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
