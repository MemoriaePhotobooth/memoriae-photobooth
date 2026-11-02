import 'package:flutter/material.dart';
import '../services/admin_push_service.dart';
import '../services/admin_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import 'admin_dashboard_screen.dart';
import 'admin_login_screen.dart';

/// Root of this app (see main.dart). Checks the real Firebase Auth session
/// (and the `admins/{uid}` record); if already signed in as an admin, skip
/// straight to the dashboard, otherwise show the login screen.
class AdminGate extends StatelessWidget {
  const AdminGate({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AdminService.instance.isCurrentUserAdmin().then((ok) {
        if (ok) AdminPushService.register();
        return ok;
      }),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: AppPalette.bg(context),
            body: const Center(child: CircularProgressIndicator(color: AppColors.accent)),
          );
        }
        return (snapshot.data ?? false) ? const AdminDashboardScreen() : const AdminLoginScreen();
      },
    );
  }
}
