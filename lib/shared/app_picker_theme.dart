import 'package:flutter/material.dart';

/// One shared look for every calendar (`showDatePicker`) and clock
/// (`showTimePicker`) dialog in the User, Staff and Admin apps.
///
/// Material 3's default `ColorScheme.fromSeed` tints these dialogs with the
/// maroon seed color, which reads as a pale pink surface. This forces a plain
/// white (or dark-grey in dark mode) card with no tint, a soft rounded shape,
/// a maroon selected day, and a quiet outlined "today" marker.
///
/// Usage — add to each `ThemeData(...)`:
///   datePickerTheme: AppPickerTheme.date(accent: AppColors.accent, dark: false),
///   timePickerTheme: AppPickerTheme.time(accent: AppColors.accent, dark: false),
class AppPickerTheme {
  AppPickerTheme._();

  static const Color _lightText = Color(0xFF1A1A1A);
  static const Color _lightMuted = Color(0xFFA8A29E);
  static const Color _lightSecondary = Color(0xFF78716C);
  static const Color _lightDivider = Color(0xFFE7E5E4);
  static const Color _lightFill = Color(0xFFF4F4F4);

  static const Color _darkBg = Color(0xFF262220);
  static const Color _darkText = Color(0xFFF5F0EC);
  static const Color _darkMuted = Color(0xFF8B8481);
  static const Color _darkSecondary = Color(0xFFB9B2AE);
  static const Color _darkDivider = Color(0xFF34302E);
  static const Color _darkFill = Color(0xFF2E2A28);

  static DatePickerThemeData date({
    required Color accent,
    required bool dark,
    Color onAccent = Colors.white,
    Color? darkBg,
  }) {
    final bg = dark ? (darkBg ?? _darkBg) : Colors.white;
    final text = dark ? _darkText : _lightText;
    final muted = dark ? _darkMuted : _lightMuted;
    final secondary = dark ? _darkSecondary : _lightSecondary;
    final divider = dark ? _darkDivider : _lightDivider;

    return DatePickerThemeData(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      dividerColor: divider,

      // Header ("Select your birthdate" / big date / pencil icon)
      headerBackgroundColor: bg,
      headerForegroundColor: text,
      headerHelpStyle: TextStyle(fontSize: 12, letterSpacing: 0.4, fontWeight: FontWeight.w500, color: secondary),
      headerHeadlineStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: text),

      // Weekday letters (S M T W T F S) and day numbers
      weekdayStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: secondary),
      dayStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return onAccent;
        if (states.contains(WidgetState.disabled)) return muted.withValues(alpha: 0.55);
        return text;
      }),
      dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return accent;
        return Colors.transparent;
      }),
      dayOverlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) return accent.withValues(alpha: 0.14);
        if (states.contains(WidgetState.hovered)) return accent.withValues(alpha: 0.08);
        if (states.contains(WidgetState.focused)) return accent.withValues(alpha: 0.10);
        return null;
      }),

      // Today: maroon text + thin maroon ring (no fill) until it's selected.
      todayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return onAccent;
        return accent;
      }),
      todayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return accent;
        return Colors.transparent;
      }),
      todayBorder: BorderSide(color: accent.withValues(alpha: 0.55), width: 1),

      // Year list
      yearStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      yearForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return onAccent;
        if (states.contains(WidgetState.disabled)) return muted.withValues(alpha: 0.55);
        return text;
      }),
      yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return accent;
        return Colors.transparent;
      }),
      yearOverlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) return accent.withValues(alpha: 0.14);
        if (states.contains(WidgetState.hovered)) return accent.withValues(alpha: 0.08);
        return null;
      }),

      // Range picker (not used today, kept consistent in case it is)
      rangePickerBackgroundColor: bg,
      rangePickerSurfaceTintColor: Colors.transparent,
      rangeSelectionBackgroundColor: accent.withValues(alpha: 0.12),

      // Cancel = quiet text, OK = solid maroon pill
      cancelButtonStyle: TextButton.styleFrom(
        foregroundColor: secondary,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      ),
      confirmButtonStyle: TextButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onAccent,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }

  static TimePickerThemeData time({
    required Color accent,
    required bool dark,
    Color onAccent = Colors.white,
    Color? darkBg,
  }) {
    final bg = dark ? (darkBg ?? _darkBg) : Colors.white;
    final text = dark ? _darkText : _lightText;
    final secondary = dark ? _darkSecondary : _lightSecondary;
    final divider = dark ? _darkDivider : _lightDivider;
    final fill = dark ? _darkFill : _lightFill;

    return TimePickerThemeData(
      backgroundColor: bg,
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      helpTextStyle: TextStyle(fontSize: 12, letterSpacing: 0.4, fontWeight: FontWeight.w500, color: secondary),
      entryModeIconColor: secondary,

      // Hour / minute boxes
      hourMinuteShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      hourMinuteColor: WidgetStateColor.resolveWith((states) {
        return states.contains(WidgetState.selected) ? accent.withValues(alpha: 0.12) : fill;
      }),
      hourMinuteTextColor: WidgetStateColor.resolveWith((states) {
        return states.contains(WidgetState.selected) ? accent : text;
      }),

      // AM / PM toggle
      dayPeriodShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      dayPeriodBorderSide: BorderSide(color: divider),
      dayPeriodColor: WidgetStateColor.resolveWith((states) {
        return states.contains(WidgetState.selected) ? accent.withValues(alpha: 0.12) : Colors.transparent;
      }),
      dayPeriodTextColor: WidgetStateColor.resolveWith((states) {
        return states.contains(WidgetState.selected) ? accent : secondary;
      }),

      // Clock dial
      dialBackgroundColor: fill,
      dialHandColor: accent,
      dialTextColor: WidgetStateColor.resolveWith((states) {
        return states.contains(WidgetState.selected) ? onAccent : text;
      }),

      cancelButtonStyle: TextButton.styleFrom(
        foregroundColor: secondary,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      ),
      confirmButtonStyle: TextButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onAccent,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}
