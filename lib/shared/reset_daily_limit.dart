import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../user/services/server_clock.dart';
import 'send_cooldown.dart';

/// Forgot-password daily cap: each email may request at most [maxPerDay]
/// reset links per calendar day. Once used up, the person can only request
/// again the next day (resets at 12:00 AM).
///
/// The count is stored in Firestore (`resetLimits/{email}`) so closing the
/// app or switching phones does NOT reset it, and the day is taken from
/// [ServerClock] so changing the phone's clock can't cheat it. A copy is
/// also kept in SharedPreferences as a fallback when Firestore is
/// unreachable (it never blocks someone because of a network problem).
class ResetDailyLimit {
  ResetDailyLimit._();

  static const int maxPerDay = 3;

  static const String limitMessage =
      "You've reached the limit of $maxPerDay password reset requests for today. Please try again tomorrow.";

  static String _id(String email) => SendCooldown.norm(email).replaceAll('/', '_');

  static String _today() {
    final n = ServerClock.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)}';
  }

  static DocumentReference<Map<String, dynamic>> _doc(String email) =>
      FirebaseFirestore.instance.collection('resetLimits').doc(_id(email));

  static String _prefsKey(String email) => 'reset_limit:${_id(email)}';

  static int _countFrom(Map<String, dynamic>? data, String day) {
    if (data == null || data['day'] != day) return 0;
    final c = data['count'];
    return c is int ? c : 0;
  }

  static Future<int> _localCount(String email, String day) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey(email)); // "2026-10-21|2"
    if (raw == null) return 0;
    final parts = raw.split('|');
    if (parts.length != 2 || parts[0] != day) return 0;
    return int.tryParse(parts[1]) ?? 0;
  }

  /// True when [email] still has requests left today.
  static Future<bool> canRequest(String email) async {
    if (_id(email).isEmpty) return true;
    await ServerClock.sync();
    final day = _today();
    var used = await _localCount(email, day);
    try {
      final snap = await _doc(email).get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 6));
      final remote = _countFrom(snap.data(), day);
      if (remote > used) used = remote;
    } catch (_) {
      // Offline / rule not deployed yet: rely on the local count only.
    }
    return used < maxPerDay;
  }

  /// Call AFTER a reset link was sent successfully to count it for today.
  static Future<void> recordRequest(String email) async {
    if (_id(email).isEmpty) return;
    final day = _today();
    var count = await _localCount(email, day) + 1;
    try {
      count = await FirebaseFirestore.instance.runTransaction<int>((tx) async {
        final ref = _doc(email);
        final snap = await tx.get(ref);
        final next = _countFrom(snap.data(), day) + 1;
        tx.set(ref, {'day': day, 'count': next, 'updatedAt': FieldValue.serverTimestamp()});
        return next;
      }).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Keep the local count.
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey(email), '$day|$count');
  }
}
