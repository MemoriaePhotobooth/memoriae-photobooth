import 'package:flutter/material.dart';
import '../shared/app_picker_theme.dart';
import 'models/booth_package.dart';
import 'models/camera_rental.dart';
import 'theme/app_colors.dart';
import 'theme/theme_controller.dart';
import 'widgets/app_layout_shell.dart';
import 'screens/home_screen.dart';
import 'screens/photobooth_booking_screen.dart';
import 'screens/camera_rental_screen.dart';
import 'screens/user_calendar_screen.dart';
import 'screens/user_announcements_screen.dart';
import 'screens/user_messages_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/my_bookings_screen.dart';
import 'screens/user_splash_screen.dart';
import 'screens/user_entry_screen.dart';
import 'screens/user_onboarding_screen.dart';
import 'services/auth_service.dart';
import 'services/push_notification_service.dart';

/// Firebase-backed build — AuthService uses Firebase Authentication and
/// BookingRepository reads/writes the live `bookings` Firestore collection
/// shared with the Staff and Admin apps. Requires `Firebase.initializeApp()`
/// to have run first (see `main.dart` or `main_user.dart`).
class UserApp extends StatelessWidget {
  const UserApp({super.key});

  /// Builds each tab's content wrapped in the shared `AppLayoutShell`
  /// (phone-frame chrome + floating bottom nav), and hands it back with a
  /// zero-duration transition so switching tabs feels instant rather than
  /// like a full page push — closer to how `<Outlet/>` swaps content in
  /// the React version without animating the surrounding layout.
  Route<dynamic> _buildTabRoute(RouteSettings settings, Widget content, int tabIndex) {
    return PageRouteBuilder(
      settings: settings,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) {
        return AppLayoutShell(currentIndex: tabIndex, child: content);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'Memoriae',
          navigatorKey: PushNotificationService.navigatorKey,
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: Colors.white,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.accent,
              primary: AppColors.accent,
              onPrimary: AppColors.onAccent,
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              margin: EdgeInsets.zero,
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 8,
            ),
            datePickerTheme: AppPickerTheme.date(accent: AppColors.accentOnLight, dark: false, onAccent: Colors.white),
            timePickerTheme: AppPickerTheme.time(accent: AppColors.accentOnLight, dark: false, onAccent: Colors.white),
            snackBarTheme: SnackBarThemeData(
              backgroundColor: const Color(0xFF2E2A26),
              contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 6,
              actionTextColor: const Color(0xFFE0B24C),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF121212),
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.accent,
              primary: AppColors.accent,
              onPrimary: AppColors.onAccent,
              brightness: Brightness.dark,
              surface: const Color(0xFF1E1E1E),
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              color: const Color(0xFF262220),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              margin: EdgeInsets.zero,
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: const Color(0xFF1E1E1E),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 8,
            ),
            datePickerTheme: AppPickerTheme.date(accent: AppColors.accent, dark: true, onAccent: Colors.white),
            timePickerTheme: AppPickerTheme.time(accent: AppColors.accent, dark: true, onAccent: Colors.white),
            snackBarTheme: SnackBarThemeData(
              backgroundColor: const Color(0xFF2E2A26),
              contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 6,
              actionTextColor: const Color(0xFFE0B24C),
            ),
          ),
          initialRoute: '/welcome',
          onGenerateRoute: (settings) {
            switch (settings.name) {
              case '/welcome':
                return MaterialPageRoute(settings: settings, builder: (_) => const _WelcomeGate());
              case '/':
                return _buildTabRoute(settings, const HomeScreen(), 0);
              case '/book':
                final intent = settings.arguments is BookingIntent ? settings.arguments as BookingIntent : null;
                return _buildTabRoute(settings, PhotoboothBookingScreen(intent: intent), 1);
              case '/rent':
                return _buildTabRoute(settings, const CameraRentalScreen(), 2);
              case '/calendar':
                return _buildTabRoute(settings, const UserCalendarScreen(), 3);
              case '/announcements':
                return _buildTabRoute(settings, const UserAnnouncementsScreen(), 4);
              case '/messages':
                final cameraRef = settings.arguments is CameraChatRef ? settings.arguments as CameraChatRef : null;
                return _buildTabRoute(settings, UserMessagesScreen(cameraRef: cameraRef), 5);
              case '/profile':
                return _buildTabRoute(settings, const ProfileScreen(), 6);
              case '/bookings':
                return _buildTabRoute(settings, const MyBookingsScreen(), 7);
              default:
                return _buildTabRoute(settings, const HomeScreen(), 0);
            }
          },
        );
      },
    );
  }
}

/// Decides what "/welcome" (the app's start route) really shows.
///
/// If the customer is still signed in (and their 30-day verification is still
/// valid) they go straight to the dashboard ("/") — so refreshing the page,
/// reopening the app or pressing Home/Back never drops a logged-in user back
/// on the login/welcome page. Only logged-out users (or guests) see the
/// welcome page. Logging out still works: it signs out first, so this gate
/// then shows the welcome page.
class _WelcomeGate extends StatefulWidget {
  const _WelcomeGate();

  @override
  State<_WelcomeGate> createState() => _WelcomeGateState();
}

class _WelcomeGateState extends State<_WelcomeGate> {
  /// The splash only plays on a cold start. Logging out (which comes back to
  /// "/welcome") skips it and goes straight to the welcome page.
  static bool _splashPlayed = false;

  late final bool _showSplash = !_splashPlayed;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    // Run the session check and the splash minimum-time together, so the
    // splash never flashes by but also never adds extra waiting on top.
    final sessionFuture = AuthService.instance.hasValidSession();
    if (_showSplash) {
      await Future.delayed(UserSplashScreen.minDuration);
    }
    final signedIn = await sessionFuture;
    _splashPlayed = true;
    if (!mounted) return;

    // First launch only: show the tutorial once before the customer continues.
    if (!await UserOnboardingScreen.hasSeen() && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const UserOnboardingScreen()),
      );
      if (!mounted) return;
    }
    if (signedIn) {
      Navigator.of(context).pushReplacementNamed('/');
    } else {
      setState(() => _checking = false);
    }
    PushNotificationService.instance.appReady(signedIn: signedIn);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: _checking
          ? (_showSplash
              ? const UserSplashScreen(key: ValueKey('splash'))
              : const Scaffold(
                  key: ValueKey('checking'),
                  backgroundColor: AppColors.brandCream,
                  body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
                ))
          : const UserEntryScreen(key: ValueKey('entry')),
    );
  }
}