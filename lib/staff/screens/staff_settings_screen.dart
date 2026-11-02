import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/staff_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/theme_controller.dart';

/// Version shown in About — keep in sync with `version:` in pubspec.yaml.
const String _kAppVersion = '1.0.0';

/// Staff settings: appearance, notifications, POS defaults, security,
/// help and about. Preferences are remembered across restarts via
/// [StaffSettings]. Opened from the sidebar's Settings item or the
/// Profile page.
class StaffSettingsScreen extends StatelessWidget {
  final VoidCallback onChangePassword;

  const StaffSettingsScreen({super.key, required this.onChangePassword});

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Help & Support"),
        content: const Text(
          "Forgot your password? Tap \"Forgot password?\" on the sign-in screen and we'll email you a reset link. "
          "Need your name, role or access changed? Ask your admin.\n\n"
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
    final email = AuthService.instance.currentEmail ?? '';
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
                  valueListenable: StaffSettings.notifyNewBookings,
                  builder: (context, on, _) {
                    return _row(
                      context,
                      icon: on ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                      label: "New booking alerts",
                      hint: "Pop up when a booking needs approval",
                      onTap: () => StaffSettings.setNotifyNewBookings(!on),
                      trailing: Switch.adaptive(
                        value: on,
                        activeColor: AppColors.accent,
                        onChanged: (v) => StaffSettings.setNotifyNewBookings(v),
                      ),
                      isLast: true,
                    );
                  },
                ),
              ]),
              const SizedBox(height: 22),
              _sectionLabel(context, "POINT OF SALE"),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppPalette.cardBg(context),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppPalette.divider(context)),
                ),
                child: ValueListenableBuilder<String>(
                  valueListenable: StaffSettings.defaultPayment,
                  builder: (context, method, _) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.payments_outlined, size: 18, color: AppColors.accent),
                            const SizedBox(width: 12),
                            Text("Default payment method", style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context))),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(left: 30),
                          child: Text("Pre-selected in POS and walk-in bookings.", style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _choice(context, "Cash", Icons.payments_outlined, method == 'cash', () => StaffSettings.setDefaultPayment('cash'))),
                            const SizedBox(width: 10),
                            Expanded(child: _choice(context, "GCash", Icons.qr_code_2_rounded, method == 'gcash', () => StaffSettings.setDefaultPayment('gcash'))),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
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
                  hint: "Memoriae Staff Portal · v$_kAppVersion",
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: "Memoriae Staff Portal",
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

  Widget _choice(BuildContext context, String label, IconData icon, bool selected, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentTint(0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.accent : AppPalette.divider(context), width: selected ? 1.4 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? AppColors.accent : AppPalette.textMuted(context)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: selected ? AppColors.accent : AppPalette.textSecondary(context)),
              ),
            ),
          ],
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
