import 'package:flutter/material.dart';

/// A popup that opens in the CENTER of the screen, right where the person is
/// looking — used instead of `showModalBottomSheet`, whose sheets slid up
/// from the very bottom of the page (easy to miss, and far from the button
/// that was tapped).
///
/// The card is rounded on every corner, scales/fades in, dims the page
/// behind it, lifts above the keyboard, and scrolls internally if the
/// content is taller than the screen (the [builder] should therefore use a
/// `Column(mainAxisSize: MainAxisSize.min)` with a `Flexible` scrollable).
/// Close it with `Navigator.of(context).pop()` like any dialog.
Future<T?> showAppModal<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxWidth = 560,
  bool barrierDismissible = true,
  String barrierLabel = 'Close',
}) {
  // Uses the app's own navigator (like the bottom sheets it replaces), so it
  // keeps the app's live light/dark theme.
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: false,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, __) => _AppModalFrame(maxWidth: maxWidth, builder: builder),
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _AppModalFrame extends StatelessWidget {
  final double maxWidth;
  final WidgetBuilder builder;

  const _AppModalFrame({required this.maxWidth, required this.builder});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    const gap = 16.0;
    final double maxHeight = (mq.size.height - mq.viewInsets.bottom - mq.padding.top - mq.padding.bottom - gap * 2).clamp(240.0, 900.0).toDouble();

    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: EdgeInsets.fromLTRB(gap, gap, gap, gap + mq.viewInsets.bottom),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.6 : 0.22), blurRadius: 40, offset: const Offset(0, 16)),
                ],
              ),
              child: Material(
                color: dark ? const Color(0xFF262220) : Colors.white,
                surfaceTintColor: Colors.transparent,
                borderRadius: BorderRadius.circular(26),
                clipBehavior: Clip.antiAlias,
                child: Builder(builder: builder),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
