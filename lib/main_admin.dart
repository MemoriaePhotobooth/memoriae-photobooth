import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'admin/admin_app.dart';
import 'admin/services/admin_settings.dart';

/// Run just the Admin app directly, in its own terminal:
///   flutter run -t lib/main_admin.dart -d chrome
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await AdminSettings.load();
  runApp(const AdminApp());
}