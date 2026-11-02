import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Birthdate picker with a calendar and a typed-entry mode.
///
/// Unlike the stock `showDatePicker` text box, typing is masked as
/// MM/DD/YYYY and stops at 8 digits — so the year can never be longer than
/// 4 digits — and the date is validated live with the same rules as the
/// register form: not in the future, year [firstDate].year or later, and at
/// least [minAge] years old (so 9 and below is rejected).
///
/// Returns the picked date, or null if cancelled.
Future<DateTime?> showBirthDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required int minAge,
  String helpText = 'Select your birthdate',
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _BirthDateDialog(
      initialDate: initialDate,
      firstDate: firstDate,
      minAge: minAge,
      helpText: helpText,
    ),
  );
}

class _DateMask extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 8) digits = digits.substring(0, 8); // MMDDYYYY → max 4-digit year
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 4) b.write('/');
      b.write(digits[i]);
    }
    final text = b.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

class _BirthDateDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final int minAge;
  final String helpText;

  const _BirthDateDialog({
    required this.initialDate,
    required this.firstDate,
    required this.minAge,
    required this.helpText,
  });

  @override
  State<_BirthDateDialog> createState() => _BirthDateDialogState();
}

class _BirthDateDialogState extends State<_BirthDateDialog> {
  late DateTime _youngest;
  late DateTime _selected;
  bool _typing = false;
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _youngest = DateTime(now.year - widget.minAge, now.month, now.day);
    _selected = widget.initialDate.isAfter(_youngest) ? _youngest : widget.initialDate;
    _controller = TextEditingController(text: DateFormat('MM/dd/yyyy').format(_selected));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Parses the typed text; null while incomplete or invalid. Sets [_error].
  DateTime? _parseTyped() {
    final digits = _controller.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8) {
      _error = null; // still typing
      return null;
    }
    final m = int.parse(digits.substring(0, 2));
    final d = int.parse(digits.substring(2, 4));
    final y = int.parse(digits.substring(4, 8));
    final date = DateTime(y, m, d);
    if (date.year != y || date.month != m || date.day != d) {
      _error = "Enter a valid date.";
      return null;
    }
    if (date.isAfter(DateTime.now())) {
      _error = "Birthdate can't be in the future.";
      return null;
    }
    if (y < widget.firstDate.year) {
      _error = "Birth year must be ${widget.firstDate.year} or later.";
      return null;
    }
    if (date.isAfter(_youngest)) {
      _error = "You must be at least ${widget.minAge} years old to register.";
      return null;
    }
    _error = null;
    return date;
  }

  bool get _canSubmit => _typing ? _validTyped != null : true;
  DateTime? _validTyped;

  void _onTextChanged(String _) {
    setState(() => _validTyped = _parseTyped());
  }

  void _toggleMode() {
    setState(() {
      if (_typing) {
        // typed → calendar: keep the typed date if it was valid
        if (_validTyped != null) _selected = _validTyped!;
      } else {
        _controller.text = DateFormat('MM/dd/yyyy').format(_selected);
        _validTyped = _parseTyped();
      }
      _typing = !_typing;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final shownDate = _typing ? (_validTyped ?? _selected) : _selected;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(widget.helpText, style: theme.textTheme.labelMedium),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        DateFormat('EEE, MMM d, yyyy').format(shownDate),
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: _typing ? 'Switch to calendar' : 'Switch to typing',
                      onPressed: _toggleMode,
                      icon: Icon(_typing ? Icons.calendar_today_outlined : Icons.edit_outlined),
                    ),
                  ],
                ),
              ),
              const Divider(height: 16),
              if (_typing)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [_DateMask()],
                    maxLength: 10, // MM/DD/YYYY
                    onChanged: _onTextChanged,
                    decoration: InputDecoration(
                      labelText: 'Enter date',
                      hintText: 'mm/dd/yyyy',
                      counterText: '',
                      errorText: _error,
                      errorMaxLines: 2,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                )
              else
                CalendarDatePicker(
                  initialDate: _selected,
                  firstDate: widget.firstDate,
                  lastDate: _youngest, // under-minAge dates can't be picked
                  onDateChanged: (d) => setState(() => _selected = d),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: accent),
                    onPressed: _canSubmit
                        ? () => Navigator.of(context).pop(_typing ? _validTyped : _selected)
                        : null,
                    child: const Text('OK'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
