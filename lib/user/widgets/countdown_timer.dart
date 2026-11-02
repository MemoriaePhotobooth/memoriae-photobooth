import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Port of `CountdownTimer`. Parent owns [seconds] / [onTick] the same way
/// the React version lifts `seconds`/`setSeconds` state up to the parent.
class CountdownTimer extends StatefulWidget {
  final int seconds;
  final ValueChanged<int> onTick;
  final int totalSeconds;

  const CountdownTimer({
    super.key,
    required this.seconds,
    required this.onTick,
    this.totalSeconds = 15 * 60,
  });

  @override
  State<CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant CountdownTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Mirrors the React effect re-arming whenever `seconds` changes.
    _timer?.cancel();
    _startTimer();
  }

  void _startTimer() {
    if (widget.seconds <= 0) return;
    _timer = Timer(const Duration(seconds: 1), () {
      widget.onTick(math.max(0, widget.seconds - 1));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = (widget.seconds ~/ 60).toString().padLeft(2, '0');
    final s = (widget.seconds % 60).toString().padLeft(2, '0');
    final pct = widget.seconds / widget.totalSeconds;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppPalette.bg(context).withValues(alpha: 0.95),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(40, 40),
                      painter: _RingPainter(percent: pct.clamp(0, 1), trackColor: AppPalette.surface(context)),
                    ),
                    const Icon(Icons.access_time, size: 16, color: AppColors.accent),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "SLOT RESERVED",
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w500,
                      color: AppPalette.textMuted(context),
                    ),
                  ),
                  RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppPalette.textPrimary(context),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      children: [
                        TextSpan(text: "$m:$s "),
                        TextSpan(
                          text: "Remaining",
                          style: TextStyle(fontWeight: FontWeight.normal, fontSize: 12, color: AppPalette.textMuted(context)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accentTint(0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                const Text("Holding", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double percent;
  final Color trackColor;
  _RingPainter({required this.percent, required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 3;

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, track);

    final progress = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final sweep = 2 * math.pi * percent;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2, sweep, false, progress);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => oldDelegate.percent != percent || oldDelegate.trackColor != trackColor;
}
