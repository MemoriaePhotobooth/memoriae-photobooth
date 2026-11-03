import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'activity_log_repository.dart';

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

  /// Permanently deletes a customer's login and personal data through the
  /// `adminDeleteCustomer` Cloud Function. Booking and payment records are
  /// kept for accounting, detached from the account. Throws an [Exception]
  /// with a message the admin can read.
  static Future<void> deleteCustomerAccount({required String uid, required String name}) async {
    try {
      await FirebaseFunctions.instance.httpsCallable('adminDeleteCustomer').call<void>({'uid': uid});
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? "Couldn't delete this account. Please try again.");
    }
    await ActivityLogRepository.log(action: 'Deleted customer account', targetSummary: name);
  }
}
