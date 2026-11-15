import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

const Color _kMaroon = Color(0xFF6E1B1E);
const Color _kMaroonTint = Color(0xFFF3E4E4);
const Color _kGreen = Color(0xFF0F6E56);
const Color _kGreenTint = Color(0xFFE1F5EE);
const Color _kBorder = Color(0xFFE5E5E5);
const Color _kMuted = Color(0xFF8A8A8A);

enum _StatusTab { all, active, inactive }

/// Admin view of RFID loyalty members, laid out like the Staff page:
/// status tabs, search, and a members table. Admins can deactivate a card.
class AdminLoyaltyScreen extends StatefulWidget {
  const AdminLoyaltyScreen({super.key});

  @override
  State<AdminLoyaltyScreen> createState() => _AdminLoyaltyScreenState();
}

class _AdminLoyaltyScreenState extends State<AdminLoyaltyScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  _StatusTab _tab = _StatusTab.all;

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
      // Keep the member doc and mark it inactive, so the customer's app shows Inactive.
      batch.update(_db.collection('loyaltyMembers').doc(d.id), {'active': false});
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

  Future<void> _reactivate(QueryDocumentSnapshot<Map<String, dynamic>> d) async {
    try {
      final hash = (d.data()['cardHash'] ?? '') as String;
      final batch = _db.batch();
      if (hash.isNotEmpty) {
        batch.update(_db.collection('loyaltyCards').doc(hash), {'active': true});
      }
      batch.update(_db.collection('loyaltyMembers').doc(d.id), {'active': true});
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Card reactivated.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not reactivate. Try again.')),
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

        bool isActive(QueryDocumentSnapshot<Map<String, dynamic>> d) => _cardActive[d.id] ?? true;
        final activeCount = docs.where(isActive).length;
        final inactiveCount = docs.length - activeCount;

        final filtered = docs.where((d) {
          if (_tab == _StatusTab.active && !isActive(d)) return false;
          if (_tab == _StatusTab.inactive && isActive(d)) return false;
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
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                _tabs(docs.length, activeCount, inactiveCount),
                SizedBox(width: 260, child: _searchField()),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kBorder),
              ),
              child: Column(
                children: [
                  _tableHeader(context),
                  if (docs.isEmpty)
                    _message(context, 'No loyalty members yet. Link a card from the staff app to get started.')
                  else if (filtered.isEmpty)
                    _message(context, 'No member matches this filter.')
                  else
                    for (var i = 0; i < filtered.length; i++) ...[
                      _memberRow(context, filtered[i]),
                      if (i < filtered.length - 1) const Divider(height: 1, color: Color(0xFFEFEFEF)),
                    ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Showing ${filtered.length} of ${docs.length} members',
                style: const TextStyle(fontSize: 12, color: _kMuted),
              ),
            ),
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
            'Loyalty members',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context)),
          ),
          const SizedBox(height: 4),
          Text(
            'Customers with a linked RFID card and a 10% package discount.',
            style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
          ),
        ],
      ),
    );
  }

  Widget _tabs(int all, int active, int inactive) {
    Widget tab(String label, int count, _StatusTab value) {
      final selected = _tab == value;
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _tab = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? const Color(0xFF1A1A1A) : const Color(0xFF6B6B6B),
                ),
              ),
              const SizedBox(width: 6),
              Text('$count', style: const TextStyle(fontSize: 12, color: _kMuted)),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          tab('All', all, _StatusTab.all),
          tab('Active', active, _StatusTab.active),
          tab('Inactive', inactive, _StatusTab.inactive),
        ],
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchCtrl,
      onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
      decoration: InputDecoration(
        hintText: 'Search name or email',
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF4F4F4),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kMaroon, width: 1.2),
        ),
      ),
    );
  }

  Widget _tableHeader(BuildContext context) {
    const style = TextStyle(fontSize: 11, color: _kMuted, letterSpacing: 0.4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAFA),
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 4, child: Text('MEMBER', style: style)),
          Expanded(flex: 2, child: Text('DISCOUNT', style: style)),
          Expanded(flex: 2, child: Text('STATUS', style: style)),
          Expanded(flex: 2, child: Text('LINKED', style: style)),
          SizedBox(width: 40),
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
    final linked = ts is Timestamp ? _shortDate(ts.toDate()) : 'Pending';
    final active = _cardActive[d.id] ?? true;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: _kMaroon,
                  child: Text(
                    initial,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        u == null ? 'Loading...' : (name.isEmpty ? 'No name on file' : name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppPalette.textPrimary(context)),
                      ),
                      Text(
                        email.isEmpty ? d.id : email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: _kMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(alignment: Alignment.centerLeft, child: _outlinePill('$pct% off', _kMaroon)),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: active
                  ? _tintPill('● Active', _kGreen, _kGreenTint)
                  : _tintPill('● Inactive', const Color(0xFF6B6B6B), const Color(0xFFF1F1F1)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(linked, style: const TextStyle(fontSize: 12, color: Color(0xFF6B6B6B))),
          ),
          SizedBox(
            width: 40,
            child: PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.more_horiz_rounded, size: 20, color: _kMuted),
              color: Colors.white,
              onSelected: (v) {
                if (v == 'deactivate') _confirmDeactivate(d);
                if (v == 'reactivate') _reactivate(d);
              },
              itemBuilder: (_) => [
                if (active)
                  const PopupMenuItem<String>(value: 'deactivate', child: Text('Deactivate card'))
                else
                  const PopupMenuItem<String>(value: 'reactivate', child: Text('Reactivate card')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _shortDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Widget _outlinePill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color)),
    );
  }

  Widget _tintPill(String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: fg)),
    );
  }

  Widget _message(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: AppPalette.textMuted(context)),
      ),
    );
  }
}
