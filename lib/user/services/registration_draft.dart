import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the registration form's typed details across a page refresh (web)
/// or an app restart.
///
/// The password and confirm password are never stored. They are always
/// re-entered, so no secret sits in browser or device storage.
class RegistrationDraft {
  RegistrationDraft._();

  static const _key = 'registration_draft_v1';

  static Future<Map<String, dynamic>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return {};
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(Map<String, dynamic> draft) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(draft));
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
