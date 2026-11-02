import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Context-aware color roles used throughout the app so the same widgets
/// work in both light and dark mode. `AppColors` keeps the flat brand
/// constants (accent, the raw stone/grey scale); this layer picks the
/// right one — or a dark-mode equivalent — based on `Theme.of(context).brightness`.
class AppPalette {
  AppPalette._();

  static bool _isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

  /// Page/canvas background.
  static Color bg(BuildContext context) => _isDark(context) ? const Color(0xFF121212) : Colors.white;

  /// Muted "chip"/section background (was the flat `#F4F4F4` everywhere).
  static Color surface(BuildContext context) => _isDark(context) ? const Color(0xFF1E1E1E) : AppColors.surfaceGrey;

  /// Elevated card background (was hardcoded `Colors.white`).
  static Color cardBg(BuildContext context) => _isDark(context) ? const Color(0xFF262220) : Colors.white;

  static Color textPrimary(BuildContext context) => _isDark(context) ? const Color(0xFFF5F0EC) : AppColors.stone900;

  static Color textSecondary(BuildContext context) => _isDark(context) ? const Color(0xFFB9B2AE) : AppColors.stone500;

  static Color textMuted(BuildContext context) => _isDark(context) ? const Color(0xFF8B8481) : AppColors.stone400;

  static Color divider(BuildContext context) => _isDark(context) ? const Color(0xFF34302E) : AppColors.stone200;

  /// iOS "inset grouped" page background (system grouped grey).
  static Color groupedBg(BuildContext context) => _isDark(context) ? const Color(0xFF000000) : const Color(0xFFF2F2F7);

  /// Card that sits on [groupedBg].
  static Color groupedCard(BuildContext context) => _isDark(context) ? const Color(0xFF1C1C1E) : Colors.white;

  /// Search-field / secondary-control fill on [groupedBg].
  static Color fill(BuildContext context) => _isDark(context) ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);

  /// Hairline separator.
  static Color separator(BuildContext context) => _isDark(context) ? const Color(0xFF38383A) : const Color(0xFFE5E5EA);

  /// Translucent glass background for the floating bottom nav.
  static Color navGlass(BuildContext context) =>
      _isDark(context) ? const Color(0xFF1E1E1E).withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.75);
}