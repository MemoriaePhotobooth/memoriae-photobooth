import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

const Color _kMaroon = Color(0xFF6E1B1E);
const Color _kBorder = Color(0xFFE5E5E5);

/// Staff screen to link a loyalty card to a customer.
///
/// 1. Staff finds the customer by email.
/// 2. Staff taps "Link card", which writes loyaltyLinkRequests/{staffUid}.
/// 3. The customer taps the card on the reader within 2 minutes. The Worker
///    writes the result (linked, card_in_use, or no_customer) into that request.
/// 4. This screen shows the result and removes the request.
class StaffLoyaltyLinkPanel extends StatefulWidget {
  const StaffLoyaltyLinkPanel({super.key, this.onClose});

  /// Called when the staff member closes the panel.
  final VoidCallback? onClose;

  @override
  State<StaffLoyaltyLinkPanel> createState() => _StaffLoyaltyLinkPanelState();
}

class _StaffLoyaltyLinkPanelState extends State<StaffLoyaltyLinkPanel> {
  static const Duration _linkWindow = Duration(minutes: 2);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _emailCtrl = TextEditingController();

  bool _searching = false;
  bool _waiting = false;
  String? _error;
  String? _statusMessage;
  bool _statusIsError = false;
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
        final member = await _db.collection('loyaltyMembers').doc(snap.docs.first.id).get();
        if (!mounted) return;
        final alreadyActive = member.exists && member.data()?['active'] != false;
        if (alreadyActive) {
          setState(() => _error = 'This customer already has an active card. Deactivate it first in the admin page.');
        } else {
          setState(() => _customer = snap.docs.first);
        }
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
        final name = _customerName();
        _finish('Card linked to $name.', isError: false);
      } else if (status == 'already_linked') {
        _finish('This card is already linked to this customer.', isError: true);
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

  Future<void> _finish(String message, {required bool isError}) async {
    _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
    _ticker = null;
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

  Widget _stepLabel(String number, String label) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: _kMaroon, shape: BoxShape.circle),
          child: Text(
            number,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: Color(0xFF8A8A8A),
          ),
        ),
      ],
    );
  }

  // Share of the 2 minute window still left, used to draw the ring.
  double _remainingFraction() {
    if (_expiresAt == null) return 0;
    final left = _expiresAt!.difference(DateTime.now()).inMilliseconds /
        _linkWindow.inMilliseconds;
    return left.clamp(0.0, 1.0).toDouble();
  }

  // Reader-style ring: a maroon disc in a ring that drains as the time runs out.
  Widget _readerRing() {
    return SizedBox(
      width: 130,
      height: 130,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kMaroon.withValues(alpha: 0.05),
            ),
          ),
          SizedBox(
            width: 120,
            height: 120,
            child: CircularProgressIndicator(
              value: _remainingFraction(),
              strokeWidth: 4,
              color: _kMaroon,
              backgroundColor: const Color(0xFFEFE3E3),
            ),
          ),
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: _kMaroon),
            child: const Icon(Icons.contactless_outlined, color: Colors.white, size: 36),
          ),
        ],
      ),
    );
  }

  String _timeLeft() {
    if (_expiresAt == null) return '';
    final left = _expiresAt!.difference(DateTime.now());
    final secs = left.inSeconds < 0 ? 0 : left.inSeconds;
    final mm = (secs ~/ 60).toString();
    final ss = (secs % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final customer = _customer;
    final name = ((customer?.data()['fullName'] ?? '') as String).trim();
    final email = ((customer?.data()['email'] ?? '') as String).trim();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Link a loyalty card',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded),
                onPressed: widget.onClose,
              ),
            ],
          ),
          const SizedBox(height: 4),
              _stepLabel('1', 'Find customer'),
              const SizedBox(height: 8),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                enabled: !_waiting,
                onSubmitted: (_) => _findCustomer(),
                decoration: InputDecoration(
                  labelText: 'Customer email',
                  hintText: 'name@example.com',
                  prefixIcon: const Icon(Icons.mail_outline_rounded, size: 20),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _kBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _kBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _kMaroon, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _kMaroon,
                  minimumSize: const Size.fromHeight(46),
                ),
                onPressed: (_searching || _waiting) ? null : _findCustomer,
                icon: const Icon(Icons.search_rounded, size: 18),
                label: Text(_searching ? 'Searching...' : 'Find customer'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              if (customer != null && !_waiting) ...[
                const SizedBox(height: 22),
                _stepLabel('2', 'Confirm and link'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'Customer' : name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(email, style: const TextStyle(fontSize: 12, color: Color(0xFF6B6B6B))),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _kMaroon,
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: _startLink,
                        icon: const Icon(Icons.link_rounded, size: 18),
                        label: const Text('Link card'),
                      ),
                    ],
                  ),
                ),
              ],
              if (_waiting) ...[
                const SizedBox(height: 22),
                _stepLabel('2', 'Tap the card'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Column(
                    children: [
                      _readerRing(),
                      const SizedBox(height: 20),
                      const Text(
                        'Tap the card on the reader',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 13, color: Color(0xFF6B6B6B)),
                          children: [
                            const TextSpan(text: 'Linking to '),
                            TextSpan(
                              text: _customerName(),
                              style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F4F4),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.timer_outlined, size: 16, color: _kMaroon),
                            const SizedBox(width: 6),
                            Text(
                              'Time left ${_timeLeft()}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kMaroon),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _kMaroon,
                            side: const BorderSide(color: _kBorder),
                            minimumSize: const Size.fromHeight(44),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => _cancelRequest(),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_statusMessage != null && !_waiting) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _statusIsError ? const Color(0xFFFBEAEA) : const Color(0xFFE1F5EE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _statusIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                        size: 20,
                        color: _statusIsError ? const Color(0xFFA32D2D) : const Color(0xFF0F6E56),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: TextStyle(
                            fontSize: 14,
                            color: _statusIsError ? const Color(0xFFA32D2D) : const Color(0xFF0F6E56),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
          ],
        ),
      );
  }
}
