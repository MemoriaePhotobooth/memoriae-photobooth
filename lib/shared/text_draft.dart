import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps what someone typed into a form across a page refresh (web) or an
/// app restart, until the form is submitted.
///
/// Use it only for fields that are safe to store. Never pass a password or
/// other secret here.
///
/// Usage in a State:
///   late final TextDraft _draft;
///   initState: _draft = TextDraft('my_form_v1', {'name': _nameController, ...})
///              _draft.restore(() { if (mounted) setState(() {}); });
///   on success: await _draft.clear();
class TextDraft {
  TextDraft(this.storageKey, this.fields);

  final String storageKey;
  final Map<String, TextEditingController> fields;

  bool _restoring = false;
  bool _attached = false;

  /// Loads the saved values into any empty fields, then starts saving changes.
  /// [onRestored] runs after values are put back, so the screen can rebuild.
  Future<void> restore(VoidCallback onRestored) async {
    _attach();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      _restoring = true;
      try {
        for (final entry in fields.entries) {
          final value = decoded[entry.key];
          if (value is String && entry.value.text.isEmpty) {
            entry.value.text = value;
          }
        }
      } finally {
        _restoring = false;
      }
      onRestored();
    } catch (_) {}
  }

  /// Removes the saved draft. Call after the form is successfully submitted.
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
    } catch (_) {}
  }

  void _attach() {
    if (_attached) return;
    _attached = true;
    for (final c in fields.values) {
      c.addListener(_onChanged);
    }
  }

  void _onChanged() {
    if (_restoring) return;
    // Read the values now, before any await, so a quick edit isn't lost.
    final values = {for (final e in fields.entries) e.key: e.value.text};
    _persist(values);
  }

  Future<void> _persist(Map<String, String> values) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, jsonEncode(values));
    } catch (_) {}
  }
}
