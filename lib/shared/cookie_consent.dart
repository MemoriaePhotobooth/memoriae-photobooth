import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the visitor chose on the cookie notice.
enum CookieChoice { accepted, declined }

/// Remembers the visitor's cookie choice on this device/browser
/// (SharedPreferences = the browser's local storage on the web build).
class CookieConsent {
  CookieConsent._();

  static const String _choiceKey = 'cookie_consent_choice_v1';
  static const String _atKey = 'cookie_consent_at_v1';

  /// The saved choice, or null if the visitor has not chosen yet.
  static Future<CookieChoice?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      switch (prefs.getString(_choiceKey)) {
        case 'accepted':
          return CookieChoice.accepted;
        case 'declined':
          return CookieChoice.declined;
      }
    } catch (_) {
      // Storage unavailable: treat as "not chosen" so the notice still shows.
    }
    return null;
  }

  static Future<void> save(CookieChoice choice) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_choiceKey, choice == CookieChoice.accepted ? 'accepted' : 'declined');
      await prefs.setString(_atKey, DateTime.now().toIso8601String());
    } catch (_) {
      // If saving fails the notice simply shows again next visit.
    }
  }

  /// Clears the saved choice so the notice shows again (handy for testing).
  static Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_choiceKey);
      await prefs.remove(_atKey);
    } catch (_) {}
  }
}

/// Wraps the whole app and floats a cookie notice at the bottom of the
/// screen until the visitor taps Accept or Decline. Put it in
/// `MaterialApp(builder: ...)` so it sits above every screen.
class CookieConsentGate extends StatefulWidget {
  const CookieConsentGate({
    super.key,
    required this.child,
    required this.accent,
    this.onViewPolicy,
  });

  final Widget child;
  final Color accent;

  /// Called when the visitor taps "Privacy Policy" in the notice.
  final VoidCallback? onViewPolicy;

  @override
  State<CookieConsentGate> createState() => _CookieConsentGateState();
}

class _CookieConsentGateState extends State<CookieConsentGate> {
  bool _loaded = false;
  bool _needsChoice = false;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final choice = await CookieConsent.read();
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _needsChoice = choice == null;
    });
    if (choice == null) {
      // Let the first frame draw off-screen, then slide the notice up.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _shown = true);
      });
    }
  }

  Future<void> _choose(CookieChoice choice) async {
    setState(() => _shown = false);
    await CookieConsent.save(choice);
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (mounted) setState(() => _needsChoice = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_loaded && _needsChoice)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      offset: _shown ? Offset.zero : const Offset(0, 1.4),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 240),
                        opacity: _shown ? 1 : 0,
                        child: _CookieCard(
                          accent: widget.accent,
                          onAccept: () => _choose(CookieChoice.accepted),
                          onDecline: () => _choose(CookieChoice.declined),
                          onViewPolicy: widget.onViewPolicy,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CookieCard extends StatelessWidget {
  const _CookieCard({
    required this.accent,
    required this.onAccept,
    required this.onDecline,
    this.onViewPolicy,
  });

  final Color accent;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback? onViewPolicy;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF262220) : Colors.white;
    final title = dark ? const Color(0xFFF5F0EC) : const Color(0xFF1A1A1A);
    final body = dark ? const Color(0xFFB9B2AE) : const Color(0xFF57534E);
    final border = dark ? const Color(0xFF34302E) : const Color(0xFFE7E5E4);

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.5 : 0.16),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cookie_outlined, size: 20, color: accent),
                const SizedBox(width: 8),
                Text(
                  'We use cookies',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: title),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Memoriae uses cookies and your browser\'s local storage to keep you signed in, '
              'remember your settings, and make booking work. We don\'t use them for ads. '
              'Declining keeps only what the app needs to run.',
              style: TextStyle(fontSize: 12.5, height: 1.5, color: body),
            ),
            if (onViewPolicy != null) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: onViewPolicy,
                child: Text(
                  'Read our Privacy Policy',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: accent,
                    decoration: TextDecoration.underline,
                    decorationColor: accent,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDecline,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: title,
                      side: BorderSide(color: border, width: 1.2),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('Decline', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('Accept', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
