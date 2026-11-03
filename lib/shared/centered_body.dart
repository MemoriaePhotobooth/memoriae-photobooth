import 'package:flutter/material.dart';

/// Keeps a page's content centered and no wider than [maxWidth] on wide
/// screens (desktop browsers, tablets), instead of stretching edge to edge.
/// On a phone it changes nothing. The content stays pinned to the top, so
/// scrolling pages still behave normally.
class CenteredBody extends StatelessWidget {
  const CenteredBody({super.key, required this.child, this.maxWidth = 640});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
