import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

const Color _kMaroon = Color(0xFF6E1B1E);
const Color _kMaroonDark = Color(0xFF4A1013);
const Color _kBorder = Color(0xFFEDE6E4);
const Color _kBg = Color(0xFFFAF6F5);
const Color _kInk = Color(0xFF1F1A1A);
const Color _kMuted = Color(0xFF7A6F6E);
const Color _kGreen = Color(0xFF0F6E56);
const Color _kGreenSoft = Color(0xFFE1F5EE);
const Color _kRed = Color(0xFFA32D2D);
const Color _kRedSoft = Color(0xFFFBEAEA);

/// Staff screen to link a loyalty card to a customer.
///
/// 1. Staff finds the customer by email.
/// 2. Staff taps "Link card", which writes loyaltyLinkRequests/{staffUid}.
/// 3. The customer taps the card on the reader within 2 minutes. The Worker
///    writes the result (linked, card_in_use, or no_customer) into that request.
/// 4. This screen shows the result (with the customer's details when linked)
///    and removes the request.
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
  bool _statusIsError = false;
  QueryDocumentSnapshot<Map<String, dynamic>>? _customer;

  /// Snapshot of the customer that was just linked, shown on the success card.
  Map<String, dynamic>? _linkedCustomer;
  DateTime? _linkedAt;

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
      _linkedCustomer = null;
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
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expires),
      });
      if (!mounted) return;
      setState(() {
        _waiting = true;
        _expiresAt = expires;
      });
      _watchRequest(ref);
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_expiresAt != null && DateTime.now().isAfter(_expiresAt!)) {
          _cancelRequest(message: 'Request expired. Try again.', isError: true);
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
      if (!_waiting) return;
      final status = snap.data()?['status'] as String?;
      if (status == 'linked') {
        _finish('Card linked to ${_customerName()}.', isError: false, linked: true);
      } else if (status == 'card_in_use') {
        _finish('This card is already linked to another customer.', isError: true);
      } else if (status == 'no_customer') {
        _finish('Customer account not found. Try again.', isError: true);
      } else if (!snap.exists) {
        // Request removed without a result (for example, cancelled elsewhere).
        _finish('Request closed.', isError: true);
      }
    });
  }

  String _customerName() {
    final name = (_customer?.data()['fullName'] as String?)?.trim() ?? '';
    return name.isEmpty ? 'customer' : name;
  }

  Future<void> _finish(
    String message, {
    required bool isError,
    bool linked = false,
  }) async {
    _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
    _ticker = null;
    // Keep a copy of the customer details before clearing, so the success card
    // can show who the card was just linked to.
    final linkedData = linked ? <String, dynamic>{...?_customer?.data()} : null;
    try {
      await _requestRef?.delete();
    } catch (_) {
      // Already gone. Nothing else to do.
    }
    if (!mounted) return;
    setState(() {
      _waiting = false;
      _expiresAt = null;
      _customer = null;
      _linkedCustomer = linkedData;
      _linkedAt = linked ? DateTime.now() : null;
      _statusMessage = message;
      _statusIsError = isError;
    });
    _emailCtrl.clear();
  }

  Future<void> _cancelRequest({String? message, bool isError = false}) async {
    _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
    _ticker = null;
    if (mounted) {
      setState(() {
        _waiting = false;
        _expiresAt = null;
        _statusMessage = message ?? 'Cancelled.';
        _statusIsError = isError;
      });
    }
    try {
      await _requestRef?.delete();
    } catch (_) {
      // Already gone or expired on the server.
    }
  }

  void _linkAnother() {
    setState(() {
      _linkedCustomer = null;
      _linkedAt = null;
      _statusMessage = null;
      _error = null;
      _customer = null;
    });
  }

  String _timeLeft() {
    if (_expiresAt == null) return '';
    final left = _expiresAt!.difference(DateTime.now());
    final secs = left.inSeconds < 0 ? 0 : left.inSeconds;
    final mm = (secs ~/ 60).toString();
    final ss = (secs % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  double _timeFraction() {
    if (_expiresAt == null) return 0;
    final left = _expiresAt!.difference(DateTime.now()).inMilliseconds;
    return (left / _linkWindow.inMilliseconds).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final customer = _customer;
    final name = ((customer?.data()['fullName'] ?? '') as String).trim();
    final email = ((customer?.data()['email'] ?? '') as String).trim();
    final showSuccess = _linkedCustomer != null && !_waiting;
    final showStatusBanner = _statusMessage != null && !_waiting && !showSuccess;

    final int stage = showSuccess ? 3 : ((_waiting || customer != null) ? 1 : 0);

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _kInk,
        title: const Text(
          'Link loyalty card',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                _StepIndicator(stage: stage, waiting: _waiting),
                const SizedBox(height: 20),
                if (!showSuccess) ...[
                  _SearchCard(
                    controller: _emailCtrl,
                    enabled: !_waiting,
                    searching: _searching,
                    onSubmit: _findCustomer,
                    canSearch: !(_searching || _waiting),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _Banner(message: _error!, isError: true),
                ],
                _AnimatedSwap(
                  child: customer != null && !_waiting
                      ? Padding(
                          key: const ValueKey('customer'),
                          padding: const EdgeInsets.only(top: 16),
                          child: _CustomerCard(
                            name: name.isEmpty ? 'Customer' : name,
                            email: email,
                            onLink: _startLink,
                          ),
                        )
                      : _waiting
                          ? Padding(
                              key: const ValueKey('waiting'),
                              padding: const EdgeInsets.only(top: 16),
                              child: _WaitingCard(
                                customerName: _customerName(),
                                timeLeft: _timeLeft(),
                                fraction: _timeFraction(),
                                onCancel: () => _cancelRequest(),
                              ),
                            )
                          : showSuccess
                              ? Padding(
                                  key: const ValueKey('success'),
                                  padding: const EdgeInsets.only(top: 4),
                                  child: _SuccessCard(
                                    data: _linkedCustomer!,
                                    linkedAt: _linkedAt,
                                    onLinkAnother: _linkAnother,
                                  ),
                                )
                              : const SizedBox.shrink(key: ValueKey('none')),
                ),
                if (showStatusBanner) ...[
                  const SizedBox(height: 16),
                  _Banner(message: _statusMessage!, isError: _statusIsError),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

String _formatTime(DateTime t) {
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final mm = t.minute.toString().padLeft(2, '0');
  final ap = t.hour >= 12 ? 'PM' : 'AM';
  return '$h12:$mm $ap';
}

String? _firstString(Map<String, dynamic> data, List<String> keys) {
  for (final k in keys) {
    final v = data[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return null;
}

BoxDecoration _cardDecoration() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _kBorder),
      boxShadow: const [
        BoxShadow(color: Color(0x0F6E1B1E), blurRadius: 24, offset: Offset(0, 8)),
      ],
    );

class _AnimatedSwap extends StatelessWidget {
  const _AnimatedSwap({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (c, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(anim),
          child: c,
        ),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Step indicator
// ---------------------------------------------------------------------------

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.stage, required this.waiting});

  /// Number of finished steps (0..3).
  final int stage;
  final bool waiting;

  static const _labels = ['Find customer', 'Tap card', 'Linked'];

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < _labels.length; i++) {
      final done = i < stage || stage == 3;
      final active = !done && i == stage;
      children.add(_StepDot(index: i + 1, label: _labels[i], done: done, active: active));
      if (i < _labels.length - 1) {
        children.add(
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: i < stage || stage == 3 ? _kMaroon : _kBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        );
      }
    }
    // When waiting, the "Tap card" step is the active one.
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.index,
    required this.label,
    required this.done,
    required this.active,
  });

  final int index;
  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final filled = done || active;
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? _kMaroon : Colors.white,
              border: Border.all(color: filled ? _kMaroon : _kBorder, width: 1.5),
            ),
            alignment: Alignment.center,
            child: done
                ? const Icon(Icons.check_rounded, size: 17, color: Colors.white)
                : Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: active ? _kMaroon : _kMuted,
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: filled ? FontWeight.w600 : FontWeight.w500,
              color: filled ? _kInk : _kMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.controller,
    required this.enabled,
    required this.searching,
    required this.canSearch,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool searching;
  final bool canSearch;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Who is the card for?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _kInk),
          ),
          const SizedBox(height: 2),
          const Text(
            'Search the customer by the email on their account.',
            style: TextStyle(fontSize: 12.5, color: _kMuted),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.search,
            enabled: enabled,
            onSubmitted: (_) => onSubmit(),
            style: const TextStyle(fontSize: 15, color: _kInk),
            decoration: InputDecoration(
              labelText: 'Customer email',
              hintText: 'name@example.com',
              floatingLabelBehavior: FloatingLabelBehavior.never,
              prefixIcon: const Icon(Icons.alternate_email_rounded, size: 20, color: _kMuted),
              filled: true,
              fillColor: _kBg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _kMaroon, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _PrimaryButton(
            onPressed: canSearch ? onSubmit : null,
            icon: Icons.search_rounded,
            label: searching ? 'Searching...' : 'Find customer',
            loading: searching,
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.loading = false,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: _kMaroon,
          disabledBackgroundColor: _kMaroon.withAlpha(110),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
              )
            else
              Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Customer found
// ---------------------------------------------------------------------------

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.size = 52});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kMaroon, _kMaroonDark],
        ),
      ),
      child: Text(
        _initials(name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.name, required this.email, required this.onLink});

  final String name;
  final String email;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(name: name),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _kInk),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: _kMuted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _kGreenSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Found',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _kGreen),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PrimaryButton(onPressed: onLink, icon: Icons.link_rounded, label: 'Link card'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Waiting for the tap
// ---------------------------------------------------------------------------

class _WaitingCard extends StatelessWidget {
  const _WaitingCard({
    required this.customerName,
    required this.timeLeft,
    required this.fraction,
    required this.onCancel,
  });

  final String customerName;
  final String timeLeft;
  final double fraction;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          _TapCardAnimation(fraction: fraction),
          const SizedBox(height: 22),
          const Text(
            'Tap the card on the reader',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _kInk),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 13.5, color: _kMuted),
              children: [
                const TextSpan(text: 'Linking to '),
                TextSpan(
                  text: customerName,
                  style: const TextStyle(fontWeight: FontWeight.w600, color: _kInk),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: _kMaroon.withAlpha(18),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_outlined, size: 16, color: _kMaroon),
                const SizedBox(width: 6),
                Text(
                  'Time left  $timeLeft',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _kMaroon,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: _kMaroon,
                side: const BorderSide(color: _kBorder, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              onPressed: onCancel,
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pulsing contactless animation with a countdown ring around it.
class _TapCardAnimation extends StatefulWidget {
  const _TapCardAnimation({required this.fraction});
  final double fraction;

  @override
  State<_TapCardAnimation> createState() => _TapCardAnimationState();
}

class _TapCardAnimationState extends State<_TapCardAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double box = 190;
    return SizedBox(
      width: box,
      height: box,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Expanding ripples.
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) => CustomPaint(
              size: const Size(box, box),
              painter: _RipplePainter(progress: _ctrl.value),
            ),
          ),
          // Countdown ring.
          SizedBox(
            width: 128,
            height: 128,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: widget.fraction, end: widget.fraction),
              duration: const Duration(milliseconds: 900),
              builder: (context, value, _) => CircularProgressIndicator(
                value: value,
                strokeWidth: 5,
                backgroundColor: _kMaroon.withAlpha(25),
                color: _kMaroon,
              ),
            ),
          ),
          // Core with a gently breathing card + contactless icon.
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, child) {
              final t = math.sin(_ctrl.value * 2 * math.pi);
              return Transform.scale(scale: 1 + 0.035 * t, child: child);
            },
            child: Container(
              width: 104,
              height: 104,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_kMaroon, _kMaroonDark],
                ),
                boxShadow: [
                  BoxShadow(color: Color(0x556E1B1E), blurRadius: 24, offset: Offset(0, 10)),
                ],
              ),
              child: const Icon(Icons.contactless_rounded, size: 52, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  _RipplePainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const minR = 56.0;
    final maxR = size.width / 2;
    for (var i = 0; i < 3; i++) {
      final p = (progress + i / 3) % 1.0;
      final radius = minR + (maxR - minR) * p;
      final alpha = ((1 - p) * 70).round().clamp(0, 255);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _kMaroon.withAlpha(alpha);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter old) => old.progress != progress;
}

// ---------------------------------------------------------------------------
// Linked: success + customer details
// ---------------------------------------------------------------------------

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({
    required this.data,
    required this.linkedAt,
    required this.onLinkAnother,
  });

  final Map<String, dynamic> data;
  final DateTime? linkedAt;
  final VoidCallback onLinkAnother;

  @override
  Widget build(BuildContext context) {
    final name = _firstString(data, ['fullName', 'name', 'displayName']) ?? 'Customer';
    final email = _firstString(data, ['email']);
    final phone = _firstString(data, ['phone', 'phoneNumber', 'mobile']);

    final rows = <_DetailRow>[
      _DetailRow(icon: Icons.person_outline_rounded, label: 'Name', value: name),
      if (email != null)
        _DetailRow(icon: Icons.alternate_email_rounded, label: 'Email', value: email),
      if (phone != null)
        _DetailRow(icon: Icons.phone_outlined, label: 'Phone', value: phone),
      if (linkedAt != null)
        _DetailRow(
          icon: Icons.schedule_rounded,
          label: 'Linked at',
          value: _formatTime(linkedAt!),
        ),
    ];

    return Container(
      decoration: _cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header band.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_kMaroon, _kMaroonDark],
              ),
            ),
            child: Column(
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.elasticOut,
                  builder: (context, v, child) =>
                      Transform.scale(scale: v.clamp(0.0, 1.2), child: child),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded, size: 38, color: _kGreen),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Card linked!',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'The loyalty card is now connected to this customer.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(210)),
                ),
              ],
            ),
          ),
          // Customer details.
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Avatar(name: name, size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _kInk,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _kGreenSoft,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified_rounded, size: 14, color: _kGreen),
                                SizedBox(width: 4),
                                Text(
                                  'Loyalty member',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: _kGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: _kBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        rows[i],
                        if (i != rows.length - 1)
                          const Divider(height: 1, thickness: 1, color: _kBorder),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _PrimaryButton(
                  onPressed: onLinkAnother,
                  icon: Icons.add_card_rounded,
                  label: 'Link another card',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _kMaroon),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 13, color: _kMuted)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _kInk),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Banner (errors / cancelled)
// ---------------------------------------------------------------------------

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final fg = isError ? _kRed : _kGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isError ? _kRedSoft : _kGreenSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            size: 20,
            color: fg,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(fontSize: 14, color: fg)),
          ),
        ],
      ),
    );
  }
}