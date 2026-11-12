import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
    final mm = (secs ~/ 60).toString();
    final ss = (secs % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final customer = _customer;
    final name = (customer?.data()['name'] as String?) ?? '';
    final email = (customer?.data()['email'] as String?) ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Link loyalty card')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Customer email',
              hintText: 'name@example.com',
              border: OutlineInputBorder(),
            ),
            enabled: !_waiting,
            onSubmitted: (_) => _findCustomer(),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: (_searching || _waiting) ? null : _findCustomer,
            child: Text(_searching ? 'Searching...' : 'Find customer'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (customer != null && !_waiting) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? 'Customer' : name,
                        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(email),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _startLink,
                      child: const Text('Link card'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_waiting) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 16),
            Text(
              'Tap the card on the reader now.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Time left ${_timeLeft()}',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => _cancelRequest(message: 'Cancelled.'),
              child: const Text('Cancel'),
            ),
          ],
          if (_statusMessage != null && !_waiting) ...[
            const SizedBox(height: 20),
            Text(_statusMessage!, style: const TextStyle(fontSize: 16)),
          ],
        ],
      ),
    );
  }
}
