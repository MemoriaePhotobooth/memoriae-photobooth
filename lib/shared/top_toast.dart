import 'dart:async';
import 'package:flutter/material.dart';

/// What a toast is telling the person. Picked automatically from the
/// wording when [TopToast.show] isn't told explicitly.
enum TopToastKind { success, error, info }

/// One feedback message for the Admin and Staff apps ("Refund marked as
/// sent.", "Couldn't save the fees.", "Reference number copied"...).
///
/// It replaces the stock SnackBar, which floated at the BOTTOM of the
/// screen — easy to miss, and when a dialog was open it showed up behind
/// the dialog's dark barrier. A toast slides in from the TOP of the whole
/// app (above every dialog and sheet), so it is seen right away, then
/// slides back out on its own. Tap it or swipe it up to dismiss early.
/// Only one is shown at a time; a newer one replaces the current one.
class TopToast {
  TopToast._();

  /// Give this to the app's `MaterialApp(navigatorKey: ...)`. It lets a
  /// toast be shown from code that captured no BuildContext (e.g. after an
  /// `await`), always on the root overlay so it sits above dialogs.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static const Color _success = Color(0xFF2E7D32);
  static const Color _error = Color(0xFFB3261E);
  static const Color _info = Color(0xFF6E1B1E);

  static OverlayEntry? _current;

  /// [context] is optional — the app's [navigatorKey] is used when it is
  /// null or no longer mounted.
  static void show(
    BuildContext? context,
    String message, {
    TopToastKind? kind,
    Duration duration = const Duration(milliseconds: 3800),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final text = message.trim();
    if (text.isEmpty) return;

    // Same overlay the app's dialogs use (the ROOT one), so the toast is
    // drawn above any open dialog instead of behind it. Falls back to the
    // app's navigator when the caller kept no usable BuildContext.
    final BuildContext? anchor = (context != null && context.mounted) ? context : navigatorKey.currentContext;
    OverlayState? overlay = anchor == null ? null : Overlay.maybeOf(anchor, rootOverlay: true);
    overlay ??= navigatorKey.currentState?.overlay;
    if (overlay == null) return;
    // Light/dark is read from the app's own theme (the overlay itself may
    // live above it when the app is mounted inside the launcher).
    final dark = anchor != null && Theme.of(anchor).brightness == Brightness.dark;

    dismiss();

    var removed = false;
    late final OverlayEntry entry;
    void remove() {
      if (removed) return;
      removed = true;
      try {
        entry.remove();
      } catch (_) {
        // Already gone.
      }
      if (identical(_current, entry)) _current = null;
    }

    entry = OverlayEntry(
      builder: (_) => _ToastCard(
        message: text,
        kind: kind ?? _infer(text),
        dark: dark,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
        onClosed: remove,
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }

  /// Removes the toast right away (no animation).
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

  static TopToastKind _infer(String text) {
    final t = text.toLowerCase();
    const bad = [
      "couldn't", "couldn’t", "can't", "can’t", 'cannot', 'failed', 'error', 'unable', 'invalid',
      'not allowed', 'try again', 'denied', 'wrong', 'missing', 'required', 'too big', 'too large',
    ];
    for (final w in bad) {
      if (t.contains(w)) return TopToastKind.error;
    }
    const good = [
      'saved', 'sent', 'copied', 'deleted', 'updated', 'marked', 'blocked', 'unblocked', 'reopened',
      'closed', 'cleared', 'voided', 'hidden', 'visible', 'posted', 'published', 'added', 'removed',
      'created', 'confirmed', 'approved', 'rescheduled', 'changed', 'done', 'success', 'is now',
    ];
    for (final w in good) {
      if (t.contains(w)) return TopToastKind.success;
    }
    return TopToastKind.info;
  }
}

class _ToastCard extends StatefulWidget {
  final String message;
  final TopToastKind kind;
  final bool dark;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onClosed;

  const _ToastCard({
    required this.message,
    required this.kind,
    required this.dark,
    required this.duration,
    required this.actionLabel,
    required this.onAction,
    required this.onClosed,
  });

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _anim.forward();
    _timer = Timer(widget.duration, _close);
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    try {
      await _anim.reverse();
    } catch (_) {
      // Disposed mid-animation.
    }
    widget.onClosed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  Color get _accent {
    switch (widget.kind) {
      case TopToastKind.success:
        return TopToast._success;
      case TopToastKind.error:
        return TopToast._error;
      case TopToastKind.info:
        return TopToast._info;
    }
  }

  IconData get _icon {
    switch (widget.kind) {
      case TopToastKind.success:
        return Icons.check_circle_rounded;
      case TopToastKind.error:
        return Icons.error_rounded;
      case TopToastKind.info:
        return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final surface = dark ? const Color(0xFF2A2523) : Colors.white;
    final ink = dark ? const Color(0xFFF5F0ED) : const Color(0xFF1C1917);
    final muted = dark ? const Color(0xFFB3AAA6) : const Color(0xFF6B635F);
    final accent = dark ? Color.lerp(_accent, Colors.white, 0.4)! : _accent;
    final curve = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, -1.5), end: Offset.zero).animate(curve),
              child: FadeTransition(
                opacity: _anim,
                child: GestureDetector(
                  onTap: _close,
                  onVerticalDragEnd: (d) {
                    if ((d.primaryVelocity ?? 0) < -120) _close();
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: _accent.withValues(alpha: dark ? 0.5 : 0.22)),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.55 : 0.18), blurRadius: 28, offset: const Offset(0, 10)),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(width: 5, color: _accent),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
                                child: Row(
                                  children: [
                                    Icon(_icon, size: 22, color: accent),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        widget.message,
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 13.5, height: 1.35, fontWeight: FontWeight.w600, color: ink),
                                      ),
                                    ),
                                    if (widget.actionLabel != null && widget.onAction != null)
                                      TextButton(
                                        onPressed: () {
                                          final a = widget.onAction;
                                          _close();
                                          a?.call();
                                        },
                                        style: TextButton.styleFrom(
                                          foregroundColor: accent,
                                          padding: const EdgeInsets.symmetric(horizontal: 10),
                                          minimumSize: const Size(0, 34),
                                        ),
                                        child: Text(widget.actionLabel!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                                      ),
                                    IconButton(
                                      onPressed: _close,
                                      visualDensity: VisualDensity.compact,
                                      icon: Icon(Icons.close_rounded, size: 18, color: muted),
                                    ),
                                  ],
                                ),
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
      ),
    );
  }
}
