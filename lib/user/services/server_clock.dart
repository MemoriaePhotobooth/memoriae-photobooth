import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "What time is it really?" — as told by Firebase's servers, not the
/// phone. Used for the 15-minute booking hold and the 12 AM–6 AM booking
/// curfew, so changing the phone's clock can't cheat either one.
///
/// How it works: [sync] writes a server timestamp into `serverClock/{id}`,
/// reads it back, and remembers how far the phone's clock is off. [now]
/// is then the phone's clock plus that offset (still in local time zone).
///
/// Safe by design: if the sync fails for any reason (offline, the
/// `serverClock` rule not deployed yet), the offset stays at zero and the
/// app behaves exactly like before — it never blocks a booking.
class ServerClock {
  ServerClock._();

  static Duration _offset = Duration.zero;
  static DateTime? _lastTry;
  static Future<void>? _inflight;
  static const Duration _refreshAfter = Duration(minutes: 10);
  static const String _idPrefsKey = 'memoriae_clock_id';

  /// Current time, corrected by the last successful [sync].
  static DateTime now() => DateTime.now().add(_offset);

  /// Philippine Standard Time is always UTC+8 (no daylight saving).
  static const Duration _phOffset = Duration(hours: 8);

  /// The current Philippine time (UTC+8), whatever time zone the phone is
  /// set to. Only read the wall-clock fields (`year`, `month`, `day`,
  /// `hour`, `minute`) from the result — it is flagged as UTC purely so
  /// those fields come out as Manila time. Don't mix it with local
  /// `DateTime`s in comparisons.
  static DateTime phNow() => now().toUtc().add(_phOffset);

  /// Today's date in the Philippines at midnight, as a plain local
  /// `DateTime(y, m, d)` so it compares cleanly with calendar dates.
  static DateTime phToday() {
    final n = phNow();
    return DateTime(n.year, n.month, n.day);
  }

  /// Re-measures the offset (at most once per 10 minutes unless [force]).
  /// Never throws.
  static Future<void> sync({bool force = false}) {
    final last = _lastTry;
    if (!force && last != null && DateTime.now().difference(last) < _refreshAfter) {
      return Future.value();
    }
    return _inflight ??= _doSync().whenComplete(() => _inflight = null);
  }

  static Future<String> _clockId() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) return uid;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_idPrefsKey);
    if (id == null || id.isEmpty) {
      id = 'dev-${DateTime.now().microsecondsSinceEpoch}';
      await prefs.setString(_idPrefsKey, id);
    }
    return id;
  }

  static Future<void> _doSync() async {
    _lastTry = DateTime.now();
    try {
      final ref = FirebaseFirestore.instance.collection('serverClock').doc(await _clockId());
      final t0 = DateTime.now();
      await ref.set({'t': FieldValue.serverTimestamp()}).timeout(const Duration(seconds: 6));
      final snap = await ref.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 6));
      final t1 = DateTime.now();
      final ts = snap.data()?['t'];
      if (ts is! Timestamp) return;

      final rtt = t1.difference(t0);
      if (rtt > const Duration(seconds: 5)) return; // too slow to trust
      final localMid = t0.add(Duration(microseconds: rtt.inMicroseconds ~/ 2));
      var off = ts.toDate().difference(localMid);
      if (off.abs() < const Duration(seconds: 2)) off = Duration.zero; // ignore jitter
      _offset = off;
    } catch (_) {
      // Keep the previous offset (zero on first run) — see class doc.
    }
  }
}
