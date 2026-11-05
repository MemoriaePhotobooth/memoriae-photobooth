import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/camera_rental_record.dart';
import '../models/pricing_item_record.dart';
import '../services/auth_service.dart';
import '../services/camera_rental_repository.dart';
import '../services/pricing_repository.dart';
import '../services/rental_receipt_pdf.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/dashboard_kit.dart';

const Color _okColor = Color(0xFF2E7D32);
const Color _warnColor = Color(0xFFC62828);

/// A rental length staff can pick. Same options (and the same pro-rating
/// of the daily rate) the customer app shows on its Rent tab, so the
/// price a customer saw online is the price they pay at the counter.
class _RentalLength {
  final String label;
  final Duration value;
  const _RentalLength(this.label, this.value);

  int priceFor(int dailyRate) => (dailyRate * value.inMinutes / (24 * 60)).ceil();
}

const List<_RentalLength> _kLengths = [
  _RentalLength('6 hours', Duration(hours: 6)),
  _RentalLength('12 hours', Duration(hours: 12)),
  _RentalLength('1 day', Duration(hours: 24)),
  _RentalLength('2 days', Duration(hours: 48)),
  _RentalLength('3 days', Duration(hours: 72)),
];

/// The ID the customer leaves with the shop while they have the camera.
/// Only the TYPE is recorded — never the ID number.
const List<String> _kIdTypes = [
  "Driver's license",
  'UMID',
  'National ID',
  'Passport',
  'School ID',
  'Other',
];

/// How the co-maker is related to the customer. Optional, one tap.
const List<String> _kRelationships = [
  'Parent',
  'Sibling',
  'Spouse / Partner',
  'Relative',
  'Friend',
  'Other',
];

/// Staff flow for renting a camera to a walk-in customer: pick one of the
/// cameras that is free right now, pick how long, record who is taking it
/// and what they left behind, collect payment, and print the receipt.
///
/// Starting the rental locks the camera (so it shows as "Rented" in the
/// customer app immediately), records the rental, and rings up the fee in
/// the POS sales — all in one Firestore transaction, so it either all
/// happens or none of it does.
class StaffNewRentalScreen extends StatefulWidget {
  const StaffNewRentalScreen({super.key});

  @override
  State<StaffNewRentalScreen> createState() => _StaffNewRentalScreenState();
}

class _StaffNewRentalScreenState extends State<StaffNewRentalScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _coNameCtrl = TextEditingController();
  final _coPhoneCtrl = TextEditingController();
  final _depositCtrl = TextEditingController();
  final _conditionCtrl = TextEditingController();
  final _cashCtrl = TextEditingController();

  // Held in fields so rebuilding the form doesn't re-subscribe.
  late final Stream<List<PricingItemRecord>> _pricingStream = PricingRepository.watchAllPricing();
  late final Stream<List<CameraRentalRecord>> _rentalsStream = CameraRentalRepository.watchAllRentals();

  final Map<String, Uint8List?> _imageCache = {};

  String? _cameraId;
  int _lengthIndex = 2; // 1 day
  String? _idType;
  String? _coRel;
  String _payment = 'cash';

  String? _linkedUid;
  String? _linkedName;
  String? _lookupMessage;
  bool _lookupBusy = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _depositCtrl.addListener(_refresh);
    _cashCtrl.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _accountCtrl.dispose();
    _coNameCtrl.dispose();
    _coPhoneCtrl.dispose();
    _depositCtrl.dispose();
    _conditionCtrl.dispose();
    _cashCtrl.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  int get _deposit => int.tryParse(_depositCtrl.text.trim()) ?? 0;

  Uint8List? _decodeImage(String value) {
    return _imageCache.putIfAbsent(value, () {
      if (!value.startsWith('data:') || !value.contains(',')) return null;
      try {
        return base64Decode(value.split(',').last);
      } catch (_) {
        return null;
      }
    });
  }

  InputDecoration _deco(String label, {String? prefix, String? hint, IconData? icon}) {
    OutlineInputBorder b(Color c, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: AppPalette.textMuted(context), fontSize: 13),
      hintStyle: TextStyle(color: AppPalette.textMuted(context), fontSize: 13),
      prefixText: prefix,
      prefixIcon: icon == null ? null : Icon(icon, size: 18, color: AppPalette.textMuted(context)),
      filled: true,
      fillColor: AppPalette.surface(context),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      border: b(Colors.transparent),
      enabledBorder: b(Colors.transparent),
      focusedBorder: b(AppColors.accent, 1.4),
    );
  }

  /// Pill-style choice used for length, ID type, relationship and payment.
  Widget _choice(String label, bool selected, VoidCallback onTap, {IconData? icon}) {
    return ChoiceChip(
      avatar: icon == null ? null : Icon(icon, size: 16, color: selected ? AppColors.accent : AppPalette.textMuted(context)),
      label: Text(label),
      labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: selected ? AppColors.accent : AppPalette.textSecondary(context)),
      selected: selected,
      showCheckmark: false,
      backgroundColor: AppPalette.surface(context),
      selectedColor: AppColors.accentTint(0.10),
      side: BorderSide(color: selected ? AppColors.accent : Colors.transparent, width: 1.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      onSelected: (_) => onTap(),
    );
  }

  // -------------------------------------------------------------------------
  // Optional: link the rental to a customer's app account
  // -------------------------------------------------------------------------

  Future<void> _lookupAccount() async {
    final q = _accountCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _lookupBusy = true;
      _lookupMessage = null;
    });
    try {
      final isEmail = q.contains('@');
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where(isEmail ? 'email' : 'contactNumber', isEqualTo: isEmail ? q.toLowerCase() : q)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        if (mounted) setState(() => _lookupMessage = "No app account found. You can still rent using the name and number above.");
        return;
      }
      final doc = snap.docs.first;
      final blocked = await FirebaseFirestore.instance.collection('blockedUsers').doc(doc.id).get();
      if (blocked.exists) {
        if (mounted) setState(() => _lookupMessage = "This account is restricted. Check with the admin before renting.");
        return;
      }
      final data = doc.data();
      final fullName = ((data['fullName'] ?? '') as String).trim();
      final phone = ((data['contactNumber'] ?? '') as String).trim();
      if (!mounted) return;
      setState(() {
        _linkedUid = doc.id;
        _linkedName = fullName.isNotEmpty ? fullName : q;
        _lookupMessage = null;
        if (_nameCtrl.text.trim().isEmpty && fullName.isNotEmpty) _nameCtrl.text = fullName;
        if (_phoneCtrl.text.trim().isEmpty && phone.isNotEmpty) _phoneCtrl.text = phone;
      });
    } catch (_) {
      if (mounted) setState(() => _lookupMessage = "Couldn't look that up. Check the connection and try again.");
    } finally {
      if (mounted) setState(() => _lookupBusy = false);
    }
  }

  void _unlinkAccount() {
    setState(() {
      _linkedUid = null;
      _linkedName = null;
      _accountCtrl.clear();
    });
  }

  // -------------------------------------------------------------------------
  // Submit
  // -------------------------------------------------------------------------

  Future<void> _submit(PricingItemRecord? camera) async {
    if (_submitting) return;
    if (camera == null) {
      _toast('Pick a camera first.');
      return;
    }
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final phoneDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (name.isEmpty) {
      _toast("Enter the customer's name.");
      return;
    }
    if (phoneDigits.length < 10 || phoneDigits.length > 13) {
      _toast('Enter a valid contact number.');
      return;
    }
    if (_idType == null) {
      _toast('Select the ID the customer is leaving.');
      return;
    }
    final coName = _coNameCtrl.text.trim();
    final coPhone = _coPhoneCtrl.text.trim();
    final coDigits = coPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (coName.isEmpty) {
      _toast("Enter the co-maker's name.");
      return;
    }
    if (coDigits.length < 10 || coDigits.length > 13) {
      _toast("Enter a valid contact number for the co-maker.");
      return;
    }
    if (coDigits == phoneDigits) {
      _toast("The co-maker's number must be different from the customer's.");
      return;
    }

    final length = _kLengths[_lengthIndex];
    final fee = length.priceFor(camera.price);
    final deposit = _deposit;
    final toCollect = fee + deposit;

    int? received;
    if (_payment == 'cash') {
      received = int.tryParse(_cashCtrl.text.trim());
      if (received == null || received < toCollect) {
        _toast(received == null ? 'Enter the cash received.' : 'Cash received is less than ₱$toCollect.');
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      final rental = await CameraRentalRepository.createWalkInRental(
        cameraId: camera.id,
        cameraName: camera.name,
        dailyRate: camera.price,
        duration: length.value,
        durationLabel: length.label,
        rentalFee: fee,
        userId: _linkedUid ?? 'walk-in',
        customerName: name,
        customerPhone: phone,
        idType: _idType!,
        coMakerName: coName,
        coMakerPhone: coPhone,
        coMakerRelationship: _coRel ?? '',
        deposit: deposit,
        conditionNote: _conditionCtrl.text.trim(),
        paymentMethod: _payment,
        amountReceived: received,
        staffId: AuthService.instance.currentUid ?? '',
        staffEmail: AuthService.instance.currentEmail ?? '',
      );
      if (!mounted) return;
      await _showSuccess(rental);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _toast("Couldn't start the rental: ${e.toString().replaceFirst('Exception: ', '')}");
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showSuccess(CameraRentalRecord rental) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.check_circle_rounded, color: _okColor, size: 40),
        title: const Text('Rental started'),
        content: Text(
          '${rental.cameraName} → ${rental.customerName}\n'
          'Due back ${DateFormat('EEE, MMM d · h:mm a').format(rental.dueAt)}',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Done')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white),
            onPressed: () async {
              try {
                await RentalReceiptPdf.printReceipt(rental);
              } catch (_) {
                if (mounted) _toast("Couldn't open the receipt. You can print it later from the rental card.");
              }
            },
            icon: const Icon(Icons.print_rounded, size: 18),
            label: const Text('Print / save receipt'),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.surface(context),
      appBar: AppBar(
        title: const Text('New walk-in rental', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        backgroundColor: AppPalette.bg(context),
        foregroundColor: AppPalette.textPrimary(context),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: StreamBuilder<List<PricingItemRecord>>(
        stream: _pricingStream,
        builder: (context, pricingSnap) {
          return StreamBuilder<List<CameraRentalRecord>>(
            stream: _rentalsStream,
            builder: (context, rentalSnap) {
              if (pricingSnap.hasError || rentalSnap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text("Couldn't load the cameras. Check the connection and try again.", textAlign: TextAlign.center, style: TextStyle(color: AppPalette.textMuted(context))),
                  ),
                );
              }
              if (!pricingSnap.hasData || !rentalSnap.hasData) {
                return const Center(child: CircularProgressIndicator(color: AppColors.accent));
              }
              final cameras = pricingSnap.data!.where((p) => p.category == 'Camera Rental').toList()
                ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
              final out = <String, CameraRentalRecord>{
                for (final r in rentalSnap.data!)
                  if (!r.isReturned) r.cameraId: r,
              };
              final available = cameras.where((c) => !out.containsKey(c.id)).toList();
              final rentedOut = cameras.where((c) => out.containsKey(c.id)).toList();
              PricingItemRecord? selected;
              for (final c in available) {
                if (c.id == _cameraId) selected = c;
              }
              return _buildForm(context, available, rentedOut, out, selected);
            },
          );
        },
      ),
    );
  }

  /// Screens at least this wide get a two-column layout: the form on the
  /// left, and the deposit / payment / total panel pinned on the right.
  static const double _kWideBreakpoint = 900;

  Widget _buildForm(
    BuildContext context,
    List<PricingItemRecord> available,
    List<PricingItemRecord> rentedOut,
    Map<String, CameraRentalRecord> out,
    PricingItemRecord? selected,
  ) {
    final length = _kLengths[_lengthIndex];
    final fee = selected == null ? 0 : length.priceFor(selected.price);
    final deposit = _deposit;
    final toCollect = fee + deposit;
    final dueAt = DateTime.now().add(length.value);
    final received = int.tryParse(_cashCtrl.text.trim());
    final change = received == null ? null : received - toCollect;

    const hero = DashboardHeroBanner(
      watermarkIcon: Icons.camera_alt_rounded,
      pillLabel: 'WALK-IN RENTAL',
      title: 'Rent out a camera',
      subtitle: 'Pick a camera, record who is taking it, then collect payment.',
    );

    final cameraSection = _section(
      context,
      'Camera',
      step: 1,
      icon: Icons.camera_alt_rounded,
      subtitle: available.isEmpty ? null : 'Only cameras that are free right now are shown.',
      child: _cameraList(context, available, rentedOut, out, selected),
    );

    final lengthSection = _section(
      context,
      'How long',
      step: 2,
      icon: Icons.schedule_rounded,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < _kLengths.length; i++)
            _choice(
              selected == null ? _kLengths[i].label : '${_kLengths[i].label} · ₱${_kLengths[i].priceFor(selected.price)}',
              _lengthIndex == i,
              () => setState(() => _lengthIndex = i),
            ),
        ],
      ),
    );

    final customerSection = _section(context, 'Customer', step: 3, icon: Icons.person_rounded, child: _customerFields(context));
    final coMakerSection = _section(context, 'Co-maker', step: 4, icon: Icons.group_rounded, child: _coMakerFields(context));

    final depositSection = _section(
      context,
      'Deposit & condition',
      step: 5,
      icon: Icons.verified_user_rounded,
      child: Column(
        children: [
          TextField(
            controller: _depositCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _deco('Deposit (refundable)', prefix: '₱ ', hint: '0 = no deposit'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _conditionCtrl,
            maxLines: 3,
            minLines: 2,
            maxLength: 300,
            decoration: _deco('Condition & items handed over', hint: 'e.g. lens clean, 2 batteries, 32GB card, strap'),
          ),
        ],
      ),
    );

    final paymentSection = _section(
      context,
      'Payment',
      step: 6,
      icon: Icons.payments_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _choice('Cash', _payment == 'cash', () => setState(() => _payment = 'cash'), icon: Icons.payments_outlined),
              _choice('GCash', _payment == 'gcash', () => setState(() => _payment = 'gcash'), icon: Icons.phone_android_rounded),
            ],
          ),
          const SizedBox(height: 14),
          _summary(context, selected, length, fee, deposit, toCollect, dueAt),
          if (_payment == 'cash') ...[
            const SizedBox(height: 14),
            TextField(
              controller: _cashCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _deco('Cash received', prefix: '₱ '),
            ),
            if (change != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: (change >= 0 ? _okColor : _warnColor).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(change >= 0 ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded, size: 18, color: change >= 0 ? _okColor : _warnColor),
                    const SizedBox(width: 8),
                    Text(
                      change >= 0 ? 'Change: ₱$change' : 'Short by ₱${-change}',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: change >= 0 ? _okColor : _warnColor),
                    ),
                  ],
                ),
              ),
            ],
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Confirm the GCash payment of ₱$toCollect has arrived before starting the rental.', style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context))),
            ),
        ],
      ),
    );

    final submitButton = Container(
      height: 54,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: selected == null ? null : AppShadows.accentGlowSmall),
      child: ElevatedButton(
        onPressed: (_submitting || selected == null) ? null : () => _submit(selected),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: _submitting
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(
                selected == null ? 'Pick a camera to continue' : 'Start rental · ₱$toCollect',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _kWideBreakpoint;

        if (!wide) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  hero,
                  const SizedBox(height: 16),
                  cameraSection,
                  lengthSection,
                  customerSection,
                  coMakerSection,
                  depositSection,
                  paymentSection,
                  const SizedBox(height: 4),
                  submitButton,
                ],
              ),
            ),
          );
        }

        // Wide: form on the left, pinned checkout panel on the right. Each
        // side scrolls on its own, so the total and the Start button never
        // disappear while staff fill in the customer details.
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 12, 28),
                    children: [
                      hero,
                      const SizedBox(height: 16),
                      cameraSection,
                      lengthSection,
                      customerSection,
                      coMakerSection,
                    ],
                  ),
                ),
                SizedBox(
                  width: 440,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 16, 24, 28),
                    children: [
                      depositSection,
                      paymentSection,
                      const SizedBox(height: 4),
                      submitButton,
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Two fields side by side when there's room, stacked when there isn't.
  Widget _pair(Widget a, Widget b) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 480) {
          return Column(children: [a, const SizedBox(height: 12), b]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)],
        );
      },
    );
  }

  Widget _section(BuildContext context, String title, {required IconData icon, int? step, String? subtitle, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.soft,
        border: Border.all(color: AppPalette.divider(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.accentTint(0.10), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 18, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context)))),
              if (step != null)
                Text('STEP $step', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppPalette.textMuted(context))),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle, style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _cameraList(
    BuildContext context,
    List<PricingItemRecord> available,
    List<PricingItemRecord> rentedOut,
    Map<String, CameraRentalRecord> out,
    PricingItemRecord? selected,
  ) {
    if (available.isEmpty) {
      return Text(
        rentedOut.isEmpty ? 'No cameras are set up yet. Add them in Admin → Pricing.' : 'Every camera is rented out right now.',
        style: TextStyle(fontSize: 13, color: AppPalette.textSecondary(context)),
      );
    }
    final backFmt = DateFormat('MMM d, h:mm a');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            const gap = 10.0;
            final cols = box.maxWidth >= 560 ? 2 : 1;
            final tileWidth = (box.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final c in available) SizedBox(width: tileWidth, child: _cameraTile(context, c, c.id == selected?.id)),
              ],
            );
          },
        ),
        if (rentedOut.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Rented out: ${rentedOut.map((c) => '${c.name} (back ${backFmt.format(out[c.id]!.dueAt)})').join(', ')}',
            style: TextStyle(fontSize: 11.5, height: 1.4, color: AppPalette.textMuted(context)),
          ),
        ],
      ],
    );
  }

  Widget _cameraTile(BuildContext context, PricingItemRecord c, bool isSelected) {
    final bytes = _decodeImage(c.imageUrl);
    return InkWell(
      onTap: () => setState(() => _cameraId = c.id),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentTint(0.07) : AppPalette.surface(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? AppColors.accent : Colors.transparent, width: 1.5),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 54,
                height: 54,
                child: bytes != null
                    ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
                    : Container(color: AppColors.accentTint(0.12), child: const Icon(Icons.camera_alt_rounded, color: AppColors.accent)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
                  const SizedBox(height: 2),
                  Text(
                    c.features.isNotEmpty ? c.features.join(' · ') : 'Available now',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₱${c.price}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
                Text('/ day', style: TextStyle(fontSize: 10.5, color: AppPalette.textMuted(context))),
              ],
            ),
            const SizedBox(width: 8),
            Icon(isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: isSelected ? AppColors.accent : AppPalette.textMuted(context), size: 22),
          ],
        ),
      ),
    );
  }

  Widget _customerFields(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pair(
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: _deco('Full name', icon: Icons.person_outline_rounded),
          ),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
            decoration: _deco('Contact number', hint: '09XX XXX XXXX', icon: Icons.phone_outlined),
          ),
        ),
        const SizedBox(height: 16),
        Text('ID left with the shop', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppPalette.textSecondary(context))),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in _kIdTypes)
              _choice(t, _idType == t, () => setState(() => _idType = t)),
          ],
        ),
        const SizedBox(height: 4),
        Text('Only the type of ID is saved, never the ID number.', style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
        const SizedBox(height: 16),
        Text('Has an app account? (optional)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppPalette.textSecondary(context))),
        const SizedBox(height: 8),
        if (_linkedUid != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: _okColor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Icon(Icons.link_rounded, size: 18, color: _okColor),
                const SizedBox(width: 8),
                Expanded(child: Text('Linked to $_linkedName', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _okColor))),
                IconButton(onPressed: _unlinkAccount, icon: const Icon(Icons.close_rounded, size: 18), visualDensity: VisualDensity.compact, tooltip: 'Unlink'),
              ],
            ),
          )
        else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _accountCtrl,
                  keyboardType: TextInputType.emailAddress,
                  onSubmitted: (_) => _lookupAccount(),
                  decoration: _deco('Account email or phone', icon: Icons.alternate_email_rounded),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: _lookupBusy ? null : _lookupAccount,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.accent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _lookupBusy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                      : const Text('Find'),
                ),
              ),
            ],
          ),
          if (_lookupMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_lookupMessage!, style: TextStyle(fontSize: 11.5, color: AppPalette.textSecondary(context))),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Linking lets the customer see their countdown in the app.', style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
            ),
        ],
      ],
    );
  }

  Widget _coMakerFields(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.accentTint(0.06), borderRadius: BorderRadius.circular(14)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.shield_outlined, size: 18, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Only called if we can't reach the customer. Should be someone who knows them, with their own number.",
                  style: TextStyle(fontSize: 11.5, height: 1.4, color: AppPalette.textSecondary(context)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _pair(
          TextField(
            controller: _coNameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: _deco('Co-maker full name', icon: Icons.people_outline_rounded),
          ),
          TextField(
            controller: _coPhoneCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
            decoration: _deco('Co-maker contact number', hint: '09XX XXX XXXX', icon: Icons.phone_outlined),
          ),
        ),
        const SizedBox(height: 16),
        Text('Relationship to customer (optional)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppPalette.textSecondary(context))),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in _kRelationships)
              // Tap again to clear it, it's optional.
              _choice(t, _coRel == t, () => setState(() => _coRel = _coRel == t ? null : t)),
          ],
        ),
      ],
    );
  }

  Widget _summary(BuildContext context, PricingItemRecord? camera, _RentalLength length, int fee, int deposit, int toCollect, DateTime dueAt) {
    Widget line(String l, String v, {bool strong = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(child: Text(l, style: TextStyle(fontSize: strong ? 13.5 : 12.5, fontWeight: strong ? FontWeight.w800 : FontWeight.w500, color: strong ? AppPalette.textPrimary(context) : AppPalette.textSecondary(context)))),
              Text(v, style: TextStyle(fontSize: strong ? 15 : 12.5, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          line('Camera', camera?.name ?? '—'),
          line('Length', length.label),
          line('Due back', DateFormat('EEE, MMM d · h:mm a').format(dueAt)),
          Divider(height: 14, color: AppPalette.divider(context)),
          line('Rental fee', '₱$fee'),
          if (deposit > 0) line('Deposit (refundable)', '₱$deposit'),
          Container(
            margin: const EdgeInsets.only(top: 4, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(color: AppColors.accentTint(0.10), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Expanded(child: Text('Total to collect', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context)))),
                Text('₱$toCollect', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}