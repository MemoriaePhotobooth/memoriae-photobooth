/// In-memory throttle for "send me an email" buttons (OTP codes, password
/// reset links) so they can't be spammed.
///
/// State lives for the life of the app process, so closing and re-opening a
/// dialog/sheet does NOT reset the countdown. Keys are per purpose + email,
/// e.g. `otp:juan@email.com` or `reset:juan@email.com`.
class SendCooldown {
  SendCooldown._();

  static final Map<String, DateTime> _until = {};
  static final Map<String, List<DateTime>> _log = {};

  /// The last OTP code sent per key — lets a re-opened OTP sheet reuse the
  /// code that was just emailed instead of mailing a new one.
  static final Map<String, String> codes = {};

  /// Wrong OTP attempts per key.
  static final Map<String, int> wrongTries = {};

  static String norm(String email) => email.trim().toLowerCase();

  /// Seconds left before this key may send again (0 = free to send).
  static int remainingSeconds(String key) {
    final until = _until[key];
    if (until == null) return 0;
    final ms = until.difference(DateTime.now()).inMilliseconds;
    if (ms <= 0) {
      _until.remove(key);
      return 0;
    }
    return (ms / 1000).ceil();
  }

  static void start(String key, Duration d) => _until[key] = DateTime.now().add(d);

  /// Records one send for the hourly cap.
  static void record(String key) => (_log[key] ??= []).add(DateTime.now());

  /// null when under the cap; otherwise how many minutes until the oldest
  /// send in the last hour drops off and another is allowed.
  static int? hourlyWaitMinutes(String key, {int max = 5}) {
    final now = DateTime.now();
    final list = (_log[key] ??= [])..removeWhere((t) => now.difference(t) >= const Duration(hours: 1));
    if (list.length < max) return null;
    final wait = const Duration(hours: 1) - now.difference(list.first);
    final mins = (wait.inSeconds / 60).ceil();
    return mins < 1 ? 1 : mins;
  }
}
