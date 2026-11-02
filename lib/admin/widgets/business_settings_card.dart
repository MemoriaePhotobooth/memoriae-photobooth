import '../../shared/top_toast.dart';
import 'package:flutter/material.dart';
import '../services/business_settings_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Settings card for the studio's business info (name, contact, address)
/// and the GCash account customers send payments to.
///
/// Saved to Firestore (`settings/business`) so it applies to every device,
/// and the customer app shows the GCash details at checkout.
class BusinessSettingsCard extends StatefulWidget {
  const BusinessSettingsCard({super.key});

  @override
  State<BusinessSettingsCard> createState() => _BusinessSettingsCardState();
}

class _BusinessSettingsCardState extends State<BusinessSettingsCard> {
  bool _loaded = false;
  bool _saving = false;
  final _studioName = TextEditingController();
  final _contactNumber = TextEditingController();
  final _contactEmail = TextEditingController();
  final _address = TextEditingController();
  final _gcashName = TextEditingController();
  final _gcashNumber = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await BusinessSettingsRepository.fetch();
    if (!mounted) return;
    setState(() {
      _studioName.text = b.studioName;
      _contactNumber.text = b.contactNumber;
      _contactEmail.text = b.contactEmail;
      _address.text = b.address;
      _gcashName.text = b.gcashName;
      _gcashNumber.text = b.gcashNumber;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _studioName.dispose();
    _contactNumber.dispose();
    _contactEmail.dispose();
    _address.dispose();
    _gcashName.dispose();
    _gcashNumber.dispose();
    super.dispose();
  }

  static final RegExp _phone = RegExp(r'^(09|\+639|639)\d{9}$');
  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  String? get _error {
    final gcash = _gcashNumber.text.trim();
    if (gcash.isNotEmpty && !_phone.hasMatch(gcash)) return 'GCash number must look like 09171234567.';
    final contact = _contactNumber.text.trim();
    if (contact.isNotEmpty && !_phone.hasMatch(contact)) return 'Contact number must look like 09171234567.';
    final email = _contactEmail.text.trim();
    if (email.isNotEmpty && !_email.hasMatch(email)) return 'Enter a valid contact email.';
    if (gcash.isNotEmpty && _gcashName.text.trim().isEmpty) return 'Add the name on the GCash account.';
    return null;
  }

  /// Fields the admin has typed in (or tried to save). Their message shows
  /// live and updates on every keystroke.
  final Set<TextEditingController> _touched = {};

  /// Per-field problem, or null. All fields are optional unless filled in.
  String? _fieldError(TextEditingController c) {
    final v = c.text.trim();
    if (identical(c, _contactNumber)) {
      if (v.isNotEmpty && !_phone.hasMatch(v)) return 'Must look like 09171234567.';
    } else if (identical(c, _gcashNumber)) {
      if (v.isNotEmpty && !_phone.hasMatch(v)) return 'Must look like 09171234567.';
    } else if (identical(c, _contactEmail)) {
      if (v.isNotEmpty && !_email.hasMatch(v)) return 'Enter a valid contact email.';
    } else if (identical(c, _gcashName)) {
      if (_gcashNumber.text.trim().isNotEmpty && v.isEmpty) return 'Add the name on the GCash account.';
    }
    return null;
  }

  Future<void> _save() async {
    final error = _error;
    if (error != null) {
      setState(() => _touched.addAll([_contactNumber, _contactEmail, _gcashName, _gcashNumber]));
      TopToast.show(null, error);
      return;
    }
    setState(() => _saving = true);
    try {
      await BusinessSettingsRepository.save(BusinessSettings(
        studioName: _studioName.text,
        contactNumber: _contactNumber.text,
        contactEmail: _contactEmail.text,
        address: _address.text,
        gcashName: _gcashName.text,
        gcashNumber: _gcashNumber.text,
      ));
      TopToast.show(null, 'Business details saved.');
    } catch (e) {
      TopToast.show(null, "Couldn't save: $e", kind: TopToastKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    TextInputType? keyboard,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        maxLines: maxLines,
        enabled: !_saving,
        onChanged: (_) => setState(() => _touched.add(c)),
        style: TextStyle(fontSize: 13.5, color: AppPalette.textPrimary(context)),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: (_touched.contains(c) || (identical(c, _gcashName) && _touched.contains(_gcashNumber))) ? _fieldError(c) : null,
          isDense: true,
          filled: true,
          fillColor: AppPalette.surface(context),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _heading(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading('Business info'),
          _field(_studioName, 'Studio name', hint: 'Memoriae Photobooth'),
          _field(_contactNumber, 'Contact number', hint: '09171234567', keyboard: TextInputType.phone),
          _field(_contactEmail, 'Contact email', hint: 'hello@example.com', keyboard: TextInputType.emailAddress),
          _field(_address, 'Address', maxLines: 2),
          const SizedBox(height: 4),
          _heading('GCash payment details'),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Customers see this at checkout so they know where to send their payment.',
              style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
            ),
          ),
          _field(_gcashName, 'Account name'),
          _field(_gcashNumber, 'GCash number', hint: '09171234567', keyboard: TextInputType.phone),
          const SizedBox(height: 4),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
