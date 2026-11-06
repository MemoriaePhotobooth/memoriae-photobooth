import 'package:flutter/material.dart';
import '../shared/top_toast.dart';
import '../shared/app_picker_theme.dart';
import 'theme/app_colors.dart';
import 'theme/theme_controller.dart';
import 'screens/staff_landing_screen.dart';
import 'screens/staff_dashboard_screen.dart';
import 'services/auth_service.dart';
import 'services/staff_push_service.dart';
import 'theme/app_palette.dart';

/// Firebase-backed build — sign-in uses Firebase Authentication plus a
/// `staff/{uid}` Firestore document, and the dashboard reads the live
/// `bookings` collection shared with the User and Admin apps. Requires
/// `Firebase.initializeApp()` to have run first (see `main.dart` or
/// `main_staff.dart`).
///
/// This is the Staff app — day-to-day operations only (Bookings, Camera
/// Rentals, Calendar, Feedback, Messages). For staff management and
/// pricing, see the separate `photobooth_admin_demo` project.
class StaffApp extends StatelessWidget {
  const StaffApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, themeMode, _) {
        return MaterialApp(
          navigatorKey: TopToast.navigatorKey,
          title: 'Memoriae Staff',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: Colors.white,
            colorScheme: ColorScheme.fromSeed(seedColor: AppColors.accent, primary: AppColors.accent),
            fontFamily: 'Roboto',
            // Material 3's default ColorScheme.fromSeed tints elevated
            // surfaces (dialogs, popup menus) with the seed color, which on
            // this maroon seed reads as a pale pink surface. Force plain
            // white + no tint + a consistently rounded shape instead, to
            // match the Admin app's dialogs/menus.
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
              elevation: 14,
              shadowColor: Colors.black.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              iconColor: AppColors.accent,
              titleTextStyle: TextStyle(fontFamily: 'Roboto', fontSize: 19, height: 1.25, fontWeight: FontWeight.w800, color: AppColors.stone900),
              contentTextStyle: TextStyle(fontFamily: 'Roboto', fontSize: 13.5, height: 1.45, color: const Color(0xFF57534E)),
              actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
            ),
            popupMenuTheme: PopupMenuThemeData(
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              textStyle: const TextStyle(fontSize: 13, color: AppColors.stone900),
            ),
            datePickerTheme: AppPickerTheme.date(accent: AppColors.accent, dark: false),
            timePickerTheme: AppPickerTheme.time(accent: AppColors.accent, dark: false),
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
              brightness: Brightness.dark,
            ),
            fontFamily: 'Roboto',
            cardTheme: CardThemeData(
              elevation: 0,
              color: const Color(0xFF262220),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              margin: EdgeInsets.zero,
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: const Color(0xFF262220),
              surfaceTintColor: Colors.transparent,
              elevation: 14,
              shadowColor: Colors.black.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              iconColor: AppColors.accent,
              titleTextStyle: TextStyle(fontFamily: 'Roboto', fontSize: 19, height: 1.25, fontWeight: FontWeight.w800, color: const Color(0xFFF5F0EC)),
              contentTextStyle: TextStyle(fontFamily: 'Roboto', fontSize: 13.5, height: 1.45, color: const Color(0xFFC9C2BE)),
              actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
            ),
            popupMenuTheme: PopupMenuThemeData(
              color: const Color(0xFF262220),
              surfaceTintColor: Colors.transparent,
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              textStyle: const TextStyle(fontSize: 13, color: Color(0xFFF5F0EC)),
            ),
            datePickerTheme: AppPickerTheme.date(accent: AppColors.accent, dark: true),
            timePickerTheme: AppPickerTheme.time(accent: AppColors.accent, dark: true),
            snackBarTheme: SnackBarThemeData(
              backgroundColor: const Color(0xFF2E2A26),
              contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 6,
              actionTextColor: const Color(0xFFE0B24C),
            ),
          ),
          home: const _StaffRoot(),
        );
      },
    );
  }
}

/// Start screen of the Staff app.
///
/// Refreshing the browser used to always drop you back on the landing page,
/// because that page was hard-wired as `home`. Firebase Auth already keeps the
/// session in the browser, so here we check it first: a signed-in staff member (with
/// an active `staff/{uid}` doc) goes straight to the dashboard, everyone else
/// sees the landing page. Logging out still works — the dashboard replaces
/// itself with the login screen.
class _StaffRoot extends StatefulWidget {
  const _StaffRoot();

  @override
  State<_StaffRoot> createState() => _StaffRootState();
}

class _StaffRootState extends State<_StaffRoot> {
  late final Future<bool> _check = AuthService.instance.isCurrentUserStaff().then((ok) {
    if (ok) StaffPushService.register();
    return ok;
  }).catchError((_) => false);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _check,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: AppPalette.bg(context),
            body: const Center(child: CircularProgressIndicator(color: AppColors.accent)),
          );
        }
        return (snapshot.data ?? false) ? const StaffDashboardScreen() : const StaffLandingScreen();
      },
    );
  }
}
