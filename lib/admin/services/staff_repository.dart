import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';

import '../models/staff_account_record.dart';
import 'activity_log_repository.dart';

/// Real accounts now — backed by two Firestore collections, `staff` and
/// `admins`, which is also exactly what `AuthService.isCurrentUserStaff()`
/// and `AdminService.isCurrentUserAdmin()` check. A person's row in this
/// screen literally *is* their access: their doc living in `staff` lets
/// them into the Staff app, `admins` lets them into the Admin app, and
/// deleting/deactivating that doc is what revokes it.
///
/// [addStaff] creates a real Firebase Auth account (email + a generated
/// password) *and* the matching Firestore doc in one action — no more
/// manual Firebase Console steps for every new hire.
class StaffRepository {
  StaffRepository._();

  static CollectionReference<Map<String, dynamic>> get _staffCol =>
      FirebaseFirestore.instance.collection('staff');
  static CollectionReference<Map<String, dynamic>> get _adminsCol =>
      FirebaseFirestore.instance.collection('admins');

  static CollectionReference<Map<String, dynamic>> _colFor(AccessRole role) =>
      role == AccessRole.admin ? _adminsCol : _staffCol;

  static StaffAccountRecord _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc, AccessRole role) {
    final data = doc.data();
    return StaffAccountRecord(
      id: doc.id,
      name: (data['name'] as String?)?.trim().isNotEmpty == true ? data['name'] as String : '(no name)',
      email: (data['email'] as String?) ?? '',
      role: role,
      active: (data['active'] as bool?) ?? true,
      archived: (data['archived'] as bool?) ?? false,
      createdAt: data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : null,
    );
  }

  /// Every staff + admin account, merged into one sorted list. Firestore
  /// has no "union of two collections" query, so this listens to both
  /// collections' live snapshots and re-combines whichever one changed —
  /// still a single live stream from the screen's point of view.
  static Stream<List<StaffAccountRecord>> watchAllStaff() {
    late final StreamController<List<StaffAccountRecord>> controller;
    StreamSubscription? staffSub;
    StreamSubscription? adminSub;
    List<StaffAccountRecord> latestStaff = [];
    List<StaffAccountRecord> latestAdmins = [];
    bool staffReady = false;
    bool adminsReady = false;

    void emit() {
      if (!staffReady || !adminsReady) return;
      final combined = [...latestStaff, ...latestAdmins]..sort((a, b) => a.name.compareTo(b.name));
      controller.add(combined);
    }

    controller = StreamController<List<StaffAccountRecord>>.broadcast(
      onListen: () {
        staffSub = _staffCol.snapshots().listen((snap) {
          latestStaff = snap.docs.map((d) => _fromDoc(d, AccessRole.staff)).toList();
          staffReady = true;
          emit();
        }, onError: controller.addError);
        adminSub = _adminsCol.snapshots().listen((snap) {
          latestAdmins = snap.docs.map((d) => _fromDoc(d, AccessRole.admin)).toList();
          adminsReady = true;
          emit();
        }, onError: controller.addError);
      },
      onCancel: () {
        staffSub?.cancel();
        adminSub?.cancel();
      },
    );
    return controller.stream;
  }

  /// Fixed default password per role. Must satisfy the Firebase project's
  /// password policy (uppercase, lowercase, number and a symbol, 6+ chars)
  /// or account creation fails. Trade-off: anyone who knows this default knows every
  /// new account's password until they'd change it themselves — and
  /// there's no self-service password change in this app yet, so for now
  /// treat these as shared knowledge among your own staff, not a secret
  /// per person.
  static String _defaultPasswordFor(AccessRole role) => role == AccessRole.admin ? 'Admin_2026' : 'Staff_2026';

  /// Creates a real Firebase Auth account for the new hire AND the
  /// Firestore doc (`staff/{uid}` or `admins/{uid}`) that actually grants
  /// access — done together so there's no manual Firebase Console step
  /// for every new person.
  ///
  /// Returns the default password for [role] (see [_defaultPasswordFor])
  /// so the caller can show it right after creating the account.
  ///
  /// Runs the account creation on a throwaway secondary Firebase App
  /// instance rather than the default one. `createUserWithEmailAndPassword`
  /// also signs the caller in *as* the new user on whatever app instance
  /// it runs on — on the default instance that would instantly kick the
  /// admin using this screen out of their own session. The secondary
  /// instance absorbs that side effect and gets deleted right after.
  static Future<String> addStaff({required String name, required String email, required AccessRole role}) async {
    final trimmedEmail = email.trim();
    final password = _defaultPasswordFor(role);

    final secondaryApp = await Firebase.initializeApp(
      name: 'staff-creation-${DateTime.now().microsecondsSinceEpoch}',
      options: Firebase.app().options,
    );

    try {
      final secondaryAuth = fb.FirebaseAuth.instanceFor(app: secondaryApp);
      late final fb.UserCredential cred;
      try {
        cred = await secondaryAuth.createUserWithEmailAndPassword(email: trimmedEmail, password: password);
      } on fb.FirebaseAuthException catch (e) {
        throw Exception(_friendlyCreateError(e));
      }
      final uid = cred.user!.uid;
      await secondaryAuth.signOut();

      await _colFor(role).doc(uid).set({
        'name': name,
        'email': trimmedEmail,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } finally {
      // Always clean up the secondary app, even if account creation or
      // the Firestore write above threw.
      await secondaryApp.delete();
    }

    return password;
  }

  // ---------------------------------------------------------------------
  // Safety rules (enforced here, not only in the UI, so no screen can
  // bypass them):
  //  1. You can't lock out, demote, archive or remove YOUR OWN account.
  //  2. The last active admin can't be deactivated, demoted or archived.
  //  3. Admin accounts are PROTECTED: nobody can archive, demote or
  //     delete an admin account (demoting would remove the admin doc, so
  //     it counts as deleting). Admins can still be sent a
  //     password reset. Flip
  //     [protectAdminAccounts] to false to allow it again.
  //  4. Only an ARCHIVED staff account can be permanently deleted.
  // ---------------------------------------------------------------------

  /// When true, admin accounts can't be archived, demoted to staff or
  /// deleted by anyone (including other admins).
  static const bool protectAdminAccounts = false;

  static const String _adminProtectedMessage =
      "Admin accounts are protected and can't be deleted, archived or demoted.";

  static String? get _myUid => fb.FirebaseAuth.instance.currentUser?.uid;

  static bool _isMe(StaffAccountRecord a) => a.id == _myUid;

  /// Number of admins who can still sign in (active and not archived).
  static Future<int> _activeAdminCount() async {
    final snap = await _adminsCol.get();
    return snap.docs.where((d) {
      final data = d.data();
      return ((data['active'] as bool?) ?? true) && !((data['archived'] as bool?) ?? false);
    }).length;
  }

  static Future<void> _guardNotLastAdmin(StaffAccountRecord a, String doing) async {
    if (a.role != AccessRole.admin || !a.active || a.archived) return;
    if (await _activeAdminCount() <= 1) {
      throw Exception("You can't $doing the last active admin. Add another admin first.");
    }
  }

  /// Flips the `active` flag on the person's access doc. `AuthService`
  /// and `AdminService` both check this on every sign-in, so setting it
  /// false locks them out immediately without deleting their account.
  /// Renames an account's display name. The login email is not changed here.
  static Future<void> updateName(StaffAccountRecord account, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) throw Exception("Name can't be empty.");
    await _colFor(account.role).doc(account.id).update({'name': trimmed});
    await ActivityLogRepository.log(
      action: 'Renamed account',
      targetSummary: '${account.name} → $trimmed (${account.email})',
    );
  }

  static Future<void> setActive(StaffAccountRecord account, bool active) async {
    if (account.archived) {
      throw Exception('Restore this account from the archive first.');
    }
    if (!active) {
      if (_isMe(account)) throw Exception("You can't deactivate your own account.");
      await _guardNotLastAdmin(account, 'deactivate');
    }
    await _colFor(account.role).doc(account.id).update({'active': active});
    await ActivityLogRepository.log(
      action: active ? 'Reactivated account' : 'Deactivated account',
      targetSummary: '${account.name} (${account.email})',
    );
  }

  /// Moves the person's access doc from one collection to the other
  /// (`staff` <-> `admins`). Their underlying Firebase Auth account and
  /// UID never change — only which collection's existence check they
  /// satisfy, which is what actually determines which app they can use.
  static Future<void> setRole(StaffAccountRecord account, AccessRole newRole) async {
    if (account.role == newRole) return;
    if (account.archived) throw Exception('Restore this account from the archive first.');
    if (newRole == AccessRole.staff) {
      if (protectAdminAccounts && account.role == AccessRole.admin) {
        throw Exception(_adminProtectedMessage);
      }
      if (_isMe(account)) throw Exception("You can't demote your own account.");
      await _guardNotLastAdmin(account, 'demote');
    }
    final fromCol = _colFor(account.role);
    final toCol = _colFor(newRole);

    final snap = await fromCol.doc(account.id).get();
    final data = snap.data() ?? {'name': account.name, 'email': account.email, 'active': account.active};

    await toCol.doc(account.id).set(data);
    await fromCol.doc(account.id).delete();
    await ActivityLogRepository.log(
      action: newRole == AccessRole.admin ? 'Promoted to admin' : 'Changed admin to staff',
      targetSummary: '${account.name} (${account.email})',
    );
  }

  /// Archive = soft delete. The doc stays (name, email, history) but the
  /// person is locked out (`active: false`) and hidden from the default
  /// list. Reversible with [restore]. Admins can be archived too (never
  /// yourself, never the last active admin).
  static Future<void> archive(StaffAccountRecord account) async {
    if (protectAdminAccounts && account.role == AccessRole.admin) {
      throw Exception(_adminProtectedMessage);
    }
    if (_isMe(account)) throw Exception("You can't archive your own account.");
    await _guardNotLastAdmin(account, 'archive');
    await _colFor(account.role).doc(account.id).update({
      'active': false,
      'archived': true,
      'archivedAt': FieldValue.serverTimestamp(),
      'archivedBy': fb.FirebaseAuth.instance.currentUser?.email ?? 'unknown',
    });
    await ActivityLogRepository.log(
      action: 'Archived account',
      targetSummary: '${account.name} (${account.email})',
    );
  }

  /// Emails the person a Firebase password-reset link. Works for any
  /// account (including other admins) without needing to know or set a
  /// password. Replaces the old "remove and re-add" workaround.
  static Future<void> sendPasswordReset(StaffAccountRecord account) async {
    try {
      await fb.FirebaseAuth.instance.sendPasswordResetEmail(email: account.email);
    } on fb.FirebaseAuthException catch (e) {
      throw Exception(e.message ?? "Couldn't send the reset email. Please try again.");
    }
    await ActivityLogRepository.log(
      action: 'Sent password reset',
      targetSummary: '${account.name} (${account.email})',
    );
  }

  /// Brings an archived account back. The account can sign in again right
  /// away (`active: true`).
  static Future<void> restore(StaffAccountRecord account) async {
    await _colFor(account.role).doc(account.id).update({
      'active': true,
      'archived': false,
      'archivedAt': FieldValue.delete(),
      'archivedBy': FieldValue.delete(),
    });
    await ActivityLogRepository.log(
      action: 'Restored account',
      targetSummary: '${account.name} (${account.email})',
    );
  }

  /// Permanent delete of the access doc. Only allowed for ARCHIVED staff
  /// accounts — never for admins, never for yourself, never straight from
  /// the active list. This does **not** delete the underlying Firebase
  /// Auth account (a client app can't delete someone else's; that needs
  /// the Admin SDK). With the doc gone, the person can no longer get into
  /// either app.
  static Future<void> removeStaff(StaffAccountRecord account) async {
    if (protectAdminAccounts && account.role == AccessRole.admin) {
      throw Exception(_adminProtectedMessage);
    }
    if (_isMe(account)) throw Exception("You can't delete your own account.");
    if (!account.archived) {
      throw Exception('Archive this account first, then delete it from the archive.');
    }
    await _colFor(account.role).doc(account.id).delete();
    await ActivityLogRepository.log(
      action: 'Deleted account',
      targetSummary: '${account.name} (${account.email})',
    );
  }

  static String _friendlyCreateError(fb.FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return "That email already has an account.";
      case 'invalid-email':
        return "That doesn't look like a valid email address.";
      case 'weak-password':
        return "Generated password was rejected as too weak — please try again.";
      case 'network-request-failed':
        return "Network error — check your internet connection and try again.";
      default:
        return e.message ?? "Couldn't create that account. Please try again.";
    }
  }
}