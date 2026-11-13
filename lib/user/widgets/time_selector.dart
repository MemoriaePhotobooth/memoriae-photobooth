import 'package:flutter/material.dart';
import '../services/booking_hours.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Business hours the time chips cover, in 24-hour decimal form
/// (8.0 = 8:00 AM, 22.0 = 10:00 PM).
const double kEarliestHour = 8.0;
const double kLatestHour = 22.0;
const double kMinBookingHours = 1.0;

/// Longest booking a customer can pick. Every package includes 2 hours of
/// booth time, so the end time can never be more than 2 hours after start.
const double kMaxBookingHours = 2.0;

/// Formats a decimal hour (e.g. 13.5) as "1:30 PM".
String formatHourLabel(double hour) {
  final totalMinutes = (hour * 60).round();
  final h = (totalMinutes ~/ 60) % 24;
  final m = totalMinutes % 60;
  final period = h >= 12 ? "PM" : "AM";
  final displayHour = h % 12 == 0 ? 12 : h % 12;
  final mm = m.toString().padLeft(2, '0');
  return '$displayHour:$mm $period';
}

/// Formats a start/end hour pair as "10:00 AM – 5:00 PM".
String formatTimeRangeLabel(RangeValues range) => '${formatHourLabel(range.start)} – ${formatHourLabel(range.end)}';

/// Compact label for the header chip: "10 AM", or "10:30 AM" on the half hour.
String _shortHour(double hour) {
  final totalMinutes = (hour * 60).round();
  final h = (totalMinutes ~/ 60) % 24;
  final m = totalMinutes % 60;
  final period = h >= 12 ? "PM" : "AM";
  final displayHour = h % 12 == 0 ? 12 : h % 12;
  return m == 0 ? '$displayHour $period' : '$displayHour:${m.toString().padLeft(2, '0')} $period';
}

/// Time-range picker styled like [DateSelector]: a single dropdown chip in the
/// header ("10 AM – 5 PM ▾") that opens a panel where the start and end times
/// are picked from two scrollable rows of half-hour options, or by dragging
/// the start/end chips below.
class TimeSelector extends StatefulWidget {
  final RangeValues range;
  final ValueChanged<RangeValues> onChanged;

  /// The booking date. When it is today (Philippine time), start times that
  /// have already passed are hidden so they can't be picked.
  final DateTime? date;

  const TimeSelector({super.key, required this.range, required this.onChanged, this.date});

  @override
  State<TimeSelector> createState() => _TimeSelectorState();
}

class _TimeSelectorState extends State<TimeSelector> {
  bool _expanded = false;

  /// Rounds to the nearest half hour so values always match a chip.
  double _snap(double h) => ((h * 2).round() / 2).clamp(kEarliestHour, kLatestHour).toDouble();

  List<double> _hours(double from, double to) {
    final out = <double>[];
    for (var h = _snap(from); h <= to + 0.001; h += 0.5) {
      out.add(h);
    }
    return out;
  }

  /// Start times to offer: every half hour in business hours, minus the
  /// ones that already passed when the date is today (Manila time).
  List<double> _startOptions() {
    final all = _hours(kEarliestHour, kLatestHour - kMinBookingHours);
    final d = widget.date;
    if (d == null) return all;
    return all.where((h) => !BookingHours.isSlotInPast(d, h)).toList();
  }

  void _pickStart(double h) {
    // Keep the end inside [start + min, start + max]: starting later pushes
    // the end along, and an end that is now too far away is pulled back.
    var end = widget.range.end;
    if (end < h + kMinBookingHours) end = h + kMinBookingHours;
    if (end > h + kMaxBookingHours) end = h + kMaxBookingHours;
    if (end > kLatestHour) end = kLatestHour;
    widget.onChanged(RangeValues(h, end));
  }

  void _pickEnd(double h) => widget.onChanged(RangeValues(widget.range.start, h));

  @override
  Widget build(BuildContext context) {
    final range = widget.range;
    final start = _snap(range.start);
    final end = _snap(range.end);
    final durationHours = range.end - range.start;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.access_time, size: 16, color: AppColors.accent),
                const SizedBox(width: 8),
                Text("Select Time", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context))),
              ],
            ),
            const SizedBox(width: 8),
            Flexible(
              child: GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(999)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          '${_shortHour(start)} – ${_shortHour(end)}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 18,
                        color: AppPalette.textSecondary(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(24)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label(context, "START"),
                  const SizedBox(height: 8),
                  if (_startOptions().isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        "No more times left today. Please pick another date.",
                        style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)),
                      ),
                    )
                  else
                    _TimeStrip(
                    // Latest possible start leaves room for the minimum booking length.
                    options: _startOptions(),
                    value: start,
                    onPick: _pickStart,
                  ),
                  const SizedBox(height: 16),
                  _label(context, "END"),
                  const SizedBox(height: 8),
                  _TimeStrip(
                    // End is at least 1 hour and at most 2 hours after start.
                    options: _hours(
                      start + kMinBookingHours,
                      (start + kMaxBookingHours) > kLatestHour ? kLatestHour : start + kMaxBookingHours,
                    ),
                    value: end,
                    onPick: _pickEnd,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Up to 2 hours per booking (your package includes 2 hours).',
                    style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context)),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: AppColors.accentTint(0.1), borderRadius: BorderRadius.circular(999)),
                        child: Text(
                          durationHours == durationHours.roundToDouble()
                              ? '${durationHours.round()} hour${durationHours.round() == 1 ? '' : 's'} selected'
                              : '${durationHours.toStringAsFixed(1)} hours selected',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.accent),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() => _expanded = false),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.accent,
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        child: const Text("Done"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _label(BuildContext context, String text) => Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppPalette.textMuted(context)),
      );
}

/// One horizontally-scrolling row of time chips; the chosen one is maroon.
class _TimeStrip extends StatefulWidget {
  final List<double> options;
  final double value;
  final ValueChanged<double> onPick;

  const _TimeStrip({required this.options, required this.value, required this.onPick});

  @override
  State<_TimeStrip> createState() => _TimeStripState();
}

class _TimeStripState extends State<_TimeStrip> {
  static const double _chipWidth = 84;
  static const double _gap = 8;
  static const double _step = _chipWidth + _gap;

  late final ScrollController _controller;

  double _offsetFor(double value, List<double> options) {
    final i = options.indexOf(value);
    return i <= 0 ? 0 : (i * _step - _step).clamp(0, double.infinity).toDouble();
  }

  @override
  void initState() {
    super.initState();
    // Open with the chosen time in view.
    _controller = ScrollController(initialScrollOffset: _offsetFor(widget.value, widget.options));
  }

  @override
  void didUpdateWidget(covariant _TimeStrip old) {
    super.didUpdateWidget(old);
    // The END row's first option moves when START changes. Shift the scroll
    // position by the same amount so the chips don't appear to jump.
    if (old.options.isNotEmpty && widget.options.isNotEmpty && old.options.first != widget.options.first) {
      final shift = (widget.options.first - old.options.first) / 0.5 * _step;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        final target = (_controller.offset - shift).clamp(0, _controller.position.maxScrollExtent).toDouble();
        _controller.jumpTo(target);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        itemCount: widget.options.length,
        separatorBuilder: (_, __) => const SizedBox(width: _gap),
        itemBuilder: (context, i) {
          final h = widget.options[i];
          final selected = h == widget.value;
          return GestureDetector(
            onTap: () => widget.onPick(h),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _chipWidth,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.accent : AppPalette.cardBg(context),
                borderRadius: BorderRadius.circular(14),
                boxShadow: selected ? AppShadows.accentGlowSmall : null,
              ),
              child: Text(
                formatHourLabel(h),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppPalette.textPrimary(context),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}