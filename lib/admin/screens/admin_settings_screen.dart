import 'package:flutter/material.dart';
import '../services/admin_service.dart';
import '../services/admin_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/theme_controller.dart';
import '../widgets/downpayment_settings_card.dart';

/// Version shown in About — keep in sync with `version:` in pubspec.yaml.
const String _kAppVersion = '1.0.0';

/// Admin settings: appearance, notifications, business info and GCash
/// details, payments, security, help and about. Preferences are remembered across restarts via
/// [AdminSettings]. Opened from the sidebar's Settings item or the
/// Profile page.
class AdminSettingsScreen extends StatelessWidget {
  final VoidCallback onChangePassword;

  const AdminSettingsScreen({super.key, required this.onChangePassword});

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Help & Support"),
        content: const Text(
          "Forgot your password? Tap \"Forgot password?\" on the sign-in screen and we'll email you a reset link.\n\n"
          "You can change your own password anytime under Settings → Security.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text("Close", style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = AdminService.instance.currentEmail ?? '';
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionLabel(context, "APPEARANCE"),
              _card(context, [
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: ThemeController.mode,
                  builder: (context, mode, _) {
                    final isDark = mode == ThemeMode.dark;
                    return _row(
                      context,
                      icon: isDark ? Icons.dark_mode : Icons.dark_mode_outlined,
                      label: "Dark mode",
                      hint: isDark ? "On" : "Off",
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
              const SizedBox(height: 22),
              _sectionLabel(context, "NOTIFICATIONS"),
              _card(context, [
                ValueListenableBuilder<bool>(
                  valueListenable: AdminSettings.notifyNewBookings,
                  builder: (context, on, _) {
                    return _row(
                      context,
                      icon: on ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                      label: "New booking alerts",
                      hint: "Pop up when a booking needs approval",
                      onTap: () => AdminSettings.setNotifyNewBookings(!on),
                      trailing: Switch.adaptive(
                        value: on,
                        activeColor: AppColors.accent,
                        onChanged: (v) => AdminSettings.setNotifyNewBookings(v),
                      ),
                      isLast: true,
                    );
                  },
                ),
              ]),
              const SizedBox(height: 22),
              _sectionLabel(context, "PAYMENTS"),
              _card(context, const [DownpaymentSettingsCard()]),
              const SizedBox(height: 22),
              _sectionLabel(context, "SECURITY"),
              _card(context, [
                _row(
                  context,
                  icon: Icons.lock_outline,
                  label: "Change password",
                  hint: "",
                  onTap: onChangePassword,
                  isLast: true,
                ),
              ]),
              const SizedBox(height: 22),
              _sectionLabel(context, "SUPPORT"),
              _card(context, [
                _row(
                  context,
                  icon: Icons.help_outline,
                  label: "Help & Support",
                  hint: "",
                  onTap: () => _showHelp(context),
                ),
                _row(
                  context,
                  icon: Icons.info_outline,
                  label: "About",
                  hint: "Memoriae Admin Portal · v$_kAppVersion",
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: "Memoriae Admin Portal",
                    applicationVersion: _kAppVersion,
                    applicationLegalese: "Memoriae Photobooth",
                  ),
                  isLast: true,
                ),
              ]),
              if (email.isNotEmpty) ...[
                const SizedBox(height: 22),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    "Signed in as $email",
                    style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: AppPalette.textMuted(context)),
      ),
    );
  }

  Widget _card(BuildContext context, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.divider(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String hint,
    required VoidCallback onTap,
    Widget? trailing,
    bool isLast = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: trailing != null ? 8 : 15),
          decoration: BoxDecoration(border: isLast ? null : Border(bottom: BorderSide(color: AppPalette.divider(context)))),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: trailing != null && hint.isNotEmpty
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context))),
                          const SizedBox(height: 2),
                          Text(hint, style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
                        ],
                      )
                    : Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context))),
              ),
              if (trailing != null)
                trailing
              else ...[
                if (hint.isNotEmpty) ...[
                  Flexible(
                    child: Text(hint, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
                  ),
                  const SizedBox(width: 4),
                ],
                Icon(Icons.chevron_right, size: 18, color: AppPalette.textMuted(context)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
