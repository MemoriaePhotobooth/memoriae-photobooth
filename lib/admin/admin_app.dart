import 'package:flutter/material.dart';
import '../shared/top_toast.dart';
import '../shared/app_picker_theme.dart';
import 'theme/app_colors.dart';
import 'theme/theme_controller.dart';
import 'screens/admin_welcome_screen.dart';

/// Firebase-backed build — AdminService checks against a real `admins/{uid}`
/// Firestore collection, and BookingRepository reads/writes the same live
/// `bookings` collection the User and Staff apps use. Requires
/// `Firebase.initializeApp()` to already have run before this widget mounts
/// (see `main.dart` for the combined launcher, or `main_admin.dart` for
/// running this app standalone).
class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, themeMode, _) {
        return MaterialApp(
          navigatorKey: TopToast.navigatorKey,
          title: 'Memoriae Admin',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: Colors.white,
            colorScheme: ColorScheme.fromSeed(seedColor: AppColors.accent, primary: AppColors.accent),
            fontFamily: 'Roboto',
            // Material 3's default ColorScheme.fromSeed tints elevated
            // surfaces (dialogs included) with the seed color, which on
            // this maroon seed reads as a pale pink dialog background.
            // Force plain white + no tint + a consistently rounded shape
            // instead, so every AlertDialog/dialog in the app (Staff,
            // Pricing, delete confirmations, change password, etc.) looks
            // like a clean modern card instead of a tinted one.
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
            cardTheme: CardThemeData(
              elevation: 0,
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              margin: EdgeInsets.zero,
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
            cardTheme: CardThemeData(
              elevation: 0,
              color: const Color(0xFF262220),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              margin: EdgeInsets.zero,
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
          home: const AdminWelcomeScreen(),
        );
      },
    );
  }
}