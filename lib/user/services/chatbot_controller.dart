import 'package:flutter/foundation.dart';

import '../models/booth_package.dart';
import '../models/camera_rental.dart';
import 'auth_service.dart';
import 'chatbot_ai.dart';
import 'chatbot_engine.dart';
import 'message_repository.dart';
import 'payment_settings_repository.dart';
import 'pricing_repository.dart';

enum HandoffResult { sent, notLoggedIn, failed }

/// Holds the chat conversation for the whole User app.
///
/// `AppLayoutShell` is rebuilt every time the customer switches tabs (each tab
/// is its own route), so the conversation can't live in a widget's `State` —
/// it would reset on every tab change. A singleton keeps it alive instead.
class ChatbotController {
  ChatbotController._();
  static final ChatbotController instance = ChatbotController._();

  static const int _maxMessages = 60;
  static const Duration _catalogTtl = Duration(minutes: 3);

  /// Keeps the free-tier quota safe: at most this many AI calls per app
  /// session, and never two within [_aiCooldown].
  static const int _maxAiCallsPerSession = 20;
  static const Duration _aiCooldown = Duration(seconds: 3);

  /// Whether the chat panel is open (vs. just the floating button).
  final ValueNotifier<bool> expanded = ValueNotifier<bool>(false);
  final ValueNotifier<List<ChatMessage>> messages = ValueNotifier<List<ChatMessage>>(const []);
  final ValueNotifier<bool> typing = ValueNotifier<bool>(false);

  String? _lastUserText;
  ChatCatalog? _catalog;
  DateTime? _catalogAt;
  int _aiCalls = 0;
  DateTime? _lastAiAt;

  void open() {
    expanded.value = true;
    if (messages.value.isEmpty) _add(ChatbotEngine.greeting());
  }

  void close() => expanded.value = false;

  /// Clears the conversation and starts over with the greeting.
  void reset() {
    _lastUserText = null;
    messages.value = const [];
    _add(ChatbotEngine.greeting());
  }

  Future<void> send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || typing.value) return;

    _add(ChatMessage.user(text));
    typing.value = true;

    final catalog = await _loadCatalog();
    // Tiny pause so the answer doesn't feel instant/robotic.
    await Future<void>.delayed(const Duration(milliseconds: 350));

    final reply = ChatbotEngine.reply(text, catalog);
    if (!reply.handoffRequest) _lastUserText = text;

    var answer = reply.message;

    // No rule matched -> ask Gemini (if a key was provided). If that fails
    // for any reason, the normal "I'm not sure" fallback is shown instead.
    if (reply.isFallback) {
      final ai = await _askAi(catalog);
      if (ai != null) {
        answer = ChatMessage(
          fromBot: true,
          text: ai,
          isAi: true,
          actions: const [ChatAction.suggest('Packages & prices', text: 'packages'), ChatAction.handoff()],
        );
      } else if (kDebugMode) {
        // Developer-only hint (never shown in release builds): why the AI
        // was skipped or failed.
        answer = ChatMessage(
          fromBot: true,
          text: '${answer.text}\n\n[debug] AI unavailable: ${GeminiService.lastError ?? 'unknown'}',
          actions: answer.actions,
        );
      }
    }

    typing.value = false;
    _add(answer);
  }

  Future<String?> _askAi(ChatCatalog catalog) async {
    if (!GeminiService.isConfigured) {
      GeminiService.lastError =
          'No API key loaded. Stop the app and run again with --dart-define-from-file=env.json (hot restart does not reload it).';
      return null;
    }
    if (_aiCalls >= _maxAiCallsPerSession) {
      GeminiService.lastError = 'Session limit of $_maxAiCallsPerSession AI calls reached (restart the app).';
      return null;
    }
    final last = _lastAiAt;
    if (last != null && DateTime.now().difference(last) < _aiCooldown) {
      GeminiService.lastError = 'Asked too fast, wait a few seconds and try again.';
      return null;
    }

    _aiCalls++;
    _lastAiAt = DateTime.now();
    return GeminiService.ask(history: messages.value, catalog: catalog);
  }

  /// Passes the conversation to staff through the same `messages` thread the
  /// Messages tab (and the Staff app inbox) already use — no new backend.
  Future<HandoffResult> handoffToStaff() async {
    _add(const ChatMessage.user('Talk to staff'));

    AppUser? user;
    try {
      user = await AuthService.instance.me();
    } catch (_) {
      user = null;
    }

    if (user == null) {
      _add(const ChatMessage(
        fromBot: true,
        text: 'Please log in or create an account first so our staff can reply to you.',
        actions: [ChatAction.navigate('Log in / Register', '/welcome')],
      ));
      return HandoffResult.notLoggedIn;
    }

    final q = _lastUserText;
    final text = q == null
        ? 'Hi! I was using the chat assistant and would like to talk to a staff member.'
        : 'Hi! I was using the chat assistant and need help with: "$q"';

    try {
      await MessageRepository.sendMessage(userId: user.uid, customerName: user.fullName, text: text);
      _add(const ChatMessage(
        fromBot: true,
        text: "Done — I've sent your message to our staff. They'll reply in the Messages tab.",
      ));
      return HandoffResult.sent;
    } catch (_) {
      _add(const ChatMessage(
        fromBot: true,
        text: "Sorry, I couldn't reach our staff just now. Please try again, or open the Messages tab.",
        actions: [ChatAction.handoff('Try again'), ChatAction.navigate('Open Messages', '/messages')],
      ));
      return HandoffResult.failed;
    }
  }

  // ------------------------------------------------------------- internals

  void _add(ChatMessage m) {
    final next = [...messages.value, m];
    messages.value = next.length > _maxMessages ? next.sublist(next.length - _maxMessages) : next;
  }

  /// Same data the Book / Rent screens show: the `pricing` collection Admin
  /// manages, falling back to the built-in lists when it's empty or offline.
  Future<ChatCatalog> _loadCatalog() async {
    final cached = _catalog;
    final at = _catalogAt;
    if (cached != null && at != null && DateTime.now().difference(at) < _catalogTtl) return cached;

    List<BoothPackage> packages = const [];
    List<CameraOption> cameras = const [];
    try {
      packages = await PricingRepository.watchPackages().first.timeout(const Duration(seconds: 4));
    } catch (_) {}
    try {
      cameras = await PricingRepository.watchCameraOptions().first.timeout(const Duration(seconds: 4));
    } catch (_) {}

    // Admin's downpayment rules (falls back to defaults when offline).
    var payment = PaymentSettings.defaults;
    try {
      payment = await PaymentSettingsRepository.fetch().timeout(const Duration(seconds: 4));
    } catch (_) {}

    final catalog = ChatCatalog(
      packages: packages.isNotEmpty ? packages : kPackages,
      cameras: cameras.isNotEmpty ? cameras : kCameraOptions,
      payment: payment,
    );
    _catalog = catalog;
    _catalogAt = DateTime.now();
    return catalog;
  }
}