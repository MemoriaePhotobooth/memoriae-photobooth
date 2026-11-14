import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

const Color _kDanger = Color(0xFFDC2626);
const Color _kDangerTint = Color(0xFFFDECEC);
const Color _kSuccess = Color(0xFF16A34A);
const Color _kSuccessTint = Color(0xFFE9F8EF);

/// Staff screen to link a loyalty card to a customer.
///
/// Flow:
///  1. Staff types the customer's email and taps "Find customer".
///  2. Staff taps "Link card". This writes one `loyaltyLinkRequests/{staffUid}`
///     document with the customer's UID and a server timestamp.
///  3. Staff taps the card on the studio reader within 2 minutes.
///     The Cloudflare Worker links the card and deletes the request.
///  4. This screen sees the request disappear and shows "Card linked".
class StaffLoyaltyLinkScreen extends StatefulWidget {
  const StaffLoyaltyLinkScreen({super.key});

  @override
  State<StaffLoyaltyLinkScreen> createState() => _StaffLoyaltyLinkScreenState();
}

class _StaffLoyaltyLinkScreenState extends State<StaffLoyaltyLinkScreen> {
  static const Duration _linkWindow = Duration(minutes: 2);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _emailCtrl = TextEditingController();

  bool _searching = false;
  bool _waiting = false;
  String? _error;
  String? _statusMessage;
  bool _statusIsSuccess = false;
  QueryDocumentSnapshot<Map<String, dynamic>>? _customer;
  DateTime? _expiresAt;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  Timer? _ticker;

  String? get _staffUid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>>? get _requestRef {
    final uid = _staffUid;
    if (uid == null) return null;
    return _db.collection('loyaltyLinkRequests').doc(uid);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _findCustomer() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty) {
      setState(() => _error = 'Enter the customer email first.');
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
      _statusMessage = null;
      _customer = null;
    });

    try {
      final snap = await _db
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (!mounted) return;
      if (snap.docs.isEmpty) {
        setState(() => _error = 'No customer found with that email.');
      } else {
        setState(() => _customer = snap.docs.first);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not search customers. Try again.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _startLink() async {
    final ref = _requestRef;
    final customer = _customer;
    if (ref == null || customer == null) return;

    final expires = DateTime.now().add(_linkWindow);
    setState(() {
      _error = null;
      _statusMessage = null;
    });

    try {
      await ref.set({
        'userId': customer.id,
        // Server time, so a phone or PC with a wrong clock can't break the window.
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expires),
      });
      if (!mounted) return;
      setState(() {
        _waiting = true;
        _expiresAt = expires;
      });
      _watchRequest(ref);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_expiresAt != null && DateTime.now().isAfter(_expiresAt!)) {
          _cancelRequest(message: 'Request expired. Try again.');
        } else {
          setState(() {});
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not start the link. Try again.');
    }
  }

  void _watchRequest(DocumentReference<Map<String, dynamic>> ref) {
    _sub?.cancel();
    _sub = ref.snapshots().listen((snap) {
      // The Worker deletes the request once the card is linked.
      if (!snap.exists && _waiting) {
        final name = (_customer?.data()['name'] as String?) ?? 'customer';
        _finish('Card linked to $name.');
      }
    });
  }

  void _finish(String message) {
    _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
    _ticker = null;
    if (!mounted) return;
    setState(() {
      _waiting = false;
      _expiresAt = null;
      _customer = null;
      _statusMessage = message;
      _statusIsSuccess = true;
    });
    _emailCtrl.clear();
  }

  Future<void> _cancelRequest({String? message}) async {
    _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
    _ticker = null;
    if (mounted) {
      setState(() {
        _waiting = false;
        _expiresAt = null;
        _statusMessage = message;
        _statusIsSuccess = false;
      });
    }
    try {
      await _requestRef?.delete();
    } catch (_) {
      // Already gone or expired on the server. Nothing else to do.
    }
  }

  String _timeLeft() {
    if (_expiresAt == null) return '';
    final left = _expiresAt!.difference(DateTime.now());
    final secs = left.inSeconds < 0 ? 0 : left.inSeconds;
    final mm = (secs ~/ 60).toString().padLeft(2, '0');
    final ss = (secs % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  /// 1.0 at the start of the window, sliding down to 0.0 when it expires.
  double _timeFraction() {
    if (_expiresAt == null) return 0;
    final f = _expiresAt!.difference(DateTime.now()).inMilliseconds /
        _linkWindow.inMilliseconds;
    if (f < 0) return 0;
    if (f > 1) return 1;
    return f;
  }

  static String _initials(String name, String email) {
    final source = name.trim().isNotEmpty ? name.trim() : email.trim();
    if (source.isEmpty) return '?';
    final parts = source.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.divider(context)),
        boxShadow: AppShadows.soft,
      );

  @override
  Widget build(BuildContext context) {
    final customer = _customer;
    final name = (customer?.data()['name'] as String?) ?? '';
    final email = (customer?.data()['email'] as String?) ?? '';

    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(title: const Text('Link loyalty card')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildIntro(),
          const SizedBox(height: 24),
          const _SectionLabel(step: '1', text: 'Find customer'),
          const SizedBox(height: 10),
          _buildSearchField(context),
          const SizedBox(height: 12),
          _buildFindButton(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _buildErrorBanner(_error!),
          ],
          if (customer != null && !_waiting) ...[
            const SizedBox(height: 24),
            const _SectionLabel(step: '2', text: 'Confirm and link'),
            const SizedBox(height: 10),
            _buildCustomerCard(context, name, email),
          ],
          if (_waiting) ...[
            const SizedBox(height: 24),
            const _SectionLabel(step: '2', text: 'Tap the card'),
            const SizedBox(height: 10),
            _buildWaitingCard(context, name),
          ],
          if (_statusMessage != null && !_waiting) ...[
            const SizedBox(height: 24),
            _buildStatusCard(context, _statusMessage!, _statusIsSuccess),
          ],
        ],
      ),
    );
  }

  Widget _buildIntro() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.accentGlow,
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.card_membership_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Loyalty card linking',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Find the customer by email, then have them tap their card on the reader.',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color, width: width),
        );

    return TextField(
      controller: _emailCtrl,
      enabled: !_waiting,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _findCustomer(),
      style: TextStyle(color: AppPalette.textPrimary(context)),
      decoration: InputDecoration(
        labelText: 'Customer email',
        hintText: 'name@example.com',
        prefixIcon: const Icon(Icons.mail_outline_rounded),
        filled: true,
        fillColor: AppPalette.cardBg(context),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: border(AppPalette.divider(context)),
        enabledBorder: border(AppPalette.divider(context)),
        disabledBorder: border(AppPalette.divider(context)),
        focusedBorder: border(AppColors.accent, 1.5),
      ),
    );
  }

  Widget _buildFindButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        onPressed: (_searching || _waiting) ? null : _findCustomer,
        icon: _searching
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.search_rounded),
        label: Text(_searching ? 'Searching...' : 'Find customer'),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _kDangerTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: _kDanger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: _kDanger, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerCard(BuildContext context, String name, String email) {
    final displayName = name.isEmpty ? 'Customer' : name;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accentTint(0.1),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _initials(name, email),
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppPalette.textPrimary(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      email,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppPalette.textSecondary(context), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              onPressed: _startLink,
              icon: const Icon(Icons.link_rounded),
              label: const Text('Link card'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingCard(BuildContext context, String name) {
    final fraction = _timeFraction();
    final timeLeft = _timeLeft();
    final muted = AppPalette.textSecondary(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(context),
      child: Column(
        children: [
          SizedBox(
            width: 132,
            height: 132,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 132,
                  height: 132,
                  child: CircularProgressIndicator(
                    value: fraction,
                    strokeWidth: 6,
                    strokeCap: StrokeCap.round,
                    color: AppColors.accent,
                    backgroundColor: AppPalette.divider(context),
                  ),
                ),
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: AppColors.accentTint(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.contactless_rounded, color: AppColors.accent, size: 40),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Tap the card on the reader',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppPalette.textPrimary(context),
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name.isEmpty ? 'Linking customer' : 'Linking $name',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 14),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.accentTint(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Time left $timeLeft',
              style: const TextStyle(
                color: AppColors.accent,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              color: AppColors.accent,
              backgroundColor: AppPalette.divider(context),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: BorderSide(color: AppColors.accent.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => _cancelRequest(message: 'Cancelled.'),
              icon: const Icon(Icons.close_rounded),
              label: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context, String message, bool success) {
    final bg = success ? _kSuccessTint : AppPalette.surface(context);
    final fg = success ? _kSuccess : AppPalette.textSecondary(context);
    final icon = success ? Icons.check_circle_rounded : Icons.info_outline_rounded;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: success ? const Color(0xFF14532D) : AppPalette.textPrimary(context),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String step;
  final String text;

  const _SectionLabel({required this.step, required this.text});

  @override
  Widget build(BuildContext context) {  
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.accent,
            shape: BoxShape.circle,
          ),
          child: Text(
            step,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text.toUpperCase(),
          style: TextStyle(
            color: AppPalette.textMuted(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }
}
