import '../../shared/centered_body.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/theme_controller.dart';
import '../widgets/app_toast.dart';
import '../widgets/delete_account_dialog.dart';
import 'help_support_screen.dart';
import 'info_pages.dart';
import 'user_onboarding_screen.dart';

/// Settings for the customer, grouped like the Settings screens in Facebook
/// and Instagram: preferences first, then help and legal pages, then the
/// account actions (Log Out and Delete account) at the bottom.
class UserSettingsScreen extends StatefulWidget {
  const UserSettingsScreen({super.key});

  @override
  State<UserSettingsScreen> createState() => _UserSettingsScreenState();
}

class _UserSettingsScreenState extends State<UserSettingsScreen> {
  static const Color _danger = Color(0xFFB3261E);

  bool _notificationsOn = PushNotificationService.instance.enabled;
  bool _loggingOut = false;

  void _setNotifications(bool v) {
    setState(() => _notificationsOn = v);
    PushNotificationService.instance.setEnabled(v);
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Log out?"),
        content: const Text("You'll need to sign in again to manage your bookings."),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text("Log Out", style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loggingOut = true);
    await AuthService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (route) => false);
  }

  Future<void> _deleteAccount() async {
    final deleted = await showDeleteAccountDialog(context);
    if (deleted != true || !mounted) return;
    AppToast.show(context, 'Your account has been deleted.');
    Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (route) => false);
  }

  void _open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  Widget _section(String title, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppPalette.textMuted(context)),
            ),
          ),
          Container(
            decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: Column(children: rows),
          ),
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String label,
    Color? color,
    String? hint,
    Widget? trailing,
    VoidCallback? onTap,
    bool busy = false,
    bool isLast = false,
  }) {
    final tint = color ?? AppColors.accent;
    final textColor = color ?? AppPalette.textPrimary(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: isLast ? null : Border(bottom: BorderSide(color: AppPalette.divider(context))),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: busy
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: tint),
                      )
                    : Icon(icon, size: 18, color: tint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
              ),
              if (hint != null && hint.isNotEmpty) ...[
                Text(hint, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
                const SizedBox(width: 4),
              ],
              if (trailing != null)
                trailing
              else if (!busy && onTap != null)
                Icon(Icons.chevron_right_rounded, size: 18, color: AppPalette.textMuted(context)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = AuthService.instance.isLoggedIn;

    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Settings',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
        ),
      ),
      body: CenteredBody(child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _section('Preferences', [
            _row(
              icon: Icons.notifications_outlined,
              label: 'Notifications',
              hint: _notificationsOn ? 'On' : 'Off',
              onTap: () => _setNotifications(!_notificationsOn),
              trailing: Switch.adaptive(
                value: _notificationsOn,
                activeColor: AppColors.accent,
                onChanged: _setNotifications,
              ),
            ),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeController.mode,
              builder: (context, mode, _) {
                final isDark = mode == ThemeMode.dark;
                return _row(
                  icon: isDark ? Icons.dark_mode : Icons.dark_mode_outlined,
                  label: 'Dark Mode',
                  hint: isDark ? 'On' : 'Off',
                  onTap: () => ThemeController.setDark(!isDark),
                  trailing: Switch.adaptive(
                    value: isDark,
                    activeColor: AppColors.accent,
                    onChanged: (v) => ThemeController.setDark(v),
                  ),
                  isLast: true,
                );
              },
            ),
          ]),

          _section('Help and legal', [
            _row(
              icon: Icons.school_outlined,
              label: 'App Tutorial',
              onTap: () => _open(const UserOnboardingScreen(replay: true)),
            ),
            _row(
              icon: Icons.help_outline_rounded,
              label: 'Help & Support',
              onTap: () => _open(const HelpSupportScreen()),
            ),
            _row(
              icon: Icons.description_outlined,
              label: 'Terms of Service',
              onTap: () => _open(const PolicyScreen(title: 'Terms of Service', sections: kTermsOfServiceSections)),
            ),
            _row(
              icon: Icons.shield_outlined,
              label: 'Privacy Policy',
              onTap: () => _open(const PolicyScreen(
                title: 'Privacy Policy',
                sections: kPrivacyPolicySections,
                lastUpdated: kPrivacyPolicyLastUpdated,
              )),
              isLast: true,
            ),
          ]),

          if (loggedIn)
            _section('Account', [
              _row(
                icon: Icons.logout_rounded,
                label: _loggingOut ? 'Logging out…' : 'Log Out',
                color: AppColors.accent,
                onTap: _loggingOut ? null : _logout,
                busy: _loggingOut,
              ),
              _row(
                icon: Icons.delete_outline_rounded,
                label: 'Delete account',
                color: _danger,
                onTap: _loggingOut ? null : _deleteAccount,
                isLast: true,
              ),
            ])
          else
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'Log in to manage your account.',
                style: TextStyle(fontSize: 13, color: AppPalette.textSecondary(context)),
              ),
            ),
        ],
      )),
    );
  }
}
