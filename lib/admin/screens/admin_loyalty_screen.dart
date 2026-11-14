import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_palette.dart';

/// Admin view of RFID loyalty members: who has a linked card and their discount.
/// Read-only. Cards are linked from the staff app; unlinking is not done here yet.
class AdminLoyaltyScreen extends StatefulWidget {
  const AdminLoyaltyScreen({super.key});

  @override
  State<AdminLoyaltyScreen> createState() => _AdminLoyaltyScreenState();
}

class _AdminLoyaltyScreenState extends State<AdminLoyaltyScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  // Customer profiles, fetched once per member and reused across rebuilds.
  final Map<String, Map<String, dynamic>> _users = {};
  final Set<String> _loadingUsers = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _ensureUsers(List<String> ids) async {
    final missing = ids
        .where((id) => !_users.containsKey(id) && !_loadingUsers.contains(id))
        .toList();
    if (missing.isEmpty) return;
    _loadingUsers.addAll(missing);
    final snaps = await Future.wait(
      missing.map((id) => _db.collection('users').doc(id).get()),
    );
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < missing.length; i++) {
        _users[missing[i]] = snaps[i].data() ?? <String, dynamic>{};
        _loadingUsers.remove(missing[i]);
      }
    });
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
        final ids = docs.map((d) => d.id).toList();
        WidgetsBinding.instance.addPostFrameCallback((_) => _ensureUsers(ids));

        final monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
        final thisMonth = docs.where((d) {
          final ts = d.data()['linkedAt'];
          return ts is Timestamp && !ts.toDate().isBefore(monthStart);
        }).length;

        final filtered = docs.where((d) {
          if (_query.isEmpty) return true;
          final u = _users[d.id] ?? const <String, dynamic>{};
          final name = ((u['fullName'] ?? '') as String).toLowerCase();
          final email = ((u['email'] ?? '') as String).toLowerCase();
          return name.contains(_query) || email.contains(_query);
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(child: _statCard(context, 'Members', '${docs.length}')),
                const SizedBox(width: 12),
                Expanded(child: _statCard(context, 'Linked this month', '$thisMonth')),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Search by name or email',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            if (docs.isEmpty)
              _message(
                context,
                'No loyalty members yet. Link a card from the staff app to get started.',
              )
            else if (filtered.isEmpty)
              _message(context, 'No member matches that search.')
            else
              for (final d in filtered) _memberTile(context, d),
          ],
        );
      },
    );
  }

  Widget _statCard(BuildContext context, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context))),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w500, color: AppPalette.textPrimary(context))),
        ],
      ),
    );
  }

  Widget _memberTile(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final u = _users[d.id];
    final name = ((u?['fullName'] ?? '') as String).trim();
    final email = ((u?['email'] ?? '') as String).trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final pct = (d.data()['discountPercent'] as num?)?.toInt() ?? 10;
    final ts = d.data()['linkedAt'];
    final linked = ts is Timestamp ? DateFormat('MMM d, y').format(ts.toDate()) : 'Pending';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(child: Text(initial)),
        title: Text(
          u == null ? 'Loading...' : (name.isEmpty ? 'No name on file' : name),
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(email.isEmpty ? d.id : email),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('$pct% off', style: const TextStyle(fontWeight: FontWeight.w500)),
            Text('Linked $linked',
                style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
          ],
        ),
      ),
    );
  }

  Widget _message(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: AppPalette.textMuted(context)),
      ),
    );
  }
}
