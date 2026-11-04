import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

/// Blurs whatever is behind [child] (the "frosted glass" look) — except on
/// the web, where a live backdrop blur re-renders the whole page behind it on
/// every scroll frame and is the single most expensive thing the app draws.
/// There the child is shown as-is, so give it a fairly opaque background.
class Frosted extends StatelessWidget {
  final double sigma;
  final Widget child;
  const Frosted({super.key, required this.sigma, required this.child});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return child;
    return BackdropFilter(filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma), child: child);
  }
}
