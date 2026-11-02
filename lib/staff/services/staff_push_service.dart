import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Saves this phone's FCM token on `staff/{uid}.fcmTokens` so the Cloud
/// Functions can push new bookings and customer messages to staff.
/// Best-effort: the app works fine if push is unavailable.
class StaffPushService {
  StaffPushService._();

  static bool _listening = false;

  static Future<void> register() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token != null) await _save(user.uid, token);
      if (!_listening) {
        _listening = true;
        messaging.onTokenRefresh.listen((t) {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null) _save(uid, t).catchError((_) {});
        });
      }
    } catch (_) {
      // Ignore: no push, but staff can still use the app.
    }
  }

  static Future<void> _save(String uid, String token) {
    return FirebaseFirestore.instance
        .collection('staff')
        .doc(uid)
        .update({'fcmTokens': FieldValue.arrayUnion([token])});
  }
}
