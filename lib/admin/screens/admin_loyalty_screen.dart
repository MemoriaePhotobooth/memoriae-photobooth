import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_palette.dart';

const Color _kMaroon = Color(0xFF6E1B1E);
const Color _kMaroonTint = Color(0xFFF3E4E4);
const Color _kGreen = Color(0xFF0F6E56);
const Color _kGreenTint = Color(0xFFE1F5EE);
const Color _kBorder = Color(0xFFE5E5E5);

enum _Range { today, week, month, all }

/// Admin view of RFID loyalty members. Filter by when the card was linked,
/// search, and deactivate a card (the member loses the discount).
class AdminLoyaltyScreen extends StatefulWidget {
  const AdminLoyaltyScreen({super.key});

  @override
  State<AdminLoyaltyScreen> createState() => _AdminLoyaltyScreenState();
}

class _AdminLoyaltyScreenState extends State<AdminLoyaltyScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  _Range _range = _Range.month;

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

  /// Start of the selected range, or null for "All time".
  DateTime? _rangeStart() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_range) {
      case _Range.today:
        return today;
      case _Range.week:
        return today.subtract(Duration(days: now.weekday - 1));
      case _Range.month:
        return DateTime(now.year, now.month, 1);
      case _Range.all:
        return null;
    }
  }

  bool _inRange(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final start = _rangeStart();
    if (start == null) return true;
    final ts = d.data()['linkedAt'];
    return ts is Timestamp && !ts.toDate().isBefore(start);
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

        final filtered = docs.where((d) {
          if (!_inRange(d)) return false;
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
            _rangeChips(),
            const SizedBox(height: 14),
            _searchField(),
            const SizedBox(height: 14),
            if (docs.isEmpty)
              _message(context, 'No loyalty members yet. Link a card from the staff app to get started.')
            else if (filtered.isEmpty)
              _message(context, 'No member matches this filter.')
            else
              _list(context, filtered),
          ],
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RFID Loyalty Rewards',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context)),
          ),
          const SizedBox(height: 4),
          Text(
            'Members linked · ${DateFormat('MMMM y').format(DateTime.now())}',
            style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)),
          ),
        ],
      ),
    );
  }

  Widget _rangeChips() {
    Widget chip(String label, _Range value) {
      final selected = _range == value;
      return GestureDetector(
        onTap: () => setState(() => _range = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? _kMaroon : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? _kMaroon : _kBorder),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: selected ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip('Today', _Range.today),
        chip('This week', _Range.week),
        chip('This month', _Range.month),
        chip('All time', _Range.all),
      ],
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchCtrl,
      onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
      decoration: InputDecoration(
        hintText: 'Search by name or email',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: const BorderSide(color: _kMaroon, width: 1.5),
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<QueryDocumentSnapshot<Map<String, dynamic>>> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _memberRow(context, items[i]),
            if (i < items.length - 1) const Divider(height: 1, color: Color(0xFFEFEFEF)),
          ],
        ],
      ),
    );
  }

  Widget _memberRow(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final u = _users[d.id];
    final name = ((u?['fullName'] ?? '') as String).trim();
    final email = ((u?['email'] ?? '') as String).trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final pct = (d.data()['discountPercent'] as num?)?.toInt() ?? 10;
    final ts = d.data()['linkedAt'];
    final linked = ts is Timestamp ? DateFormat('MMM d').format(ts.toDate()) : 'Pending';
    final active = _cardActive[d.id] ?? true;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: _kMaroonTint,
            child: Text(
              initial,
              style: const TextStyle(color: _kMaroon, fontWeight: FontWeight.w600, fontSize: 14),
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
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppPalette.textPrimary(context)),
                ),
                const SizedBox(height: 2),
                Text(
                  email.isEmpty ? d.id : email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(linked, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
          const SizedBox(width: 10),
          _tag(active ? 'Active' : 'Inactive', active ? _kGreen : const Color(0xFF6B6B6B),
              active ? _kGreenTint : const Color(0xFFF1F1F1)),
          const SizedBox(width: 6),
          _tag('$pct% off', _kMaroon, _kMaroonTint),
          if (active) ...[
            const SizedBox(width: 4),
            SizedBox(
              width: 36,
              height: 36,
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: 'Deactivate card',
                icon: const Icon(Icons.block_rounded, size: 18),
                color: const Color(0xFF8A8A8A),
                onPressed: () => _confirmDeactivate(d),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tag(String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: fg)),
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
