import 'package:flutter/material.dart';

/// Simple app-wide theme toggle read by `main.dart` and flipped from the
/// Profile screen's Dark Mode switch.
///
/// This is in-memory only for now — it resets on a full app restart.
/// Persisting the choice across restarts would need a storage package
/// (e.g. shared_preferences); left as a follow-up since it's a new
/// dependency the project doesn't currently have.
class ThemeController {
  ThemeController._();

  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.light);

  static bool get isDark => mode.value == ThemeMode.dark;

  static void setDark(bool dark) {
    mode.value = dark ? ThemeMode.dark : ThemeMode.light;
  }
}
