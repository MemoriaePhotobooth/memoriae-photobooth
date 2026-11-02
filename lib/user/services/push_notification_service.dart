import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../firebase_options.dart';
import '../../shared/top_alert.dart';
import '../theme/app_colors.dart';
import '../screens/my_bookings_screen.dart';

/// Runs when a push arrives while the app is fully closed or in the
/// background. Messages sent with a `notification` block are already shown
/// by Android itself (the pop-up at the top of the phone); this only has to
/// exist so Firebase can start the app's isolate.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

/// Push notifications for the customer app: staff replies, booking
/// approved / declined / rescheduled / refunded, and new announcements pop
/// up on the phone even when the app is closed or the person is on the
/// home screen of their phone.
///
/// The messages themselves are sent by the Cloud Functions in `functions/`
/// (a phone can only be reached while the app is closed by a server).
/// This class handles the phone side: permission, the high-importance
/// channel (the one that pops up at the top), saving this phone's token on
/// `users/{uid}.fcmTokens`, showing pushes that arrive while the app is
/// open, and opening the right screen when one is tapped.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  /// Shared with the User app's `MaterialApp` so a tap can open a screen
  /// from outside the widget tree.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // Android keeps a channel's sound forever once created, so the custom
  // sound lives on a new channel id (the old 'memoriae_high' is unused).
  // Keep in sync with functions/payload.js and AndroidManifest.xml.
  static const String _channelId = 'memoriae_alerts';
  static const String _channelName = 'Memoriae alerts';
  static const String _soundFile = 'memoriae_chime'; // android/app/src/main/res/raw
  static const String _prefKey = 'push_enabled';
  static const String _announcementsTopic = 'announcements';

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _started = false;
  bool _appReady = false;
  String? _pendingTarget;
  String? _token;
  bool _enabled = true;
  AppLifecycleListener? _lifecycle;

  /// Whether the customer wants notifications (Profile > Notifications).
  bool get enabled => _enabled;

  // Browsers need a service worker + VAPID key for push, so this is
  // Android / iOS only for now.
  bool get _supported => !kIsWeb;

  /// Call once at startup, after `Firebase.initializeApp`.
  Future<void> init() async {
    if (!_supported || _started) return;
    _started = true;
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      final messaging = FirebaseMessaging.instance;

      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_memoriae'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (r) => _handleTarget(r.payload),
      );
      try {
        final prefs = await SharedPreferences.getInstance();
        _enabled = prefs.getBool(_prefKey) ?? true;
      } catch (_) {}

      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: 'Booking updates, staff messages and announcements',
            importance: Importance.max,
            playSound: true,
            sound: RawResourceAndroidNotificationSound(_soundFile),
            enableVibration: true,
            showBadge: true,
          ));

      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      // While the app is open we draw our own pop-up at the top (see
      // _showForeground), so iOS shouldn't also show its system banner.
      await messaging.setForegroundNotificationPresentationOptions(alert: false, badge: true, sound: true);

      // Everyone (guests too) gets announcements.
      if (_enabled) {
        unawaited(messaging.subscribeToTopic(_announcementsTopic).catchError((_) {}));
      }

      FirebaseMessaging.onMessage.listen(_showForeground);
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _handleTarget(m.data['target'] as String?));
      final initial = await messaging.getInitialMessage();
      if (initial != null) _pendingTarget = initial.data['target'] as String?;

      // Opening the app = the customer has seen it: clear the pop-ups in the
      // notification shade and reset the unread count.
      _lifecycle = AppLifecycleListener(onResume: () => unawaited(clearUnread()));

      messaging.onTokenRefresh.listen((t) {
        _token = t;
        _saveToken();
      });
      FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null) _saveToken();
      });
      _token = await messaging.getToken();
      unawaited(_saveToken());
    } catch (e) {
      debugPrint('Push setup skipped: $e');
    }
  }

  /// The welcome gate calls this once the app has landed on its first real
  /// screen, so a notification that launched the app opens its screen
  /// instead of being replaced by the start-up navigation.
  void appReady({required bool signedIn}) {
    _appReady = true;
    if (signedIn) {
      unawaited(_saveToken());
      unawaited(clearUnread());
    }
    final target = _pendingTarget;
    _pendingTarget = null;
    if (target != null && signedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _go(target));
    }
  }

  /// Clears the notifications already shown in the phone's notification
  /// shade and resets the unread count that the server puts on the app icon.
  Future<void> clearUnread() async {
    if (!_supported) return;
    try {
      await _local.cancelAll();
    } catch (_) {}
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'unreadPush': 0}).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  /// Profile > Notifications switch. Off = no pop-ups (the server checks
  /// `users/{uid}.pushEnabled`, and the announcements topic is left).
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (_) {}
    if (!_supported) return;
    try {
      final messaging = FirebaseMessaging.instance;
      if (value) {
        await _local
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
        await messaging.subscribeToTopic(_announcementsTopic);
      } else {
        await messaging.unsubscribeFromTopic(_announcementsTopic);
      }
    } catch (e) {
      debugPrint('Updating push topic failed: $e');
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'pushEnabled': value});
    } catch (e) {
      debugPrint('Saving push preference failed: $e');
    }
  }

  /// Saves this phone's token on the signed-in customer's profile so the
  /// Cloud Functions know where to send. Uses `update` so it never creates
  /// a half-empty profile for someone still registering.
  Future<void> _saveToken() async {
    // A brand-new account's profile doc may not exist yet at this moment
    // (registration is still writing it), so retry a few times instead of
    // giving up — otherwise that phone would never get a notification.
    const delays = [Duration.zero, Duration(seconds: 3), Duration(seconds: 10), Duration(seconds: 30)];
    for (final d in delays) {
      if (d > Duration.zero) await Future<void>.delayed(d);
      final uid = FirebaseAuth.instance.currentUser?.uid;
      var token = _token;
      if (uid == null) return;
      if (token == null) {
        try {
          token = _token = await FirebaseMessaging.instance.getToken();
        } catch (_) {}
        if (token == null) continue;
      }
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'fcmTokens': FieldValue.arrayUnion([token]),
          'pushEnabled': _enabled,
        });
        return;
      } catch (e) {
        debugPrint('Saving push token failed (will retry): $e');
      }
    }
  }

  /// Call before signing out so a logged-out phone stops getting that
  /// person's notifications.
  Future<void> removeToken() async {
    if (!_supported) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final token = _token ?? await FirebaseMessaging.instance.getToken().catchError((_) => null);
    if (uid == null || token == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'fcmTokens': FieldValue.arrayRemove([token])}).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  /// A push that arrives while the app is open (booking approved / declined,
  /// a staff reply, an announcement…) pops up at the top of the app for
  /// 5 seconds — tap it to jump to the booking, chat or announcement.
  /// Neither Android nor iOS draw their own banner in the foreground, so
  /// we draw this one ourselves. If the app isn't ready to draw it yet,
  /// Android falls back to a normal system notification.
  Future<void> _showForeground(RemoteMessage m) async {
    if (!_enabled) return;
    final n = m.notification;
    if (n == null) return;
    final target = (m.data['target'] as String?) ?? '';
    final overlay = navigatorKey.currentState?.overlay;

    if (overlay != null) {
      unawaited(HapticFeedback.mediumImpact());
      if (defaultTargetPlatform == TargetPlatform.android) SystemSound.play(SystemSoundType.alert);
      final icon = switch (target) {
        'bookings' => Icons.event_available_rounded,
        'messages' => Icons.chat_bubble_rounded,
        'announcements' => Icons.campaign_rounded,
        _ => Icons.notifications_active_rounded,
      };
      TopAlert.show(
        null,
        overlay: overlay,
        title: (n.title == null || n.title!.trim().isEmpty) ? 'Memoriae Photobooth' : n.title!.trim(),
        message: n.body ?? '',
        accent: AppColors.accent,
        icon: icon,
        actionLabel: 'View',
        onAction: target.isEmpty ? null : () => _handleTarget(target),
      );
      return;
    }

    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _local.show(
      m.hashCode,
      n.title,
      n.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.max,
          priority: Priority.high,
          icon: 'ic_stat_memoriae',
          playSound: true,
          sound: RawResourceAndroidNotificationSound(_soundFile),
          enableVibration: true,
        ),
      ),
      payload: m.data['target'] as String?,
    );
  }

  void _handleTarget(String? target) {
    if (target == null || target.isEmpty) return;
    if (!_appReady) {
      _pendingTarget = target;
      return;
    }
    _go(target);
  }

  void _go(String target) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    switch (target) {
      case 'messages':
        nav.pushNamedAndRemoveUntil('/messages', (_) => false);
        break;
      case 'announcements':
        nav.pushNamedAndRemoveUntil('/announcements', (_) => false);
        break;
      case 'bookings':
        nav.pushNamedAndRemoveUntil('/', (_) => false);
        nav.push(MaterialPageRoute(builder: (_) => const MyBookingsScreen()));
        break;
    }
  }
}
