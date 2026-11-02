import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/staff_push_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import 'staff_dashboard_screen.dart';
import 'staff_login_screen.dart';

/// Root of this app (see main.dart). Checks the real Firebase Auth session
/// (and the `staff/{uid}` record); if already signed in as staff, skip
/// straight to the dashboard, otherwise show the login screen.
class StaffGate extends StatelessWidget {
  const StaffGate({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AuthService.instance.isCurrentUserStaff().then((ok) {
        if (ok) StaffPushService.register();
        return ok;
      }),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: AppPalette.bg(context),
            body: const Center(child: CircularProgressIndicator(color: AppColors.accent)),
          );
        }
        return (snapshot.data ?? false) ? const StaffDashboardScreen() : const StaffLoginScreen();
      },
    );
  }
}
