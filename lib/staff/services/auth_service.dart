import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

/// Real accounts now — Firebase Authentication (email + password) handles
/// sign-in/sign-out and session persistence, and a document in the
/// `staff` Firestore collection is what actually grants staff access:
/// [isCurrentUserStaff] checks for a `staff/{uid}` doc, not just "is
/// someone signed in". This replaces the old DEMO version, which
/// accepted any email/password and forgot every "signed in" session the
/// moment the app restarted (it only lived in a RAM variable).
///
/// Staff accounts are still provisioned by whoever manages the backend,
/// on purpose — there is no self-service "create account" flow in this
/// app. Two ways to create one for testing:
///
/// 1. Manually: Firebase Console > Authentication > Add user (email +
///    password), then Firestore > `staff` collection > add a document
///    whose ID is exactly that user's UID (copy it from the
///    Authentication user list), with whatever fields you want
///    (e.g. `{ "name": "Jana Dizon", "role": "Front Desk" }` — the
///    fields aren't checked here, only that the document exists).
/// 2. Once the Admin app's staff management page is wired to a real
///    backend too, adding a staff member there will do both steps for
///    you automatically.
/// The signed-in staff member's profile, read from their `staff/{uid}` doc.
class StaffProfile {
  final String uid;
  final String name;
  final String email;
  final String role;
  final bool active;
  final DateTime? createdAt;

  const StaffProfile({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.active,
    this.createdAt,
  });
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final fb.FirebaseAuth _auth = fb.FirebaseAuth.instance;

  static CollectionReference<Map<String, dynamic>> get _staffCol =>
      FirebaseFirestore.instance.collection('staff');

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
    } on FirebaseException catch (e) {
      throw Exception(_friendlyAuthError(e));
    } catch (e) {
      throw Exception("Something went wrong. Please try again.");
    }
  }

  /// True only if someone is signed in, their UID has a matching document
  /// in the `staff` collection, *and* that document isn't archived.
  /// The `active` flag is what the Admin app's staff screen toggles, so
  /// checking it here is what makes "Archive" actually lock someone
  /// out without deleting their account. A missing `active` field is
  /// treated as active, so hand-made Firestore Console docs (no `active`
  /// field at all) keep working.
  Future<bool> isCurrentUserStaff() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final doc = await _staffCol.doc(uid).get();
    if (!doc.exists) return false;
    final data = doc.data();
    // Archived staff can't sign in, whatever their `active` flag says.
    if ((data?['archived'] as bool?) ?? false) return false;
    return (data?['active'] as bool?) ?? true;
  }

  /// Live "does the signed-in person still have staff access?" feed:
  /// emits false the moment their `staff/{uid}` doc is deleted or flipped
  /// to `active: false` by an admin, so the dashboard can lock them out
  /// without waiting for an app restart. A snapshot served only from the
  /// local cache that says "missing" is ignored (offline isn't revoked
  /// access), and a permission-denied error counts as revoked.
  Stream<bool> watchAccess() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream<bool>.value(false);
    return _staffCol
        .doc(uid)
        .snapshots()
        .where((snap) => snap.exists || !snap.metadata.isFromCache)
        .map((snap) =>
            snap.exists &&
            ((snap.data()?['active'] as bool?) ?? true) &&
            !((snap.data()?['archived'] as bool?) ?? false))
        .transform(StreamTransformer<bool, bool>.fromHandlers(
      handleError: (error, stack, sink) {
        if (error is FirebaseException && error.code == 'permission-denied') sink.add(false);
      },
    ));
  }

  String? get currentEmail => _auth.currentUser?.email;

  /// The signed-in staff member's Firebase Auth uid — used to stamp
  /// `staffId` onto records this staff member creates (walk-in
  /// bookings, POS sales), separate from [currentEmail].
  String? get currentUid => _auth.currentUser?.uid;

  /// Best-effort display name for the signed-in staff member, read from
  /// their `staff/{uid}` Firestore doc (the same `name` field the Admin
  /// app's staff list shows). Falls back to their email, then to a
  /// generic label, so callers stamping "who did this" onto a record
  /// (e.g. which staff member accepted/rejected a booking) always get
  /// something displayable even if the staff doc has no `name` set.
  Future<String> currentStaffDisplayName() async {
    final uid = currentUid;
    if (uid != null) {
      try {
        final doc = await _staffCol.doc(uid).get();
        final name = (doc.data()?['name'] as String?)?.trim();
        if (name != null && name.isNotEmpty) return name;
      } catch (_) {
        // Falls through to the email/generic fallback below.
      }
    }
    return currentEmail ?? 'Staff';
  }

  /// Profile details for the signed-in staff member. Name/role/created
  /// date come from `staff/{uid}` (read-only for staff — only an admin can
  /// write that doc, per firestore.rules); email comes from Firebase Auth.
  /// Missing fields fall back to sensible defaults so a hand-made Console
  /// doc still renders.
  Future<StaffProfile> getProfile() async {
    final user = _auth.currentUser;
    final uid = user?.uid ?? '';
    Map<String, dynamic> d = {};
    if (uid.isNotEmpty) {
      try {
        final doc = await _staffCol.doc(uid).get();
        d = doc.data() ?? {};
      } catch (_) {
        // Fall back to Auth-only info below.
      }
    }
    final email = (user?.email ?? (d['email'] as String?) ?? '').trim();
    final name = ((d['name'] as String?) ?? '').trim();
    final role = ((d['role'] as String?) ?? '').trim();
    final ts = d['createdAt'];
    return StaffProfile(
      uid: uid,
      name: name.isNotEmpty ? name : (email.isNotEmpty ? email.split('@').first : 'Staff'),
      email: email,
      role: role.isNotEmpty ? role : 'Staff',
      active: (d['active'] as bool?) ?? true,
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Changes the signed-in staff member's own password. Re-authenticates
  /// with [currentPassword] first — Firebase requires a *recent* sign-in
  /// before it allows a password change, and re-entering the current
  /// password is what proves that here (rather than forcing a sign-out
  /// and back in). Throws with a friendly message if [currentPassword] is
  /// wrong or [newPassword] doesn't meet Firebase's minimum requirements.
  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw Exception("You're not signed in.");
    }
    try {
      final credential = fb.EmailAuthProvider.credential(email: user.email!, password: currentPassword);
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
    } on FirebaseException catch (e) {
      throw Exception(_friendlyAuthError(e));
    } catch (e) {
      throw Exception("Something went wrong. Please try again.");
    }
  }

  /// Sends Firebase's reset-link email. Deliberately does NOT report
  /// whether the email has an account (`user-not-found` is swallowed) so
  /// nobody can probe which addresses are registered — only a malformed
  /// email or a network problem is reported.
  Future<void> sendPasswordReset(String email) async {
    final key = email.trim();
    if (key.isEmpty) {
      throw Exception("Enter your email address.");
    }
    try {
      await _auth.sendPasswordResetEmail(email: key);
    } on FirebaseException catch (e) {
      if (e.code == 'user-not-found') return;
      throw Exception(_friendlyAuthError(e));
    } catch (e) {
      throw Exception("Something went wrong. Please try again.");
    }
  }

  static String _friendlyAuthError(FirebaseException e) {
    switch (e.code) {
      case 'invalid-email':
        return "That doesn't look like a valid email address.";
      case 'user-disabled':
        return "This account has been disabled.";
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return "Incorrect email or password.";
      case 'weak-password':
      case 'password-does-not-meet-requirements':
        return "Password is too weak — use at least 8 characters with upper and lowercase letters, a number, and a symbol.";
      case 'too-many-requests':
        return "Too many attempts. Please wait a few minutes and try again.";
      case 'requires-recent-login':
        return "For security, please sign out and sign in again, then retry.";
      case 'network-request-failed':
        return "Network error — check your internet connection and try again.";
      default:
        return e.message ?? "Something went wrong. Please try again.";
    }
  }
}