import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Short messages shown at the TOP of the user app, in a card that slides
/// down and fades away on its own. Only one toast is on screen at a time: a
/// new message replaces the current one, so messages never pile up or repeat.
/// Tap the card or swipe it up to dismiss it early.
class AppToast {
  AppToast._();

  static OverlayEntry? _current;

  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    dismiss();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _AppToastView(
        message: message,
        duration: duration,
        onDone: () => _removeIfCurrent(entry),
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }

  /// Removes the toast right away (no animation).
  static void dismiss() {
    final e = _current;
    if (e != null) _removeIfCurrent(e);
  }

  static void _removeIfCurrent(OverlayEntry e) {
    if (!identical(_current, e)) return;
    _current = null;
    e.remove();
  }
}

class _AppToastView extends StatefulWidget {
  final String message;
  final Duration duration;
  final VoidCallback onDone;

  const _AppToastView({required this.message, required this.duration, required this.onDone});

  @override
  State<_AppToastView> createState() => _AppToastViewState();
}

class _AppToastViewState extends State<_AppToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _anim.forward();
    _timer = Timer(widget.duration, _close);
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    try {
      await _anim.reverse();
    } catch (_) {
      // Disposed while animating.
    }
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic));

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SlideTransition(
              position: slide,
              child: FadeTransition(
                opacity: _anim,
                child: GestureDetector(
                  onTap: _close,
                  onVerticalDragEnd: (d) {
                    if ((d.primaryVelocity ?? 0) < -150) _close();
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppPalette.cardBg(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.16)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.14),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: AppColors.accentTint(0.10), shape: BoxShape.circle),
                            child: const Icon(Icons.info_outline_rounded, size: 17, color: AppColors.accent),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              widget.message,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                                color: AppPalette.textPrimary(context),
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
    );
  }
}
