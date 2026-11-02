import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'staff/services/staff_settings.dart';
import 'staff/staff_app.dart';

/// Run just the Staff app directly, in its own terminal:
///   flutter run -t lib/main_staff.dart -d chrome
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await StaffSettings.load();
  runApp(const StaffApp());
}
