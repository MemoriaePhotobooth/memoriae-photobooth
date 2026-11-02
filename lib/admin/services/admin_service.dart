import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

/// Real accounts now — Firebase Authentication (email + password) handles
/// sign-in/sign-out and session persistence, and a document in the
/// `admins` Firestore collection is what actually grants admin access:
/// [isCurrentUserAdmin] checks for an `admins/{uid}` doc, not just "is
/// someone signed in". This replaces the old DEMO version, which
/// accepted any email/password and forgot every "signed in" session the
/// moment the app restarted (it only lived in a RAM variable).
///
/// Admin accounts are still provisioned by whoever manages the backend,
/// on purpose — there is no self-service "create account" flow in this
/// app. To create one for testing: Firebase Console > Authentication >
/// Add user (email + password), then Firestore > `admins` collection >
/// add a document whose ID is exactly that user's UID (copy it from the
/// Authentication user list). The document's fields aren't checked here
/// — only that it exists — but a `name` field is nice for your own
/// reference.
///
/// This is the Admin app — anyone who can sign in here has full access
/// (staff management, pricing, plus everything Staff has); there is no
/// lower-privilege role within this project.
/// The signed-in admin's profile, read from their `admins/{uid}` doc.
class AdminProfile {
  final String uid;
  final String name;
  final String email;
  final String role;
  final bool active;
  final DateTime? createdAt;

  const AdminProfile({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.active,
    this.createdAt,
  });
}

class AdminService {
  AdminService._();
  static final AdminService instance = AdminService._();

  final fb.FirebaseAuth _auth = fb.FirebaseAuth.instance;

  static CollectionReference<Map<String, dynamic>> get _adminsCol =>
      FirebaseFirestore.instance.collection('admins');

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
    } on FirebaseException catch (e) {
      // Catches FirebaseAuthException too (it's a subclass) — on Flutter
      // Web, some error paths surface as the plain base type instead, and
      // a catch clause typed only to FirebaseAuthException would miss
      // those, letting the raw exception crash past our friendly message.
      throw Exception(_friendlyAuthError(e));
    } catch (e) {
      // Last-resort net so nothing thrown here ever reaches Flutter's
      // default error screen unhandled.
      throw Exception("Something went wrong. Please try again.");
    }
  }

  /// True only if someone is signed in, their UID has a matching document
  /// in the `admins` collection, *and* that doc hasn't been deactivated —
  /// this is what `StaffRepository.setActive(account, false)` actually
  /// locks. A missing `active` field is treated as active, so hand-made
  /// Firestore Console docs (no `active` field at all) keep working.
  Future<bool> isCurrentUserAdmin() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final doc = await _adminsCol.doc(uid).get();
    if (!doc.exists) return false;
    final data = doc.data();
    if ((data?['archived'] as bool?) ?? false) return false;
    return (data?['active'] as bool?) ?? true;
  }

  String? get currentEmail => _auth.currentUser?.email;

  /// Profile details for the signed-in admin: name/role/created date from
  /// `admins/{uid}`, email from Firebase Auth. Missing fields fall back to
  /// sensible defaults so hand-made Console docs still render.
  Future<AdminProfile> getProfile() async {
    final user = _auth.currentUser;
    final uid = user?.uid ?? '';
    Map<String, dynamic> d = {};
    if (uid.isNotEmpty) {
      try {
        final doc = await _adminsCol.doc(uid).get();
        d = doc.data() ?? {};
      } catch (_) {
        // Fall back to Auth-only info below.
      }
    }
    final email = (user?.email ?? (d['email'] as String?) ?? '').trim();
    final name = ((d['name'] as String?) ?? '').trim();
    final role = ((d['role'] as String?) ?? '').trim();
    final ts = d['createdAt'];
    return AdminProfile(
      uid: uid,
      name: name.isNotEmpty ? name : (email.isNotEmpty ? email.split('@').first : 'Admin'),
      email: email,
      role: role.isNotEmpty ? role : 'Admin',
      active: (d['active'] as bool?) ?? true,
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }

  Future<String>? _roleLabelFuture;

  /// The signed-in admin's role as stored on `admins/{uid}` (e.g. for the
  /// sidebar profile card). Loaded once and remembered until sign-out, so
  /// the card can rebuild freely without re-reading Firestore.
  Future<String> currentRoleLabel() => _roleLabelFuture ??= getProfile().then((p) => p.role).catchError((_) => 'Admin');

  Future<void> signOutAdmin() async {
    _roleLabelFuture = null;
    await _auth.signOut();
  }

  /// Changes the signed-in admin's own password. Re-authenticates with
  /// [currentPassword] first — Firebase requires a *recent* sign-in
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