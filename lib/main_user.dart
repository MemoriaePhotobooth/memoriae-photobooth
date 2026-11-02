import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'user/services/push_notification_service.dart';
import 'user/user_app.dart';

/// Run just the User app directly, in its own terminal:
///   flutter run -t lib/main_user.dart -d chrome
///
/// Startup is guarded so that a failing Firebase or push setup does not
/// crash the app before its first screen appears. Errors are logged.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Show a readable message instead of a silent crash if a widget fails to build.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[startup] Flutter error: ${details.exceptionAsString()}');
  };

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e, st) {
    debugPrint('[startup] Firebase init failed: $e\n$st');
  }

  try {
    await PushNotificationService.instance.init();
  } catch (e, st) {
    debugPrint('[startup] Push init failed: $e\n$st');
  }

  runApp(const UserApp());
}
