import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/booth_package.dart';
import 'booking_hours.dart';
import 'booking_repository.dart';
import 'chatbot_engine.dart';

/// Calls the Google Gemini API (free tier) for questions the rule-based
/// [ChatbotEngine] couldn't answer.
///
/// Setup — the key is NOT stored in the code. Pass it when running/building:
///
///   flutter run -d chrome -t lib/main_user.dart --dart-define=GEMINI_API_KEY=your_key
///
/// (or put it in an `env.json` file and use `--dart-define-from-file=env.json`).
/// With no key, [isConfigured] is false and the bot simply stays rule-based.
///
/// Privacy: only the last few chat messages and public shop info (prices,
/// hours) are sent. Customer names, emails and bookings are never included.
class GeminiService {
  GeminiService._();

  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  /// Optional override: `--dart-define=GEMINI_MODEL=...` (or in env.json).
  static const String _configuredModel = String.fromEnvironment('GEMINI_MODEL');

  /// Google renames and retires models often, so if one returns 404 the next
  /// is tried automatically. The first one that works is remembered.
  static const List<String> _defaultModels = [
    'gemini-3.5-flash-lite',
    'gemini-3.8-flash',
    'gemini-2.5-flash-lite',
  ];
  static String? _workingModel;

  /// False for an empty key *or* the "PASTE_YOUR_KEY_HERE" placeholder, so a
  /// fresh copy of the project stays rule-based instead of calling Gemini
  /// with a key that can't work.
  static bool get isConfigured => _apiKey.isNotEmpty && !_apiKey.toUpperCase().contains('PASTE');

  /// Why the last call failed (shown in the chat in debug builds only).
  static String? lastError;

  static List<String> get _modelsToTry => <String>{
        if (_workingModel != null) _workingModel!,
        if (_configuredModel.isNotEmpty) _configuredModel,
        ..._defaultModels,
      }.toList();

  /// Returns the model's answer, or null if anything goes wrong (no key,
  /// offline, rate-limited, blocked, timeout) so the caller can fall back.
  /// [history] must end with the customer's latest question.
  static Future<String?> ask({required List<ChatMessage> history, required ChatCatalog catalog}) async {
    lastError = null;
    if (!isConfigured) {
      lastError = 'No API key loaded.';
      return null;
    }

    final contents = _buildContents(history);
    if (contents.isEmpty) {
      lastError = 'Nothing to send.';
      return null;
    }

    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': _systemPrompt(catalog)},
        ],
      },
      'contents': contents,
      'generationConfig': {'temperature': 0.3, 'maxOutputTokens': 600},
    });

    for (final model in _modelsToTry) {
      final uri = Uri.https('generativelanguage.googleapis.com', '/v1beta/models/$model:generateContent');

      http.Response res;
      try {
        res = await http
            .post(uri, headers: {'Content-Type': 'application/json', 'x-goog-api-key': _apiKey}, body: body)
            .timeout(const Duration(seconds: 12));
      } catch (e) {
        lastError = 'Request failed (${e.runtimeType}): ${_short(e.toString())}';
        debugPrint('Gemini request failed: $e');
        return null;
      }

      if (res.statusCode == 200) {
        final text = _extractText(res.body);
        if (text == null) {
          lastError = 'Gemini replied with no text (possibly blocked) on $model.';
          return null;
        }
        _workingModel = model;
        return text;
      }

      lastError = 'HTTP ${res.statusCode} on $model: ${_apiMessage(res.body)}';
      debugPrint('Gemini error: $lastError');
      // 404 = this model name was renamed/retired -> try the next one.
      // Anything else (401/403 key, 429 quota, 400 bad request) won't be
      // fixed by switching model, so stop.
      if (res.statusCode != 404) return null;
    }
    return null;
  }

  static String? _extractText(String responseBody) {
    try {
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;
      final parts = candidates.first['content']?['parts'] as List?;
      if (parts == null) return null;
      final text = parts.map((p) => (p['text'] ?? '').toString()).join().trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  static String _apiMessage(String responseBody) {
    try {
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final msg = data['error']?['message'];
      if (msg != null) return _short(msg.toString());
    } catch (_) {}
    return _short(responseBody);
  }

  static String _short(String s) {
    // Google's error text can echo the API key back (e.g. "Consumer
    // 'api_key:AQ....' has been suspended"), so never let it reach the UI.
    final redacted = s
        .replaceAll(RegExp(r'(AQ\.|AIza)[A-Za-z0-9_\-.]+'), '[key hidden]')
        .replaceAll(_apiKey.isEmpty ? '\u0000' : _apiKey, '[key hidden]');
    final one = redacted.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.length > 180 ? '${one.substring(0, 180)}...' : one;
  }

  // --------------------------------------------------------------- helpers

  /// Last few messages as Gemini turns. Gemini wants roles `user`/`model`,
  /// starting with `user`; consecutive same-role messages are merged.
  static List<Map<String, dynamic>> _buildContents(List<ChatMessage> history) {
    final recent = history.length > 7 ? history.sublist(history.length - 7) : history;

    final roles = <String>[];
    final texts = <String>[];
    for (final m in recent) {
      final role = m.fromBot ? 'model' : 'user';
      if (roles.isNotEmpty && roles.last == role) {
        texts[texts.length - 1] = '${texts.last}\n${m.text}';
      } else {
        roles.add(role);
        texts.add(m.text);
      }
    }
    while (roles.isNotEmpty && roles.first != 'user') {
      roles.removeAt(0);
      texts.removeAt(0);
    }

    return [
      for (var i = 0; i < roles.length; i++)
        {
          'role': roles[i],
          'parts': [
            {'text': texts[i]},
          ],
        },
    ];
  }

  /// Grounds the model in the shop's real data so it answers from facts
  /// instead of guessing — same data the Book / Rent screens show.
  static String _systemPrompt(ChatCatalog c) {
    final mins = BookingRepository.holdDuration.inMinutes;

    final packages = ([...c.packages]..sort((a, b) => a.price.compareTo(b.price))).map((p) {
      final feats = p.features.isEmpty ? '' : ' Includes: ${p.features.join(', ')}.';
      final dur = p.duration.isEmpty ? '' : ' (${p.duration})';
      return '- ${p.name}$dur: ${formatPeso(p.price)}.$feats';
    }).join('\n');

    final cameras = c.cameras
        .map((x) => '- ${x.name}: ${formatPeso(x.dailyRate)} / 24 hrs. ${x.description}')
        .join('\n');

    final addOns = kAddOns.map((a) => '- ${a.name}: ${formatPeso(a.price)}. ${a.description}').join('\n');

    return '''
You are the customer-support assistant inside the Memoriae Photobooth app. Memoriae offers photobooth packages for events and camera rentals. Prices are in Philippine pesos.

FACTS (the only information you may rely on):

Photobooth packages:
$packages

Camera rentals:
$cameras

Add-ons:
$addOns

Booking:
- ${BookingHours.closedMessage}
- Event time slots: ${kTimeSlots.join(', ')}.
- Steps: pick the event date and time, pin the event location on the map, choose a package (and optional add-ons), tap "Book Now & Hold Slot". The slot is held for $mins minutes while the customer uploads their GCash payment receipt.
- Payment is GCash only. To reserve a date the customer sends ${ChatbotEngine.paymentSummary(c.payment)}${c.payment.downpaymentEnabled ? '; the balance is paid on the event day' : ''}. After the receipt is uploaded, staff review it and approve the booking.
- The Calendar tab shows which dates are available or already booked.
- Booking status, balance due and refund updates are shown under My Bookings in the app. Refunds are sent to the customer's GCash (they can save a GCash refund account under Profile > Payment Methods).

RULES:
- Answer only from the FACTS above. If the answer is not there (for example cancellation or refund policy, rescheduling, discounts, studio address, service area, or travel fees), say you don't have that information and suggest tapping "Talk to staff". For questions about a specific booking's status, balance or refund, point them to My Bookings.
- Never invent prices, dates, availability, or policies.
- Reply in the same language the customer used (English, Filipino, or Taglish).
- Keep replies short: at most 3 sentences or about 60 words. Plain text only, no markdown.
- Never ask for or repeat personal or payment details.
- Stay on topic. Politely decline unrelated requests.
''';
  }
}