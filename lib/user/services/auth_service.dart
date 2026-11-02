import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:shared_preferences/shared_preferences.dart';

import 'local_db.dart';
import 'push_notification_service.dart';

/// A signed-in (or guest) customer, as the rest of the user app sees them.
/// Same shape as before — only the storage underneath changed.
class AppUser {
  final String uid;
  final String fullName;
  final String email;
  final DateTime? birthDate;
  final String? contactNumber;
  final bool isGuest;
  final String? paymentMethod;
  final List<String> contactPreferences;
  final String? billingAddress;
  final String? specialAssistance;

  /// GCash account refunds are sent to (saved from Profile → Payment
  /// Methods). Staff/Admin see it on a pending refund.
  final String? gcashName;
  final String? gcashNumber;

  /// Profile picture as a small base64 `data:` URI, or null when none is set.
  final String? profilePhoto;

  const AppUser({
    required this.uid,
    required this.fullName,
    required this.email,
    this.birthDate,
    this.contactNumber,
    this.isGuest = false,
    this.paymentMethod,
    this.contactPreferences = const [],
    this.billingAddress,
    this.specialAssistance,
    this.gcashName,
    this.gcashNumber,
    this.profilePhoto,
  });
}

/// Real accounts now — Firebase Authentication (email + password) handles
/// sign-up/sign-in/sign-out and session persistence; a matching profile
/// document in the `users` Firestore collection holds everything Firebase
/// Auth itself doesn't store (full name, birthdate, contact number,
/// payment preference, etc). Passwords are never touched or stored by this
/// app directly — Firebase Auth owns that entirely, so there's nothing
/// sensitive sitting in Firestore.
///
/// This replaces the old DEMO version's in-memory `Map` of accounts, which
/// is why registering used to "disappear" every time the app restarted —
/// that map lived only in RAM. A real Firebase Auth account, and this
/// Firestore doc, both persist the same way your bookings already do.
///
/// One-time setup required in the Firebase console (see README):
/// 1. Authentication > Sign-in method > enable "Email/Password".
/// 2. Firestore > Rules > allow a signed-in user to read/write their own
///    `users/{uid}` document.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  /// The signed-in customer's profile picture as a `data:` URI, or null.
  /// Every avatar in the user app listens to this, so they all update together.
  static final ValueNotifier<String?> photo = ValueNotifier<String?>(null);

  final fb.FirebaseAuth _auth = fb.FirebaseAuth.instance;

  /// How long an email verification stays valid. After this many days
  /// (counted from today's real date vs. the saved `lastVerifiedAt`),
  /// the user has to enter a fresh emailed code the next time they log in.
  static const Duration otpValidity = Duration(days: 30);

  static CollectionReference<Map<String, dynamic>> get _usersCol =>
      FirebaseFirestore.instance.collection('users');

  // Only used for guest browsing/checkout before any real account exists —
  // a per-device id (persisted via SharedPreferences, not a Firebase Auth
  // account, since guests never set a password) so a guest's bookings and
  // chat thread survive closing and reopening the app, not just this
  // in-memory session.
  String? _guestUid;
  static const String _guestUidPrefsKey = 'memoriae_guest_uid';

  String? get currentUid => _auth.currentUser?.uid ?? _guestUid;
  bool get isLoggedIn => _auth.currentUser != null;

  /// Loads the guest id saved on this device, or creates and saves a new
  /// one the first time. Reusing the same id across restarts is what lets
  /// a guest's `messages`/`bookings` docs and their `users/{uid}` profile
  /// (once they've gone through guest checkout) stay linked to them.
  Future<String> _loadOrCreateGuestUid() async {
    if (_guestUid != null) return _guestUid!;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_guestUidPrefsKey);
    if (saved != null && saved.isNotEmpty) {
      _guestUid = saved;
      return saved;
    }
    final fresh = 'guest-${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString(_guestUidPrefsKey, fresh);
    _guestUid = fresh;
    return fresh;
  }

  /// The signed-in (or guest) customer. Also keeps [photo] in sync.
  Future<AppUser?> me() async {
    final user = await _loadMe();
    photo.value = user?.profilePhoto;
    return user;
  }

  Future<AppUser?> _loadMe() async {
    final fbUser = _auth.currentUser;
    if (fbUser == null) {
      final uid = await _loadOrCreateGuestUid();
      // If a previous guest checkout on this device already wrote a
      // profile doc, read it back so their name/contact carry over too —
      // otherwise this is a guest who hasn't checked out yet.
      final doc = await _usersCol.doc(uid).get();
      final data = doc.data();
      if (data != null) return _fromDoc(uid, data);
      return AppUser(uid: uid, fullName: "Guest User", email: "", isGuest: true);
    }
    final doc = await _usersCol.doc(fbUser.uid).get();
    final data = doc.data();
    if (data != null && _isOtpDue(data)) {
      // Firebase keeps people signed in across app restarts, so without
      // this check someone who verified 30+ days ago would never be asked
      // for a code again. Signing out here sends them back through the
      // login page, which asks for the code.
      await _auth.signOut();
      return _loadMe();
    }
    if (data == null) {
      // Signed in but the profile doc is missing somehow — fall back
      // gracefully instead of crashing the Profile screen.
      return AppUser(uid: fbUser.uid, fullName: fbUser.displayName ?? (fbUser.email ?? "Account"), email: fbUser.email ?? "");
    }
    return _fromDoc(fbUser.uid, data);
  }

  /// True when the saved verification is missing or [otpValidity] (30 days)
  /// old. Compared against today's actual date. Accounts made before this
  /// field existed fall back to `createdAt` (that's when they verified).
  static bool _isOtpDue(Map<String, dynamic> data) {
    final ts = data['lastVerifiedAt'] ?? data['createdAt'];
    if (ts is! Timestamp) return true;
    return DateTime.now().difference(ts.toDate()) >= otpValidity;
  }

  /// Whether the currently signed-in account must enter a new emailed
  /// code before continuing (used right after a successful password login).
  Future<bool> isOtpDue() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    Map<String, dynamic>? data;
    try {
      data = (await _usersCol.doc(uid).get().timeout(const Duration(seconds: 15))).data();
    } catch (_) {
      return true; // can't tell (slow/no connection) - ask for a code to be safe
    }
    if (data == null) return true;
    return _isOtpDue(data);
  }

  /// True when a real (non-guest) account is still signed in from a previous
  /// visit AND its 30-day email verification hasn't expired. Firebase restores
  /// the saved session asynchronously (especially on web), so this waits for
  /// the first auth-state event instead of reading `currentUser` too early.
  /// Used by the welcome gate so reopening/refreshing the app lands the user
  /// back on their dashboard instead of the login page.
  Future<bool> hasValidSession() async {
    try {
      final u = await _auth.authStateChanges().first.timeout(const Duration(seconds: 8));
      if (u == null) return false;
      return !(await isOtpDue());
    } catch (_) {
      return _auth.currentUser != null;
    }
  }

  /// Saves "verified just now" — restarts the 30-day window.
  Future<void> markVerifiedNow() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception("You're not signed in.");
    await _usersCol.doc(uid).set({'lastVerifiedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  static AppUser _fromDoc(String uid, Map<String, dynamic> data) {
    final ts = data['birthDate'];
    return AppUser(
      uid: uid,
      fullName: data['fullName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      birthDate: ts is Timestamp ? ts.toDate() : null,
      contactNumber: data['contactNumber'] as String?,
      isGuest: data['isGuest'] as bool? ?? false,
      paymentMethod: data['paymentMethod'] as String?,
      contactPreferences: (data['contactPreferences'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      billingAddress: data['billingAddress'] as String?,
      specialAssistance: data['specialAssistance'] as String?,
      gcashName: data['gcashName'] as String?,
      gcashNumber: data['gcashNumber'] as String?,
      profilePhoto: _photoFrom(data['profilePhoto']),
    );
  }

  static String? _photoFrom(Object? value) =>
      (value is String && value.startsWith('data:image/')) ? value : null;

  /// Saves a new profile picture, or removes it when [bytes] is null. Stored
  /// on `users/{uid}` as a small base64 string (like receipts and chat photos),
  /// so no Firebase Storage is needed. The new picture shows right away and is
  /// rolled back if the save fails.
  Future<void> updateProfilePhoto({Uint8List? bytes, String mimeType = 'image/jpeg'}) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Log in to change your profile picture.');
    final previous = photo.value;
    final uri = bytes == null ? null : 'data:$mimeType;base64,${base64Encode(bytes)}';
    photo.value = uri;
    try {
      await _usersCol.doc(user.uid).set({
        'profilePhoto': uri ?? FieldValue.delete(),
      }, SetOptions(merge: true));
    } catch (_) {
      photo.value = previous;
      rethrow;
    }
  }

  /// Saves edits to the signed-in customer's own details (name, contact
  /// number, birthdate). Guests have no account, so this needs a signed-in
  /// user — `users/{uid}` is only writable by its owner (see firestore.rules).
  Future<void> updateProfile({
    required String fullName,
    required String contactNumber,
    required DateTime birthDate,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Log in to edit your profile.');
    final name = fullName.trim();
    final phone = contactNumber.trim();
    if (name.isEmpty || phone.isEmpty) throw Exception('Please fill in all fields.');
    await _usersCol.doc(user.uid).set({
      'fullName': name,
      'contactNumber': phone,
      'birthDate': Timestamp.fromDate(birthDate),
    }, SetOptions(merge: true));
    try {
      await user.updateDisplayName(name);
    } catch (_) {
      // Display name is cosmetic — the profile doc above is what the app reads.
    }
  }

  /// Saves (or, with empty values, clears) the GCash account refunds are
  /// sent to. Requires a signed-in account — `users/{uid}` is only
  /// writable by its owner (see firestore.rules).
  Future<void> saveRefundAccount({required String name, required String number}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Log in to save a payment method.');
    final n = name.trim();
    final phone = number.trim();
    await _usersCol.doc(uid).set({
      'gcashName': n.isEmpty ? FieldValue.delete() : n,
      'gcashNumber': phone.isEmpty ? FieldValue.delete() : phone,
      if (n.isNotEmpty || phone.isNotEmpty) 'paymentMethod': 'GCash',
    }, SetOptions(merge: true));
  }

  static CollectionReference<Map<String, dynamic>> get _emailIndexCol =>
      FirebaseFirestore.instance.collection('emailIndex');

  /// Checks whether a real (non-guest) account already exists for
  /// [email] — used to short-circuit registration *before* sending an
  /// OTP, so someone re-registering with an email they already used
  /// doesn't waste an email and get a confusing "already registered"
  /// error only after typing back a code that did verify correctly.
  ///
  /// Checks the public `emailIndex` doc first (fast, and works for
  /// every account created after that index existed), then falls back
  /// to Firebase Auth's own `fetchSignInMethodsForEmail` for accounts
  /// that predate it. Deliberately does NOT query the `users` collection
  /// directly — that collection's rules only allow a signed-in person to
  /// read their own doc, so a collection query from someone who isn't
  /// signed in yet (exactly the case here) would just throw
  /// permission-denied.
  Future<bool> emailHasAccount(String email) async {
    final key = email.trim();
    if (key.isEmpty) return false;

    try {
      final doc = await _emailIndexCol.doc(key.toLowerCase()).get();
      if (doc.exists) return true;
    } catch (_) {
      // Falls through to the Auth-based check below.
    }

    try {
      final methods = await _auth.fetchSignInMethodsForEmail(key);
      return methods.isNotEmpty;
    } catch (_) {
      // Some Firebase projects have "email enumeration protection" on,
      // which makes this always return empty regardless — the index
      // check above is the primary signal either way, so just fall back
      // to "not found" rather than blocking registration on an error here.
      return false;
    }
  }

  Future<AppUser> register({
    required String fullName,
    required String email,
    required String password,
    required DateTime birthDate,
    required String contactNumber,
    required bool emailVerified,
    String? paymentMethod,
    List<String> contactPreferences = const [],
    String? billingAddress,
    String? specialAssistance,
    String? termsVersion,
  }) async {
    final key = email.trim();
    if (key.isEmpty || password.isEmpty || fullName.trim().isEmpty || contactNumber.trim().isEmpty) {
      throw Exception("Please fill in all required fields.");
    }
    if (!emailVerified) {
      // Guards against register() ever being called without going through
      // the email OTP step first — should be unreachable from the UI,
      // but fails loudly rather than silently creating an unverified
      // account if some future code path forgets the check.
      throw Exception("Email must be verified before creating an account.");
    }
    if (_ageOn(birthDate, DateTime.now()) < 10) {
      throw Exception("You must be at least 10 years old to create an account.");
    }
    if (birthDate.year < 1970) {
      throw Exception("Birth year must be 1970 or later.");
    }
    final digitsOnly = contactNumber.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length != 11) {
      throw Exception("Contact number must be exactly 11 digits.");
    }
    if (!digitsOnly.startsWith('09')) {
      throw Exception("Contact number must start with 09.");
    }

    fb.UserCredential credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(email: key, password: password);
    } on FirebaseException catch (e) {
      throw Exception(_friendlyAuthError(e));
    } catch (e) {
      throw Exception("Something went wrong. Please try again.");
    }

    final uid = credential.user!.uid;
    final billing = (billingAddress ?? '').trim();
    final assistance = (specialAssistance ?? '').trim();

    await _usersCol.doc(uid).set({
      'fullName': fullName.trim(),
      'email': key,
      'birthDate': Timestamp.fromDate(birthDate),
      'contactNumber': contactNumber.trim(),
      'emailVerified': true,
      'lastVerifiedAt': FieldValue.serverTimestamp(),
      'isGuest': false,
      'paymentMethod': paymentMethod,
      'contactPreferences': contactPreferences,
      'billingAddress': billing.isEmpty ? null : billing,
      'specialAssistance': assistance.isEmpty ? null : assistance,
      // Proof of consent: when they ticked "I agree to the Terms of
      // Service, Cancellation Policy and Privacy Policy", and which
      // version of those pages they were looking at (kPoliciesVersion).
      if (termsVersion != null) ...{
        'agreedToTermsAt': FieldValue.serverTimestamp(),
        'termsVersion': termsVersion,
      },
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Best-effort — feeds emailHasAccount()'s duplicate-email check.
    // Wrapped so a failure here (e.g. rules not deployed yet) never
    // blocks the account that was just successfully created.
    try {
      await _emailIndexCol.doc(key.toLowerCase()).set({'createdAt': FieldValue.serverTimestamp()});
    } catch (_) {}

    await credential.user!.updateDisplayName(fullName.trim());

    // Creating the account signs the person in automatically — sign them
    // back out so they land on the login page and log in themselves.
    await _auth.signOut();

    return AppUser(
      uid: uid,
      fullName: fullName.trim(),
      email: key,
      birthDate: birthDate,
      contactNumber: contactNumber.trim(),
      paymentMethod: paymentMethod,
      contactPreferences: contactPreferences,
      billingAddress: billing.isEmpty ? null : billing,
      specialAssistance: assistance.isEmpty ? null : assistance,
    );
  }

  /// Lightweight identity for guest checkout — no password, no Firebase
  /// Auth account, just a profile doc so staff can still see who booked.
  Future<AppUser> registerGuest({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
  }) async {
    if (email.trim().isEmpty || firstName.trim().isEmpty || lastName.trim().isEmpty || phone.trim().isEmpty) {
      throw Exception("Please fill in all fields.");
    }
    final fullName = "${firstName.trim()} ${lastName.trim()}";
    // Reuse this device's existing guest id (same one messages/bookings
    // made before checkout are already tagged with) instead of minting a
    // new one, so nothing gets orphaned under a stale id.
    final uid = await _loadOrCreateGuestUid();

    await _usersCol.doc(uid).set({
      'fullName': fullName,
      'email': email.trim(),
      'contactNumber': phone.trim(),
      'isGuest': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    _guestUid = uid;
    return AppUser(uid: uid, fullName: fullName, email: email.trim(), contactNumber: phone.trim(), isGuest: true);
  }

  Future<AppUser> login({required String email, required String password}) async {
    fb.UserCredential credential;
    try {
      credential = await _auth
          .signInWithEmailAndPassword(email: email.trim(), password: password)
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw Exception(
          "Sign-in timed out - the phone couldn't reach the server. Check your internet, try another Wi-Fi or mobile data, then use \"Connection test\" below.");
    } on FirebaseException catch (e) {
      throw Exception(_friendlyAuthError(e));
    } catch (e) {
      throw Exception("Something went wrong (${e.runtimeType}). Please try again.");
    }
    final uid = credential.user!.uid;
    // Reading the profile must never block a login that already succeeded:
    // on a slow connection give up after 15s and carry on with what Firebase
    // Auth itself already knows (name + email).
    Map<String, dynamic>? data;
    try {
      final doc = await _usersCol.doc(uid).get().timeout(const Duration(seconds: 15));
      data = doc.data();
    } catch (_) {
      data = null;
    }
    if (data == null) {
      return AppUser(uid: uid, fullName: credential.user!.displayName ?? '', email: email.trim());
    }
    return _fromDoc(uid, data);
  }

  /// Permanently deletes the signed-in customer's account. The password is
  /// re-checked first (Firebase requires a recent login for this), then the
  /// `deleteMyAccount` Cloud Function removes the data and the login itself.
  /// Throws an [Exception] with a message the user can read.
  Future<void> deleteAccount({required String password}) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) {
      throw Exception('Log in to delete your account.');
    }

    try {
      await user.reauthenticateWithCredential(
        fb.EmailAuthProvider.credential(email: email, password: password),
      );
    } on fb.FirebaseAuthException catch (e) {
      final wrong = e.code == 'wrong-password' || e.code == 'invalid-credential' || e.code == 'invalid-login-credentials';
      throw Exception(wrong ? 'That password is incorrect.' : "Couldn't verify your password. Please try again.");
    }

    try {
      await FirebaseFunctions.instance.httpsCallable('deleteMyAccount').call<void>();
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? "Couldn't delete your account. Please try again.");
    }

    // The account is gone on the server. Clean up this phone too.
    try {
      await PushNotificationService.instance.removeToken();
    } catch (_) {
      // The profile doc is already gone, so there is nothing to remove.
    }
    await LocalDb.instance.clearUserData();
    try {
      await _auth.signOut();
    } catch (_) {
      // Already signed out by the server-side deletion.
    }
    photo.value = null;
  }

  Future<void> logout() async {
    await PushNotificationService.instance.removeToken();
    await _auth.signOut();
    photo.value = null;
    // Don't leave this customer's saved bookings on the phone.
    await LocalDb.instance.clearUserData();
    // _guestUid deliberately stays set so guest browsing/bookings keep
    // working under the same session id after logging out.
  }

  /// Sends a password-reset link to [email] via Firebase Auth's built-in
  /// flow — no custom email server or OTP code needed, Firebase handles
  /// composing and sending it. On success the person gets an email with a
  /// link that lets them set a new password; nothing changes here on our
  /// side until they've clicked it.
  ///
  /// Deliberately does NOT throw on `user-not-found` — reporting whether
  /// an email has an account would let someone probe for registered
  /// addresses. Every valid-looking email address gets the same success
  /// result; only a badly-formed one reports an error.
  Future<void> sendPasswordReset(String email) async {
    final key = email.trim();
    if (key.isEmpty) {
      throw Exception("Enter your email address.");
    }
    try {
      await _auth.sendPasswordResetEmail(email: key);
    } on FirebaseException catch (e) {
      if (e.code == 'user-not-found') return; // see doc comment above
      throw Exception(_friendlyAuthError(e));
    } catch (e) {
      throw Exception("Something went wrong. Please try again.");
    }
  }

  static String _friendlyAuthError(FirebaseException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return "There's already an account with that email — try logging in instead.";
      case 'invalid-email':
        return "That doesn't look like a valid email address.";
      case 'weak-password':
        return "Password is too weak — use at least 8 characters with upper and lowercase letters, a number, and a symbol.";
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return "Incorrect email or password.";
      case 'network-request-failed':
        return "Network error — check your internet connection and try again.";
      default:
        return e.message ?? "Something went wrong. Please try again.";
    }
  }

  static int _ageOn(DateTime birthDate, DateTime today) {
    int age = today.year - birthDate.year;
    final hadBirthdayThisYear =
        (today.month > birthDate.month) || (today.month == birthDate.month && today.day >= birthDate.day);
    if (!hadBirthdayThisYear) age--;
    return age;
  }
}