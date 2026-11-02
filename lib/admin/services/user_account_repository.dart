import 'package:cloud_firestore/cloud_firestore.dart';

/// A customer account created through the User app's Register screen.
class RegisteredAccount {
  final String uid;
  final String name;
  final String email;
  final String contact;
  final DateTime? createdAt;

  const RegisteredAccount({
    required this.uid,
    required this.name,
    required this.email,
    required this.contact,
    required this.createdAt,
  });
}

/// Admin-side read access to `users/{uid}` so a brand-new account shows up
/// for the admin right after the person registers, before they ever book.
/// Firestore rules already let admins read the users collection.
class UserAccountRepository {
  UserAccountRepository._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('users');

  /// Every real (non-guest) account, newest registration first.
  static Stream<List<RegisteredAccount>> watchAccounts() {
    return _col.snapshots().map((snap) {
      final list = <RegisteredAccount>[];
      for (final d in snap.docs) {
        final data = d.data();
        if (data['isGuest'] == true) continue; // guest checkouts aren't accounts
        final name = ((data['fullName'] ?? '') as String).trim();
        final email = ((data['email'] ?? '') as String).trim();
        if (name.isEmpty && email.isEmpty) continue;
        list.add(RegisteredAccount(
          uid: d.id,
          name: name,
          email: email,
          contact: ((data['contactNumber'] ?? '') as String).trim(),
          createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
        ));
      }
      list.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      return list;
    });
  }
}
