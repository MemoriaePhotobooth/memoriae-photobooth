import 'package:flutter/material.dart';
import 'frosted.dart';

/// "Liquid Glass" surface (Apple's iOS 26 look), built from plain Flutter:
///
///  * the content behind it is blurred ([blur]),
///  * a soft light sheen falls across the body, brightest at the top-left,
///  * a specular edge — bright on the lit corner, fading to a faint rim on
///    the opposite one — traces the outline,
///  * a floating shadow lifts it off the page.
///
/// Pass [colors] for a coloured glass body (buttons, app-icon tiles, the
/// active tab) or [tint] for a flat colour wash over clear glass. With
/// [blur] set to 0 no backdrop filter is created, which is the cheaper
/// option for opaque coloured glass.
///
/// This approximates the effect; it does not refract the background the way
/// a shader-based implementation would.
class LiquidGlass extends StatelessWidget {
  final Widget? child;
  final double? width;
  final double? height;
  final double radius;
  final bool capsule;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final Color? tint;
  final List<Color>? colors;
  final bool shadow;

  const LiquidGlass({
    super.key,
    this.child,
    this.width,
    this.height,
    this.radius = 24,
    this.capsule = false,
    this.padding,
    this.blur = 24,
    this.tint,
    this.colors,
    this.shadow = true,
  });

  ShapeBorder get _shape => capsule
      ? const StadiumBorder()
      : ContinuousRectangleBorder(borderRadius: BorderRadius.circular(radius * 2));

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shape = _shape;

    Widget surface = CustomPaint(
      painter: _GlassPainter(shape: shape, dark: dark, tint: tint, colors: colors, foreground: false),
      foregroundPainter: _GlassPainter(shape: shape, dark: dark, tint: tint, colors: colors, foreground: true),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );

    if (blur > 0) {
      surface = Frosted(sigma: blur, child: surface);
    }

    return Container(
      width: width,
      height: height,
      decoration: shadow
          ? ShapeDecoration(
              shape: shape,
              shadows: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.35 : 0.10), blurRadius: 24, offset: const Offset(0, 10))],
            )
          : null,
      child: ClipPath(clipper: ShapeBorderClipper(shape: shape), child: surface),
    );
  }
}

class _GlassPainter extends CustomPainter {
  final ShapeBorder shape;
  final bool dark;
  final Color? tint;
  final List<Color>? colors;
  final bool foreground;

  const _GlassPainter({
    required this.shape,
    required this.dark,
    required this.tint,
    required this.colors,
    required this.foreground,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final path = shape.getOuterPath(rect);

    if (!foreground) {
      // Body: coloured gradient, flat tint, or a faint white wash.
      final paint = Paint();
      if (colors != null && colors!.isNotEmpty) {
        paint.shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors!.length == 1 ? [colors!.first, colors!.first] : colors!,
        ).createShader(rect);
      } else if (tint != null) {
        paint.color = tint!;
      } else {
        paint.color = Colors.white.withValues(alpha: dark ? 0.06 : 0.26);
      }
      canvas.drawPath(path, paint);
      return;
    }

    // Sheen across the whole body.
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: dark ? 0.16 : 0.42),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: dark ? 0.05 : 0.12),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );

    // Gloss on the upper half.
    final gloss = Rect.fromLTWH(0, 0, size.width, size.height * 0.5);
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      gloss,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: dark ? 0.10 : 0.22), Colors.white.withValues(alpha: 0)],
        ).createShader(gloss),
    );
    canvas.restore();

    // Specular edge: bright on the lit corner, a faint rim on the far one.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.95),
            Colors.white.withValues(alpha: 0.12),
            Colors.white.withValues(alpha: 0.06),
            Colors.white.withValues(alpha: 0.6),
          ],
          stops: const [0, 0.38, 0.68, 1],
        ).createShader(rect),
    );

    // Hairline so the glass stays visible on a white page.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.07),
    );
  }

  @override
  bool shouldRepaint(_GlassPainter old) =>
      old.shape != shape || old.dark != dark || old.tint != tint || old.colors != colors || old.foreground != foreground;
}