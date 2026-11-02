import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/booth_package.dart';
import '../services/auth_service.dart';
import '../services/booking_repository.dart';
import '../services/payment_info.dart';
import '../services/payment_settings_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/circle_back_button.dart';
import '../widgets/app_toast.dart';

/// Profile → Payment Methods.
///
/// Memoriae takes payment through GCash (send the amount, then upload the
/// receipt screenshot), so this screen does three useful things instead
/// of being a card vault:
///   1. explains how paying works (incl. the current downpayment rule),
///   2. lets a signed-in customer save the GCash account their refunds
///      should be sent to (staff see it on the pending refund), and
///   3. shows their payment history — paid vs. balance per booking.
class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  AppUser? _user;
  bool _loading = true;
  PaymentSettings _settings = PaymentSettings.defaults;

  final _name = TextEditingController();
  final _number = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _editing = false;
  bool _saving = false;

  bool get _hasAccount => (_user?.gcashNumber ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([AuthService.instance.me(), PaymentSettingsRepository.fetch()]);
      if (!mounted) return;
      setState(() {
        _user = results[0] as AppUser?;
        _settings = results[1] as PaymentSettings;
        _name.text = _user?.gcashName ?? _user?.fullName ?? '';
        _number.text = _user?.gcashNumber ?? '';
        _editing = !_hasAccount;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) => AppToast.show(context, msg);

  /// PH mobile numbers: 09XXXXXXXXX, or +639XXXXXXXXX / 639XXXXXXXXX.
  static String? _validateNumber(String? v) {
    final t = (v ?? '').replaceAll(RegExp(r'[\s-]'), '');
    if (t.isEmpty) return 'Enter your GCash number';
    if (!RegExp(r'^(09|\+639|639)\d{9}$').hasMatch(t)) return 'Use a valid number, e.g. 09171234567';
    return null;
  }

  static String _normalize(String raw) {
    var t = raw.replaceAll(RegExp(r'[\s-]'), '');
    if (t.startsWith('+63')) t = '0${t.substring(3)}';
    if (t.startsWith('63') && t.length == 12) t = '0${t.substring(2)}';
    return t;
  }

  static String _mask(String n) => n.length < 4 ? n : '${n.substring(0, 4)} ••• ${n.substring(n.length - 4)}';

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await AuthService.instance.saveRefundAccount(name: _name.text, number: _normalize(_number.text));
      final fresh = await AuthService.instance.me();
      if (!mounted) return;
      setState(() {
        _user = fresh;
        _editing = false;
      });
      _toast('Refund account saved');
    } catch (e) {
      if (mounted) _toast("Couldn't save. Please try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove GCash account?'),
        content: const Text("We won't have a number to send refunds to until you add one again."),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Remove', style: TextStyle(color: AppColors.accent))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await AuthService.instance.saveRefundAccount(name: '', number: '');
      final fresh = await AuthService.instance.me();
      if (!mounted) return;
      setState(() {
        _user = fresh;
        _name.text = fresh?.fullName ?? '';
        _number.clear();
        _editing = true;
      });
      _toast('Removed');
    } catch (_) {
      if (mounted) _toast("Couldn't remove. Please try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        leading: const CircleBackButton.appBar(),
        leadingWidth: CircleBackButton.appBarLeadingWidth,
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: Text('Payment Methods', style: TextStyle(color: AppPalette.textPrimary(context), fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _howToPay(context),
                  const SizedBox(height: 20),
                  _refundAccount(context),
                  const SizedBox(height: 20),
                  _history(context),
                ],
              ),
      ),
    );
  }

  // ---------------------------------------------------------------- how to pay

  Widget _howToPay(BuildContext context) {
    final split = _settings.downpaymentEnabled;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.brandCream, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('GCash', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
                    Text('Accepted payment method', style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _step(context, '1', 'Pick a package and date, then tap "Book Now & Hold Slot".'),
          _step(context, '2', split
              ? 'Send a ${_settings.label} downpayment to reserve it (the balance is paid on the event day), or pay in full.'
              : 'Send the full amount through GCash.'),
          _step(context, '3', 'Upload your GCash receipt screenshot before the ${BookingRepository.holdDuration.inMinutes}-minute hold ends.'),
          _step(context, '4', 'Staff review it and approve your booking. Your pass appears under Tickets.', last: true),
        ],
      ),
    );
  }

  Widget _step(BuildContext context, String n, String text, {bool last = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.accentTint(0.12), shape: BoxShape.circle),
            child: Text(n, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.accent)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, height: 1.45, color: AppPalette.textSecondary(context)))),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ refund account

  Widget _refundAccount(BuildContext context) {
    final loggedIn = AuthService.instance.isLoggedIn;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('REFUND ACCOUNT', style: _label(context)),
          const SizedBox(height: 6),
          Text(
            'If a booking is cancelled and you are due a refund, we send it to this GCash number.',
            style: TextStyle(fontSize: 12.5, height: 1.5, color: AppPalette.textSecondary(context)),
          ),
          const SizedBox(height: 14),
          if (!loggedIn)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.accentTint(0.06), borderRadius: BorderRadius.circular(14)),
              child: Text(
                'Log in to save a refund account. Guests can still get refunds — just message our staff your GCash number.',
                style: TextStyle(fontSize: 12.5, height: 1.5, color: AppPalette.textSecondary(context)),
              ),
            )
          else if (!_editing && _hasAccount)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle, size: 18, color: Color(0xFF2E7D32)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_user?.gcashName ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
                          Text(_mask(_user!.gcashNumber!), style: TextStyle(fontSize: 13, color: AppPalette.textSecondary(context))),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: _saving ? null : () => setState(() => _editing = true),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.accent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      child: const Text('Edit'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _saving ? null : _remove,
                      child: Text('Remove', style: TextStyle(color: AppPalette.textMuted(context))),
                    ),
                  ],
                ),
              ],
            )
          else
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: _dec(context, 'Name on GCash', Icons.person_outline),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the name on your GCash' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _number,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]'))],
                    decoration: _dec(context, 'GCash number (09XXXXXXXXX)', Icons.phone_iphone),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: _validateNumber,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _saving
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAccent))
                              : const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      if (_hasAccount) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => setState(() {
                                    _editing = false;
                                    _name.text = _user?.gcashName ?? '';
                                    _number.text = _user?.gcashNumber ?? '';
                                  }),
                          child: Text('Cancel', style: TextStyle(color: AppPalette.textMuted(context))),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- history

  Widget _history(BuildContext context) {
    final uid = _user?.uid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text('PAYMENT HISTORY', style: _label(context)),
        ),
        if (uid == null)
          _card(context, child: Text('No payments yet.', style: TextStyle(fontSize: 13, color: AppPalette.textSecondary(context))))
        else
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: BookingRepository.watchBookingsForUser(uid),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
                );
              }
              // Only bookings where a receipt has actually been sent.
              final rows = snap.data!.where((b) {
                final s = b['status'] as String? ?? '';
                return s == 'pending_confirmation' || s == 'confirmed' || s == 'completed';
              }).toList();
              if (rows.isEmpty) {
                return _card(
                  context,
                  child: Text('No payments yet. Once you send a receipt, it will be listed here.',
                      style: TextStyle(fontSize: 13, height: 1.5, color: AppPalette.textSecondary(context))),
                );
              }
              return _card(
                context,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) _historyRow(context, rows[i], last: i == rows.length - 1),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _historyRow(BuildContext context, Map<String, dynamic> b, {required bool last}) {
    final pay = PaymentInfo.fromBooking(b);
    final ts = b['date'];
    final date = ts is Timestamp ? DateFormat('MMM d, yyyy').format(ts.toDate()) : '';
    final status = b['status'] as String? ?? '';
    final inv = (b['invoiceNo'] as String? ?? '').trim();
    final refunded = b['refundStatus'] == 'refunded';

    final String tag;
    final Color tagColor;
    if (refunded) {
      tag = 'Refunded';
      tagColor = AppColors.stone500;
    } else if (status == 'pending_confirmation') {
      tag = 'Under review';
      tagColor = const Color(0xFFE08A00);
    } else if (pay.hasBalance) {
      tag = 'Balance ${formatPeso(pay.balance)}';
      tagColor = const Color(0xFFE08A00);
    } else {
      tag = 'Paid in full';
      tagColor = const Color(0xFF2E7D32);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: AppPalette.divider(context)))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b['packageName'] as String? ?? 'Booking',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
                const SizedBox(height: 2),
                Text([if (inv.isNotEmpty) inv, if (date.isNotEmpty) date].join(' · '),
                    style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatPeso(pay.paid), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
              const SizedBox(height: 2),
              Text(tag, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tagColor)),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- helpers

  Widget _card(BuildContext context, {required Widget child, EdgeInsets padding = const EdgeInsets.all(18)}) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(20)),
      child: child,
    );
  }

  TextStyle _label(BuildContext context) =>
      TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: AppPalette.textMuted(context));

  InputDecoration _dec(BuildContext context, String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 18, color: AppColors.accent),
      filled: true,
      fillColor: AppPalette.cardBg(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppPalette.divider(context))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppPalette.divider(context))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.accent)),
    );
  }
}
