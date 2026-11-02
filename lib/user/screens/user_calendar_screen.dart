import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/booth_package.dart';
import '../services/booking_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Read-only month calendar so a customer can see, before ever opening
/// checkout, which dates already have someone else's booking and which
/// are still open. Backed by the same `watchBookedDates` stream the
/// booking screen's date picker uses, so a date that's locked there shows
/// locked here too.
class UserCalendarScreen extends StatefulWidget {
  const UserCalendarScreen({super.key});

  @override
  State<UserCalendarScreen> createState() => _UserCalendarScreenState();
}

class _UserCalendarScreenState extends State<UserCalendarScreen> {
  static const List<String> _weekdayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  static const Color _available = Color(0xFF2E7D32);

  late DateTime _displayedMonth;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _displayedMonth = DateTime(now.year, now.month);
  }

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isBeforeToday(DateTime d) {
    final today = DateTime.now();
    return d.isBefore(DateTime(today.year, today.month, today.day));
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _displayedMonth.year == now.year && _displayedMonth.month == now.month;
  }

  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      _displayedMonth = DateTime(now.year, now.month);
      _selectedDay = DateTime(now.year, now.month, now.day);
    });
  }

  void _shiftMonth(int delta) {
    // No point browsing months that are already over.
    if (delta < 0 && _isCurrentMonth) return;
    setState(() {
      _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month + delta);
      _selectedDay = null;
    });
  }

  void _bookDate(DateTime date) {
    Navigator.of(context).pushNamed('/book', arguments: BookingIntent(date: date));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Set<DateTime>>(
      stream: BookingRepository.watchBookedDates(),
      builder: (context, snapshot) {
        final bookedDates = snapshot.data ?? const <DateTime>{};
        final selected = _selectedDay;
        final selectedIsBooked = selected != null && bookedDates.any((d) => _isSameDay(d, selected));
        final selectedIsPast = selected != null && _isBeforeToday(selected);
        final bookedThisMonth = bookedDates
            .where((d) => d.year == _displayedMonth.year && d.month == _displayedMonth.month && !_isBeforeToday(d))
            .length;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Availability", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppPalette.textPrimary(context))),
                        const SizedBox(height: 4),
                        Text(
                          "Pick a date to see if it's open.",
                          style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
                        ),
                      ],
                    ),
                  ),
                  if (!_isCurrentMonth || selected == null || !_isSameDay(selected, DateTime.now()))
                    TextButton.icon(
                      onPressed: _goToToday,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        backgroundColor: AppColors.accentTint(0.08),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      icon: const Icon(Icons.today_rounded, size: 16),
                      label: const Text("Today", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _buildMonthGrid(context, bookedDates, bookedThisMonth),
              const SizedBox(height: 14),
              _buildLegend(context),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(anim), child: child),
                ),
                child: selected != null
                    ? _buildSelectedDayCard(context, selected, isBooked: selectedIsBooked, isPast: selectedIsPast)
                    : _buildHintCard(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLegend(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _legendChip(context, _available, "Available"),
        _legendChip(context, AppColors.accent, "Fully booked"),
        _legendChip(context, AppPalette.textMuted(context), "Past"),
      ],
    );
  }

  Widget _legendChip(BuildContext context, Color color, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppPalette.textSecondary(context))),
        ],
      ),
    );
  }

  Widget _navButton(BuildContext context, IconData icon, VoidCallback? onTap) {
    return Material(
      color: AppPalette.surface(context),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 22, color: onTap == null ? AppPalette.textMuted(context).withValues(alpha: 0.4) : AppPalette.textPrimary(context)),
        ),
      ),
    );
  }

  Widget _buildMonthGrid(BuildContext context, Set<DateTime> bookedDates, int bookedThisMonth) {
    final year = _displayedMonth.year;
    final month = _displayedMonth.month;
    final firstOfMonth = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final leadingBlanks = firstOfMonth.weekday % 7;

    final cells = <DateTime?>[
      ...List.filled(leadingBlanks, null),
      ...List.generate(daysInMonth, (i) => DateTime(year, month, i + 1)),
    ];

    return GestureDetector(
      // Swipe left/right to change month.
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -250) _shiftMonth(1);
        if (v > 250) _shiftMonth(-1);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
        decoration: BoxDecoration(
          color: AppPalette.cardBg(context),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppPalette.divider(context)),
          boxShadow: AppShadows.soft,
        ),
        child: Column(
          children: [
            Row(
              children: [
                _navButton(context, Icons.chevron_left_rounded, _isCurrentMonth ? null : () => _shiftMonth(-1)),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        DateFormat('MMMM yyyy').format(_displayedMonth),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        bookedThisMonth == 0 ? "All upcoming dates are open" : "$bookedThisMonth date${bookedThisMonth == 1 ? '' : 's'} already booked",
                        style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
                      ),
                    ],
                  ),
                ),
                _navButton(context, Icons.chevron_right_rounded, () => _shiftMonth(1)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: _weekdayLabels
                  .map((l) => Expanded(
                        child: Center(
                          child: Text(l, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppPalette.textMuted(context))),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: GridView.count(
                key: ValueKey('$year-$month'),
                crossAxisCount: 7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 0.92,
                children: cells.map((d) => d == null ? const SizedBox.shrink() : _buildDayCell(context, d, bookedDates)).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCell(BuildContext context, DateTime d, Set<DateTime> bookedDates) {
    final isSelected = _selectedDay != null && _isSameDay(_selectedDay!, d);
    final isToday = _isSameDay(d, DateTime.now());
    final isPast = _isBeforeToday(d);
    final isBooked = bookedDates.any((b) => _isSameDay(b, d));

    Color fill = Colors.transparent;
    Color textColor = AppPalette.textPrimary(context);
    Color? dot;
    if (isPast) {
      textColor = AppPalette.textMuted(context).withValues(alpha: 0.6);
    } else if (isBooked) {
      fill = AppColors.accentTint(0.10);
      textColor = AppColors.accent;
      dot = AppColors.accent;
    } else {
      dot = _available;
    }
    if (isSelected) {
      fill = AppColors.accent;
      textColor = AppColors.onAccent;
      dot = AppColors.onAccent;
    }

    return Padding(
      padding: const EdgeInsets.all(2.5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isPast ? null : () => setState(() => _selectedDay = d),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: fill,
              border: (!isSelected && isToday) ? Border.all(color: AppColors.accent, width: 1.6) : null,
              boxShadow: isSelected
                  ? [BoxShadow(color: AppColors.accentTint(0.35), blurRadius: 10, offset: const Offset(0, 4))]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${d.day}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected || isToday || isBooked ? FontWeight.w700 : FontWeight.w500,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 3),
                // Tiny status dot: green = open, maroon = booked.
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(color: dot ?? Colors.transparent, shape: BoxShape.circle),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHintCard(BuildContext context) {
    return Container(
      key: const ValueKey('hint'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Icon(Icons.touch_app_rounded, size: 22, color: AppPalette.textMuted(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Tap a date to check if it's available. Swipe the calendar to change month.",
              style: TextStyle(fontSize: 12.5, height: 1.4, color: AppPalette.textSecondary(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedDayCard(BuildContext context, DateTime day, {required bool isBooked, required bool isPast}) {
    final weekday = DateFormat('EEEE').format(day);
    final dateLabel = DateFormat('MMMM d, yyyy').format(day);
    final statusText = isPast ? "This date has passed" : (isBooked ? "Fully booked" : "Available");
    final helper = isPast
        ? "Pick an upcoming date instead."
        : (isBooked ? "Someone already booked this day. Try another date." : "Good news, this date is open for booking!");
    final statusColor = isPast ? AppPalette.textMuted(context) : (isBooked ? AppColors.accent : _available);

    return Container(
      key: ValueKey('day-${day.toIso8601String()}'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppPalette.divider(context)),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(weekday, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppPalette.textMuted(context))),
                    const SizedBox(height: 2),
                    Text(dateLabel, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPast ? Icons.history_rounded : (isBooked ? Icons.event_busy_rounded : Icons.check_circle_rounded),
                      size: 14,
                      color: statusColor,
                    ),
                    const SizedBox(width: 5),
                    Text(statusText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(helper, style: TextStyle(fontSize: 13, height: 1.4, color: AppPalette.textSecondary(context))),
          if (!isPast && !isBooked) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _bookDate(day),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text("Book this date", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}