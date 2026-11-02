import '../../shared/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/payment_settings_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Settings card where Admin decides how much a customer must pay up-front
/// to reserve a booking. Customers can always choose to pay in full
/// instead — this only sets the *minimum* (the downpayment).
///
/// Saved to Firestore (`settings/payment`) so it applies to every device
/// and to the customer app, unlike the local-only toggles in
/// `AdminSettings`.
class DownpaymentSettingsCard extends StatefulWidget {
  const DownpaymentSettingsCard({super.key});

  @override
  State<DownpaymentSettingsCard> createState() => _DownpaymentSettingsCardState();
}

class _DownpaymentSettingsCardState extends State<DownpaymentSettingsCard> {
  bool _loaded = false;
  bool _saving = false;
  bool _enabled = true;
  bool _isPercent = true;
  final _valueCtrl = TextEditingController(text: '30');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await PaymentSettingsRepository.fetch();
    if (!mounted) return;
    setState(() {
      _enabled = s.downpaymentEnabled;
      _isPercent = s.isPercent;
      _valueCtrl.text = '${s.value}';
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    super.dispose();
  }

  int? get _value => int.tryParse(_valueCtrl.text.trim());

  String? get _error {
    final v = _value;
    if (!_enabled) return null;
    if (v == null || v < 1) return 'Enter a number greater than 0.';
    if (_isPercent && v > 99) return 'Percentage must be between 1 and 99.';
    return null;
  }

  String _peso(int n) => '₱${n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';

  Future<void> _save() async {
    if (_error != null) return;
    setState(() => _saving = true);
    try {
      await PaymentSettingsRepository.save(PaymentSettings(
        downpaymentEnabled: _enabled,
        isPercent: _isPercent,
        value: _value ?? 30,
      ));
      if (!mounted) return;
      TopToast.show(context, 'Payment settings saved.');
    } catch (e) {
      if (!mounted) return;
      TopToast.show(context, "Couldn't save: $e", kind: TopToastKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    final preview = PaymentSettings(downpaymentEnabled: _enabled, isPercent: _isPercent, value: _value ?? 1);
    const sample = 5000;
    final down = preview.downpaymentFor(sample);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.savings_outlined, size: 18, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Allow downpayment',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context))),
                    const SizedBox(height: 2),
                    Text('Customers can reserve with a partial payment, or still pay in full.',
                        style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _enabled,
                activeColor: AppColors.accent,
                onChanged: (v) => setState(() => _enabled = v),
              ),
            ],
          ),
          if (_enabled) ...[
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Percentage')),
                ButtonSegment(value: false, label: Text('Fixed amount')),
              ],
              selected: {_isPercent},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _isPercent = v.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _valueCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _isPercent ? 'Downpayment (% of total)' : 'Downpayment (₱ per booking)',
                suffixText: _isPercent ? '%' : null,
                prefixText: _isPercent ? null : '₱ ',
                errorText: _error,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            if (_error == null)
              Text(
                'Example: on a ${_peso(sample)} booking the customer pays ${_peso(down)} now '
                'and ${_peso(sample - down)} on the event day.',
                style: TextStyle(fontSize: 11.5, height: 1.4, color: AppPalette.textMuted(context)),
              ),
          ] else ...[
            const SizedBox(height: 8),
            Text('Off — every booking must be paid in full to reserve the date.',
                style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_saving || _error != null) ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save payment settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}
