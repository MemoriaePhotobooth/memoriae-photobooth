import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_palette.dart';

const Color _kMaroon = Color(0xFF6E1B1E);

/// Admin view of RFID loyalty members: linked card, active status, and discount.
/// Admins can deactivate a card here; the member loses the discount.
class AdminLoyaltyScreen extends StatefulWidget {
  const AdminLoyaltyScreen({super.key});

  @override
  State<AdminLoyaltyScreen> createState() => _AdminLoyaltyScreenState();
}

class _AdminLoyaltyScreenState extends State<AdminLoyaltyScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  // Profile and card status per member, fetched once and reused across rebuilds.
  final Map<String, Map<String, dynamic>> _users = {};
  final Map<String, bool> _cardActive = {};
  final Set<String> _loading = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _ensureData(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final todo = docs
        .where((d) => !_loading.contains(d.id) && (!_users.containsKey(d.id) || !_cardActive.containsKey(d.id)))
        .toList();
    if (todo.isEmpty) return;
    _loading.addAll(todo.map((d) => d.id));

    final userSnaps = await Future.wait(
      todo.map((d) => _db.collection('users').doc(d.id).get()),
    );
    final cardSnaps = await Future.wait(
      todo.map((d) {
        final hash = (d.data()['cardHash'] ?? '') as String;
        return _db.collection('loyaltyCards').doc(hash.isEmpty ? '_none' : hash).get();
      }),
    );

    if (!mounted) return;
    setState(() {
      for (var i = 0; i < todo.length; i++) {
        final id = todo[i].id;
        _users[id] = userSnaps[i].data() ?? <String, dynamic>{};
        _cardActive[id] = cardSnaps[i].data()?['active'] != false;
        _loading.remove(id);
      }
    });
  }

  Future<void> _confirmDeactivate(QueryDocumentSnapshot<Map<String, dynamic>> d) async {
    final u = _users[d.id];
    final name = ((u?['fullName'] ?? '') as String).trim();
    final who = name.isEmpty ? 'This customer' : name;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate card?'),
        content: Text('$who will lose the loyalty discount. They get it back by linking a card again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kMaroon),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final hash = (d.data()['cardHash'] ?? '') as String;
      final batch = _db.batch();
      if (hash.isNotEmpty) {
        batch.update(_db.collection('loyaltyCards').doc(hash), {'active': false});
      }
      batch.delete(_db.collection('loyaltyMembers').doc(d.id));
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Card deactivated.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not deactivate. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = _db
        .collection('loyaltyMembers')
        .orderBy('linkedAt', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return _message(context, 'Could not load loyalty members. Try again.');
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;
        WidgetsBinding.instance.addPostFrameCallback((_) => _ensureData(docs));

        final monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
        final thisMonth = docs.where((d) {
          final ts = d.data()['linkedAt'];
          return ts is Timestamp && !ts.toDate().isBefore(monthStart);
        }).length;
        final activeCount = docs.where((d) => _cardActive[d.id] ?? true).length;

        final filtered = docs.where((d) {
          if (_query.isEmpty) return true;
          final u = _users[d.id] ?? const <String, dynamic>{};
          final name = ((u['fullName'] ?? '') as String).toLowerCase();
          final email = ((u['email'] ?? '') as String).toLowerCase();
          return name.contains(_query) || email.contains(_query);
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _header(context),
            Row(
              children: [
                Expanded(child: _statCard(context, Icons.card_membership_outlined, 'Members', '${docs.length}')),
                const SizedBox(width: 12),
                Expanded(child: _statCard(context, Icons.check_circle_outline, 'Active cards', '$activeCount')),
                const SizedBox(width: 12),
                Expanded(child: _statCard(context, Icons.calendar_month_outlined, 'Linked this month', '$thisMonth')),
              ],
            ),
            const SizedBox(height: 18),
            _searchField(context),
            const SizedBox(height: 16),
            if (docs.isEmpty)
              _message(context, 'No loyalty members yet. Link a card from the staff app to get started.')
            else if (filtered.isEmpty)
              _message(context, 'No member matches that search.')
            else
              for (final d in filtered) _memberCard(context, d),
          ],
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Loyalty members',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context)),
          ),
          const SizedBox(height: 4),
          Text(
            'Customers with a linked RFID card and a 10% package discount',
            style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
          ),
        ],
      ),
    );
  }

  Widget _statCard(BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _kMaroon.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: _kMaroon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.textPrimary(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    final theme = Theme.of(context);
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: c, width: w),
        );
    return TextField(
      controller: _searchCtrl,
      onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
      decoration: InputDecoration(
        hintText: 'Search by name or email',
        prefixIcon: const Icon(Icons.search_rounded),
        isDense: true,
        filled: true,
        fillColor: theme.colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: border(theme.dividerColor),
        enabledBorder: border(theme.dividerColor),
        focusedBorder: border(_kMaroon, 1.5),
      ),
    );
  }

  Widget _memberCard(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final theme = Theme.of(context);
    final u = _users[d.id];
    final name = ((u?['fullName'] ?? '') as String).trim();
    final email = ((u?['email'] ?? '') as String).trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final pct = (d.data()['discountPercent'] as num?)?.toInt() ?? 10;
    final ts = d.data()['linkedAt'];
    final linked = ts is Timestamp ? DateFormat('MMM d, y').format(ts.toDate()) : 'Pending';
    final active = _cardActive[d.id] ?? true;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: _kMaroon,
            child: Text(
              initial,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u == null ? 'Loading...' : (name.isEmpty ? 'No name on file' : name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email.isEmpty ? d.id : email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _pill(
                active ? 'Active' : 'Inactive',
                active ? Colors.green.shade800 : AppPalette.textMuted(context),
                active ? Colors.green.withValues(alpha: 0.12) : theme.dividerColor.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 6),
              _pill('$pct% off', _kMaroon, _kMaroon.withValues(alpha: 0.08)),
              const SizedBox(height: 4),
              Text(
                'Linked $linked',
                style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context)),
              ),
            ],
          ),
          if (active)
            IconButton(
              tooltip: 'Deactivate card',
              icon: const Icon(Icons.block_rounded),
              color: AppPalette.textMuted(context),
              onPressed: () => _confirmDeactivate(d),
            ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  Widget _message(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: AppPalette.textMuted(context)),
      ),
    );
  }
}
