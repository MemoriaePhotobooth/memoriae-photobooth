import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'admin/admin_app.dart';
import 'firebase_options.dart';
import 'staff/staff_app.dart';
import 'user/services/push_notification_service.dart';
import 'user/user_app.dart';

/// Single entrypoint for the combined Memoriae Photobooth bundle.
///
/// This launcher shows a role picker. Each button opens one of the three
/// original standalone apps (Admin, Staff, User/customer) as a full-screen
/// nested app. The Staff and User apps share one Firebase project's
/// `bookings` Firestore collection and Storage bucket for receipts, so
/// Firebase is initialized once here before any of them mount.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[startup] Flutter error: ${details.exceptionAsString()}');
  };
  // Guarded so a Firebase/push failure can't stop the app from opening.
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
  runApp(const LauncherApp());
}

class LauncherApp extends StatelessWidget {
  const LauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Memoriae',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6E1B1E)),
        fontFamily: 'Roboto',
      ),
      initialRoute: '/',
      // Each role also has its own direct URL so it can be opened, bookmarked,
      // or shared without going through the picker screen first:
      //   yoursite.com/#/user   -> customer app
      //   yoursite.com/#/staff  -> staff app
      //   yoursite.com/#/admin  -> admin app
      routes: {
        '/': (context) => const RoleSelectorScreen(),
        '/user': (context) => const UserApp(),
        '/staff': (context) => const StaffApp(),
        '/admin': (context) => const AdminApp(),
      },
    );
  }
}

class RoleSelectorScreen extends StatelessWidget {
  const RoleSelectorScreen({super.key});

  static const _accent = Color(0xFF6E1B1E);

  void _open(BuildContext context, String routeName) {
    Navigator.of(context).pushNamed(routeName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.photo_camera_outlined, size: 64, color: _accent),
                  const SizedBox(height: 16),
                  const Text(
                    'Memoriae Photobooth',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Choose which app to open',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Color(0xFF78716C)),
                  ),
                  const SizedBox(height: 40),
                  _RoleButton(
                    label: 'User / Customer App',
                    subtitle: 'Book a photobooth, rent a camera',
                    icon: Icons.person_outline,
                    onTap: () => _open(context, '/user'),
                  ),
                  const SizedBox(height: 16),
                  _RoleButton(
                    label: 'Staff App',
                    subtitle: 'Day-to-day bookings & operations',
                    icon: Icons.badge_outlined,
                    onTap: () => _open(context, '/staff'),
                  ),
                  const SizedBox(height: 16),
                  _RoleButton(
                    label: 'Admin App',
                    subtitle: 'Staff management, pricing, dashboard',
                    icon: Icons.admin_panel_settings_outlined,
                    onTap: () => _open(context, '/admin'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleButton extends StatelessWidget {
  const _RoleButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  static const _accent = Color(0xFF6E1B1E);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD1D1D1)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: _accent),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF78716C))),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFFA8A29E)),
            ],
          ),
        ),
      ),
    );
  }
}
