import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Countdown card for an active camera rental. Same visual language as
/// [CountdownTimer] (ring + tabular-figure readout) but sized for a
/// 24-hour window instead of a 15-minute booking hold, so it counts down
/// in HH:MM:SS rather than MM:SS, and turns red with an "Overdue" pill
/// once the due time has passed instead of popping an expiry dialog.
class RentalCountdownTimer extends StatefulWidget {
  final DateTime dueAt;
  final Duration totalDuration;
  final String cameraName;

  const RentalCountdownTimer({
    super.key,
    required this.dueAt,
    required this.cameraName,
    this.totalDuration = const Duration(hours: 24),
  });

  @override
  State<RentalCountdownTimer> createState() => _RentalCountdownTimerState();
}

class _RentalCountdownTimerState extends State<RentalCountdownTimer> {
  Timer? _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.dueAt.difference(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = widget.dueAt.difference(DateTime.now());
      setState(() => _remaining = next);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overdue = _remaining.isNegative;
    final clamped = overdue ? Duration.zero : _remaining;
    final days = clamped.inDays;
    final h = (clamped.inHours % 24).toString().padLeft(2, '0');
    final m = (clamped.inMinutes % 60).toString().padLeft(2, '0');
    final s = (clamped.inSeconds % 60).toString().padLeft(2, '0');
    // 1 day or more left: "13d 23:58:40" instead of "335:58:40".
    final clock = days > 0 ? '${days}d $h:$m:$s' : '$h:$m:$s';
    final pct = overdue ? 0.0 : clamped.inSeconds / widget.totalDuration.inSeconds;
    final color = overdue ? const Color(0xFFB3261E) : AppColors.accent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.surface(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: overdue ? color.withValues(alpha: 0.4) : AppPalette.divider(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(44, 44),
                      painter: _RingPainter(percent: pct.clamp(0, 1), trackColor: AppPalette.cardBg(context), color: color),
                    ),
                    Icon(overdue ? Icons.warning_amber_rounded : Icons.camera_alt, size: 18, color: color),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      overdue ? "OVERDUE FOR RETURN" : "CAMERA RENTED",
                      style: TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w600, color: color),
                    ),
                    const SizedBox(height: 2),
                    Text(widget.cameraName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context))),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(overdue ? "Overdue" : "Active", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: AppPalette.textPrimary(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              children: [
                TextSpan(text: overdue ? "00:00:00" : "$clock "),
                TextSpan(
                  text: overdue ? "  please return to the shop" : "remaining",
                  style: TextStyle(fontWeight: FontWeight.normal, fontSize: 12, color: AppPalette.textMuted(context)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Due back ${_formatDue(widget.dueAt)} · ${_lengthLabel()}",
            style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context)),
          ),
        ],
      ),
    );
  }

  /// "6-hour rental" / "1-day rental" / "3-day rental", from the real
  /// rental length instead of a hard-coded 24 hours.
  String _lengthLabel() {
    final hours = widget.totalDuration.inHours;
    if (hours >= 24 && hours % 24 == 0) {
      final days = hours ~/ 24;
      return days == 1 ? '1-day rental' : '$days-day rental';
    }
    return '$hours-hour rental';
  }

  String _formatDue(DateTime d) {
    final now = DateTime.now();
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    final time = '$hour:$minute $ampm';
    return sameDay ? "today at $time" : "${d.month}/${d.day} at $time";
  }
}

class _RingPainter extends CustomPainter {
  final double percent;
  final Color trackColor;
  final Color color;
  _RingPainter({required this.percent, required this.trackColor, required this.color});

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
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final sweep = 2 * math.pi * percent;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2, sweep, false, progress);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.percent != percent || oldDelegate.trackColor != trackColor || oldDelegate.color != color;
}