import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/booking_record.dart';
import '../services/admin_service.dart';
import '../services/booking_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Admin dialog for moving a customer's booking to another date/time.
/// Saves through [BookingRepository.rescheduleBooking] itself, so a clash
/// ("that date was just taken") shows inline and the dialog stays open;
/// on success it pops the updated [BookingRecord].
class RescheduleDialog extends StatefulWidget {
  final BookingRecord booking;
  const RescheduleDialog({super.key, required this.booking});

  @override
  State<RescheduleDialog> createState() => RescheduleDialogState();
}

class RescheduleDialogState extends State<RescheduleDialog> {
  late DateTime _date;
  late TimeOfDay _start;
  TimeOfDay? _end;
  final _reasonController = TextEditingController();
  bool _saving = false;
  bool _loadingDates = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final b = widget.booking;
    _date = DateTime(b.date.year, b.date.month, b.date.day);
    final times = RegExp(r'(\d{1,2}):(\d{2})\s*([AaPp][Mm])').allMatches(b.time).map((m) {
      var h = int.parse(m.group(1)!) % 12;
      if (m.group(3)!.toLowerCase() == 'pm') h += 12;
      return TimeOfDay(hour: h, minute: int.parse(m.group(2)!));
    }).toList();
    _start = times.isNotEmpty ? times[0] : const TimeOfDay(hour: 10, minute: 0);
    _end = times.length > 1 ? times[1] : null;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  String _fmt(TimeOfDay t) => DateFormat('h:mm a').format(DateTime(2000, 1, 1, t.hour, t.minute));
  String get _timeLabel => _end == null ? _fmt(_start) : '${_fmt(_start)} – ${_fmt(_end!)}';
  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _pickDate() async {
    setState(() => _loadingDates = true);
    Set<DateTime> locked = {};
    try {
      locked = await BookingRepository.watchLockedDates().first;
    } catch (_) {}
    if (!mounted) return;
    setState(() => _loadingDates = false);

    final today = DateTime.now();
    final first = DateTime(today.year, today.month, today.day);
    final own = widget.booking.date;
    final initial = _date.isBefore(first) ? first : _date;
    final picked = await showDatePicker(
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: first.add(const Duration(days: 365)),
      // Dates held by OTHER bookings are greyed out; this booking's own
      // current date stays selectable so staff can change only the time.
      selectableDayPredicate: (d) => _sameDay(d, own) || !locked.any((l) => _sameDay(l, d)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickStart() async {
    final t = await showTimePicker(context: context, initialTime: _start);
    if (t != null) setState(() => _start = t);
  }

  Future<void> _pickEnd() async {
    final t = await showTimePicker(context: context, initialTime: _end ?? TimeOfDay(hour: (_start.hour + 3) % 24, minute: _start.minute));
    if (t != null) setState(() => _end = t);
  }

  Future<void> _save() async {
    final b = widget.booking;
    final startMin = _start.hour * 60 + _start.minute;
    if (_end != null && (_end!.hour * 60 + _end!.minute) <= startMin) {
      setState(() => _error = "End time must be after the start time.");
      return;
    }
    if (_sameDay(_date, b.date) && _timeLabel == b.time) {
      setState(() => _error = "That's the same date and time — pick something different.");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profile = await AdminService.instance.getProfile();
      final staffId = profile.uid.isEmpty ? null : profile.uid;
      final staffName = profile.name;
      final reason = _reasonController.text.trim();
      await BookingRepository.rescheduleBooking(
        b.id,
        newDate: _date,
        newTime: _timeLabel,
        reason: reason,
        staffId: staffId,
        staffName: staffName,
      ).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DoubleBookingException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't reschedule: $e");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(BuildContext context, {required IconData icon, required String label, required String value, required VoidCallback? onTap}) {
    return InkWell(
      onTap: _saving ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 10.5, color: AppPalette.textMuted(context))),
                  Text(value, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    return AlertDialog(
      backgroundColor: AppPalette.cardBg(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      icon: const Icon(Icons.edit_calendar_outlined, color: AppColors.accent),
      title: const Text("Reschedule booking"),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Currently: ${DateFormat('EEE, MMM d, yyyy').format(b.date)}${b.time.isEmpty ? '' : ' · ${b.time}'}",
                style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)),
              ),
              const SizedBox(height: 12),
              _field(context, icon: Icons.event, label: "New date", value: DateFormat('EEEE, MMM d, yyyy').format(_date), onTap: _loadingDates ? null : _pickDate),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _field(context, icon: Icons.schedule, label: "Start", value: _fmt(_start), onTap: _pickStart)),
                  const SizedBox(width: 8),
                  Expanded(child: _field(context, icon: Icons.schedule_outlined, label: "End (optional)", value: _end == null ? "Not set" : _fmt(_end!), onTap: _pickEnd)),
                  if (_end != null)
                    IconButton(
                      tooltip: "Clear end time",
                      visualDensity: VisualDensity.compact,
                      onPressed: _saving ? null : () => setState(() => _end = null),
                      icon: Icon(Icons.close, size: 16, color: AppPalette.textMuted(context)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reasonController,
                enabled: !_saving,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: "Note to customer (optional)",
                  hintText: "e.g. Moved to a later time as requested",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "The customer gets a notification and their My Bookings updates right away.",
                style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFFC62828), fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text("Cancel")),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text("Reschedule & notify"),
        ),
      ],
    );
  }
}
