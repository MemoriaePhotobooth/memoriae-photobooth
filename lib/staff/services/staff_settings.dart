import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/theme_controller.dart';

/// Staff-side preferences, remembered across app restarts with
/// `shared_preferences` (already a project dependency):
///
///  * [notifyNewBookings] — pop up an alert when a booking needs approval.
///  * [defaultPayment] — payment method ('cash' | 'gcash') pre-selected in
///    the POS and walk-in screens.
///  * Dark mode — persisted by listening to [ThemeController.mode], so every
///    place that toggles it (header, settings) is remembered with no extra
///    wiring.
///
/// Call [load] once at startup (main_staff.dart does; the dashboard also
/// calls it as a harmless fallback — it only runs once).
class StaffSettings {
  StaffSettings._();

  static const _kNotify = 'staff_notify_new_bookings';
  static const _kPayment = 'staff_default_payment';
  static const _kDark = 'staff_dark_mode';

  static final ValueNotifier<bool> notifyNewBookings = ValueNotifier(true);
  static final ValueNotifier<String> defaultPayment = ValueNotifier('cash');

  static SharedPreferences? _prefs;
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      notifyNewBookings.value = prefs.getBool(_kNotify) ?? true;
      final pay = prefs.getString(_kPayment);
      defaultPayment.value = (pay == 'gcash') ? 'gcash' : 'cash';
      ThemeController.setDark(prefs.getBool(_kDark) ?? false);
    } catch (_) {
      // Storage unavailable — keep in-memory defaults.
    }
    ThemeController.mode.addListener(() {
      _prefs?.setBool(_kDark, ThemeController.isDark);
    });
  }

  static Future<void> setNotifyNewBookings(bool value) async {
    notifyNewBookings.value = value;
    await _prefs?.setBool(_kNotify, value);
  }

  static Future<void> setDefaultPayment(String method) async {
    defaultPayment.value = method == 'gcash' ? 'gcash' : 'cash';
    await _prefs?.setString(_kPayment, defaultPayment.value);
  }
}
