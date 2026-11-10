import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Port of `DateSelector`, extended with an expand/collapse calendar —
/// mirroring the reference "Book a Table" flow: a compact date field that,
/// on tap, swaps a short horizontal day strip for a full month grid.
class DateSelector extends StatefulWidget {
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onSelect;

  /// Dates that already have someone else's active booking — shown
  /// struck-through/greyed and not tappable, so the same date can't be
  /// double-booked.
  final Set<DateTime> bookedDates;

  const DateSelector({
    super.key,
    required this.selectedDate,
    required this.onSelect,
    this.bookedDates = const {},
  });

  @override
  State<DateSelector> createState() => _DateSelectorState();
}

class _DateSelectorState extends State<DateSelector> {
  bool _expanded = false;
  late DateTime _displayedMonth;

  static const List<String> _weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"];

  @override
  void initState() {
    super.initState();
    final base = widget.selectedDate ?? DateTime.now();
    _displayedMonth = DateTime(base.year, base.month);
  }

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// Bookable window: from today up to 2 months ahead. Past dates and anything
  /// later than that are disabled.
  bool _isOutOfRange(DateTime d) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final end = DateTime(today.year, today.month + 2, today.day);
    return d.isBefore(start) || d.isAfter(end);
  }

  bool _isBooked(DateTime d) => widget.bookedDates.any((b) => _isSameDay(b, d));

  void _pickDate(DateTime d) {
    if (_isBooked(d) || _isOutOfRange(d)) return;
    widget.onSelect(d);
    setState(() => _expanded = false);
  }

  void _shiftMonth(int delta) {
    setState(() => _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final compactDays = List.generate(14, (i) => DateTime(today.year, today.month, today.day + i));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: AppColors.accent),
                const SizedBox(width: 8),
                Text("Select a Date", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context))),
              ],
            ),
            GestureDetector(
              onTap: () {
                setState(() {
                  _expanded = !_expanded;
                  if (_expanded) {
                    final base = widget.selectedDate ?? DateTime.now();
                    _displayedMonth = DateTime(base.year, base.month);
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppPalette.surface(context),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.selectedDate != null ? DateFormat('EEE, MMM d').format(widget.selectedDate!) : "Pick a date",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context)),
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
          ],
        ),
        const SizedBox(height: 12),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: _buildCompactStrip(context, compactDays),
          secondChild: _buildMonthGrid(context),
        ),
      ],
    );
  }

  Widget _buildCompactStrip(BuildContext context, List<DateTime> days) {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final d = days[i];
          final isSelected = widget.selectedDate != null && _isSameDay(widget.selectedDate!, d);
          final isBooked = _isBooked(d);
          return GestureDetector(
            onTap: isBooked ? null : () => _pickDate(d),
            child: Opacity(
              opacity: isBooked ? 0.4 : 1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 56,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.accent : AppPalette.surface(context),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: isSelected ? AppShadows.accentGlowSmall : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('EEE').format(d).toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: (isSelected ? Colors.white : AppPalette.textPrimary(context)).withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${d.day}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                        color: isSelected ? Colors.white : AppPalette.textPrimary(context),
                        decoration: isBooked ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isBooked ? "Booked" : DateFormat('MMM').format(d),
                      style: TextStyle(
                        fontSize: 9,
                        color: (isSelected ? Colors.white : AppPalette.textPrimary(context)).withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMonthGrid(BuildContext context) {
    final year = _displayedMonth.year;
    final month = _displayedMonth.month;
    final firstOfMonth = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // DateTime.weekday: Mon=1..Sun=7. We want a Sunday-first grid.
    final leadingBlanks = firstOfMonth.weekday % 7;

    final cells = <DateTime?>[
      ...List.filled(leadingBlanks, null),
      ...List.generate(daysInMonth, (i) => DateTime(year, month, i + 1)),
    ];

    return Container(
      key: const ValueKey('month-grid'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(24)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => _shiftMonth(-1),
                icon: const Icon(Icons.chevron_left, size: 20),
                color: AppPalette.textSecondary(context),
                visualDensity: VisualDensity.compact,
              ),
              Text(
                DateFormat('MMMM yyyy').format(_displayedMonth),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
              ),
              IconButton(
                onPressed: () => _shiftMonth(1),
                icon: const Icon(Icons.chevron_right, size: 20),
                color: AppPalette.textSecondary(context),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: _weekdayLabels
                .map((l) => Expanded(
                      child: Center(
                        child: Text(l, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppPalette.textMuted(context))),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1,
            children: cells.map((d) {
              if (d == null) return const SizedBox.shrink();

              final isSelected = widget.selectedDate != null && _isSameDay(widget.selectedDate!, d);
              final isToday = _isSameDay(d, DateTime.now());
              final isPast = _isOutOfRange(d);
              final isBooked = _isBooked(d);
              final isDisabled = isPast || isBooked;

              return Padding(
                padding: const EdgeInsets.all(2),
                child: GestureDetector(
                  onTap: isDisabled ? null : () => _pickDate(d),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? AppColors.accent
                          : isBooked
                              ? AppPalette.divider(context)
                              : Colors.transparent,
                      border: (!isSelected && isToday) ? Border.all(color: AppColors.accent, width: 1.5) : null,
                    ),
                    child: Text(
                      '${d.day}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                        decoration: isBooked ? TextDecoration.lineThrough : null,
                        color: isSelected
                            ? Colors.white
                            : isDisabled
                                ? AppPalette.textMuted(context)
                                : AppPalette.textPrimary(context),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}