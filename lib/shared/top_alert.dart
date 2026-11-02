import 'dart:async';
import 'package:flutter/material.dart';

/// Shortens a long customer name so an alert never gets flooded by it.
String shortenForAlert(String text, {int max = 28}) {
  final t = text.trim();
  return t.length <= max ? t : '${t.substring(0, max - 1).trimRight()}…';
}

/// A heads-up alert that slides in from the TOP of the screen, shows for
/// [duration] (default 5 seconds, with a thin countdown bar), then slides
/// away on its own. Tap the body or the action to act on it, tap ✕ or swipe
/// it up to dismiss early. Only one is shown at a time — a newer alert
/// replaces the current one.
class TopAlert {
  TopAlert._();

  static OverlayEntry? _current;

  /// Pass a [context] from inside the app, or an [overlay] directly (e.g.
  /// `navigatorKey.currentState?.overlay`) when showing from a service that
  /// has no widget context.
  static void show(
    BuildContext? context, {
    OverlayState? overlay,
    required String title,
    required String message,
    required Color accent,
    IconData icon = Icons.event_available_rounded,
    String actionLabel = 'View',
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 5),
  }) {
    final target = overlay ?? (context == null ? null : Overlay.maybeOf(context, rootOverlay: true));
    if (target == null) return;
    dismiss();

    var removed = false;
    late final OverlayEntry entry;
    void remove() {
      if (removed) return;
      removed = true;
      entry.remove();
      if (identical(_current, entry)) _current = null;
    }

    entry = OverlayEntry(
      builder: (_) => _TopAlertCard(
        title: title,
        message: message,
        accent: accent,
        icon: icon,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
        onClosed: remove,
      ),
    );
    _current = entry;
    target.insert(entry);
  }

  /// Removes the alert right away (no animation).
  static void dismiss() {
    final e = _current;
    _current = null;
    if (e != null) {
      try {
        e.remove();
      } catch (_) {
        // Already gone.
      }
    }
  }
}

class _TopAlertCard extends StatefulWidget {
  final String title;
  final String message;
  final Color accent;
  final IconData icon;
  final String actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  final VoidCallback onClosed;

  const _TopAlertCard({
    required this.title,
    required this.message,
    required this.accent,
    required this.icon,
    required this.actionLabel,
    required this.onAction,
    required this.duration,
    required this.onClosed,
  });

  @override
  State<_TopAlertCard> createState() => _TopAlertCardState();
}

class _TopAlertCardState extends State<_TopAlertCard> with TickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  late final AnimationController _countdown = AnimationController(vsync: this, duration: widget.duration);
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _slide.forward();
    _countdown.forward();
    _countdown.addStatusListener((s) {
      if (s == AnimationStatus.completed) _close();
    });
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _countdown.stop();
    try {
      await _slide.reverse();
    } catch (_) {
      // Disposed mid-animation.
    }
    widget.onClosed();
  }

  void _act() {
    final action = widget.onAction;
    _close();
    action?.call();
  }

  @override
  void dispose() {
    _slide.dispose();
    _countdown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF2A2523) : Colors.white;
    final textPrimary = dark ? const Color(0xFFF5F0ED) : const Color(0xFF1C1917);
    final textMuted = dark ? const Color(0xFFB3AAA6) : const Color(0xFF6B635F);
    final accent = widget.accent;
    final accentOnDark = dark ? Color.lerp(accent, Colors.white, 0.45)! : accent;

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, -1.4), end: Offset.zero)
                  .animate(CurvedAnimation(parent: _slide, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
              child: FadeTransition(
                opacity: _slide,
                child: GestureDetector(
                  onVerticalDragEnd: (d) {
                    if ((d.primaryVelocity ?? 0) < -150) _close();
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: accent.withValues(alpha: dark ? 0.45 : 0.18)),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.5 : 0.16), blurRadius: 24, offset: const Offset(0, 8)),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: widget.onAction == null ? null : _act,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(color: accent.withValues(alpha: dark ? 0.28 : 0.12), shape: BoxShape.circle),
                                    child: Icon(widget.icon, size: 20, color: accentOnDark),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          widget.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: textPrimary),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          widget.message,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 12.5, height: 1.3, color: textMuted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (widget.onAction != null)
                                    TextButton(
                                      onPressed: _act,
                                      style: TextButton.styleFrom(
                                        foregroundColor: accentOnDark,
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                        minimumSize: const Size(0, 36),
                                      ),
                                      child: Text(widget.actionLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                                    ),
                                  IconButton(
                                    onPressed: _close,
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(Icons.close_rounded, size: 18, color: textMuted),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Countdown bar: drains over the alert's lifetime.
                          AnimatedBuilder(
                            animation: _countdown,
                            builder: (_, __) => LinearProgressIndicator(
                              value: 1 - _countdown.value,
                              minHeight: 3,
                              backgroundColor: Colors.transparent,
                              valueColor: AlwaysStoppedAnimation<Color>(accentOnDark.withValues(alpha: 0.85)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
