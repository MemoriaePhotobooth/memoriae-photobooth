import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/booking_record.dart';
import '../services/booking_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Read-only month calendar for staff: any date that has an active
/// booking (pending approval, approved, or completed) shows as "locked"
/// with a colored dot, since that slot is no longer open for a new
/// customer to pick. Cancelled/rejected bookings free the date back up.
///
/// Responsive: below [_desktopBreakpoint] the calendar and the selected
/// day's agenda stack vertically (calendar on top); at or above it they
/// sit side by side in a two-pane layout, since a phone-width single
/// column just left a widescreen window mostly empty.
class AdminCalendarScreen extends StatefulWidget {
  const AdminCalendarScreen({super.key});

  @override
  State<AdminCalendarScreen> createState() => _AdminCalendarScreenState();
}

class _AdminCalendarScreenState extends State<AdminCalendarScreen> {
  static const double _desktopBreakpoint = 900;
  static const List<String> _weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"];

  late DateTime _displayedMonth;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _displayedMonth = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  void _shiftMonth(int delta) {
    setState(() => _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month + delta));
  }

  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      _displayedMonth = DateTime(now.year, now.month);
      _selectedDay = DateTime(now.year, now.month, now.day);
    });
  }

  /// A booking still "locks" its date unless it's been rejected/cancelled.
  bool _locksDate(BookingRecord b) => b.status != 'cancelled';

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':
        return const Color(0xFF2E7D32);
      case 'completed':
        return const Color(0xFF1565C0);
      case 'cancelled':
        return const Color(0xFF9E9E9E);
      default:
        return const Color(0xFFB07A2A);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BookingRecord>>(
      stream: BookingRepository.watchAllBookings(),
      builder: (context, snapshot) {
        final bookings = snapshot.data ?? const <BookingRecord>[];
        final locked = bookings.where(_locksDate).toList();

        final selected = _selectedDay;
        final dayBookings = selected == null
            ? const <BookingRecord>[]
            : (locked.where((b) => _isSameDay(b.date, selected)).toList()..sort((a, b) => a.time.compareTo(b.time)));

        return LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= _desktopBreakpoint;
            final calendar = _buildCalendarCard(context, locked);
            final agenda = _buildAgendaCard(context, selected, dayBookings);

            if (isDesktop) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 400, child: calendar),
                    const SizedBox(width: 24),
                    Expanded(child: agenda),
                  ],
                ),
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  calendar,
                  const SizedBox(height: 20),
                  agenda,
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLegend(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _legendChip(context, _statusColor('pending_confirmation'), "Pending"),
        _legendChip(context, _statusColor('confirmed'), "Approved"),
        _legendChip(context, _statusColor('completed'), "Completed"),
      ],
    );
  }

  Widget _legendChip(BuildContext context, Color color, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _buildCalendarCard(BuildContext context, List<BookingRecord> locked) {
    final year = _displayedMonth.year;
    final month = _displayedMonth.month;
    final firstOfMonth = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final leadingBlanks = firstOfMonth.weekday % 7;

    final cells = <DateTime?>[
      ...List.filled(leadingBlanks, null),
      ...List.generate(daysInMonth, (i) => DateTime(year, month, i + 1)),
    ];

    Color? colorForDay(DateTime d) {
      for (final b in locked) {
        if (_isSameDay(b.date, d)) return _statusColor(b.status);
      }
      return null;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _navButton(context, Icons.chevron_left, () => _shiftMonth(-1)),
                  SizedBox(
                    width: 132,
                    child: Text(
                      DateFormat('MMMM yyyy').format(_displayedMonth),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
                    ),
                  ),
                  _navButton(context, Icons.chevron_right, () => _shiftMonth(1)),
                ],
              ),
              TextButton(
                onPressed: _goToToday,
                style: TextButton.styleFrom(foregroundColor: AppColors.accent, padding: const EdgeInsets.symmetric(horizontal: 10)),
                child: const Text("Today", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: cells.map((d) {
              if (d == null) return const SizedBox.shrink();

              final isSelected = _selectedDay != null && _isSameDay(_selectedDay!, d);
              final isToday = _isSameDay(d, DateTime.now());
              final dotColor = colorForDay(d);

              return GestureDetector(
                onTap: () => setState(() => _selectedDay = d),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: isSelected
                        ? AppColors.accent
                        : (dotColor != null ? dotColor.withValues(alpha: 0.10) : Colors.transparent),
                    border: (!isSelected && isToday) ? Border.all(color: AppColors.accent, width: 1.5) : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${d.day}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.white : AppPalette.textPrimary(context),
                        ),
                      ),
                      if (dotColor != null) ...[
                        const SizedBox(height: 3),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: isSelected ? Colors.white : dotColor),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          Divider(height: 1, color: AppPalette.divider(context)),
          const SizedBox(height: 14),
          _buildLegend(context),
        ],
      ),
    );
  }

  Widget _navButton(BuildContext context, IconData icon, VoidCallback onPressed) {
    return Material(
      color: AppPalette.surface(context),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: AppPalette.textSecondary(context)),
        ),
      ),
    );
  }

  Widget _buildAgendaCard(BuildContext context, DateTime? selected, List<BookingRecord> dayBookings) {
    return Container(
      padding: const EdgeInsets.all(22),
      constraints: const BoxConstraints(minHeight: 200),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(28),
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
                    Text(
                      selected != null ? DateFormat('EEEE').format(selected) : "Select a date",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppPalette.textMuted(context)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selected != null ? DateFormat('MMMM d, yyyy').format(selected) : "—",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
                    ),
                  ],
                ),
              ),
              if (dayBookings.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.accentTint(0.1), borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    '${dayBookings.length} booking${dayBookings.length == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.accent),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (dayBookings.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(Icons.event_available, size: 36, color: AppPalette.textMuted(context)),
                  const SizedBox(height: 10),
                  Text("No bookings on this date.", style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context))),
                ],
              ),
            )
          else
            ...dayBookings.map((b) => _dayBookingTile(context, b)),
        ],
      ),
    );
  }

  Widget _dayBookingTile(BuildContext context, BookingRecord b) {
    final color = _statusColor(b.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppPalette.surface(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 52,
            decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.horizontal(left: Radius.circular(16))),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.packageName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                        const SizedBox(height: 2),
                        Text(b.time, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      b.status.replaceAll('_', ' '),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}