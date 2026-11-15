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

    return Scaffold(
      appBar: AppBar(title: const Text('Link loyalty card')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
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
                const SizedBox(height: 20),
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
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(
                        width: 56,
                        height: 56,
                        child: CircularProgressIndicator(strokeWidth: 4, color: _kMaroon),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Tap the card on the reader',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Linking ${_customerName()}',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF6B6B6B)),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: _kMaroon),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Time left ${_timeLeft()}',
                          style: const TextStyle(fontSize: 12, color: _kMaroon, fontWeight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kMaroon,
                          side: const BorderSide(color: _kMaroon),
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: () => _cancelRequest(),
                        child: const Text('Cancel'),
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
        ),
      ),
    );
  }
}
