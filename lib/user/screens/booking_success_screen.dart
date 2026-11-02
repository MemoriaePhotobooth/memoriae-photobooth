import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/booth_package.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// The original React file imports `BookingSuccess` from
/// "@/components/BookingSuccess" but that component's source wasn't
/// provided, so this is a faithful, style-matched reconstruction that
/// takes the same props: pkg, date, time, onReset.
///
/// Rendered as the `child` content inside `AppLayoutShell`, matching how
/// the React version still renders inside `<Outlet/>` (frame + BottomNav
/// stay visible) when the booking form's `submitted` state flips.
class BookingSuccessScreen extends StatelessWidget {
  final BoothPackage pkg;
  final List<BoothAddOn> addOns;
  final DateTime date;
  final String time;
  final String? location;
  final VoidCallback onReset;

  const BookingSuccessScreen({
    super.key,
    required this.pkg,
    this.addOns = const [],
    required this.date,
    required this.time,
    this.location,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.accentTint(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle, color: AppColors.accent, size: 40),
            ),
            const SizedBox(height: 20),
            Text(
              "Booking Confirmed!",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
            ),
            const SizedBox(height: 6),
            Text(
              "We've received your receipt and reserved your slot.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppPalette.textSecondary(context)),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(20)),
              child: Column(
                children: [
                  _row(context, "Package", pkg.name),
                  const SizedBox(height: 8),
                  _row(context, "Date & Time", "${DateFormat('MMM d').format(date)} · $time"),
                  if (location != null && location!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _row(context, "Location", location!),
                  ],
                  const SizedBox(height: 8),
                  _row(context, "Duration", pkg.duration),
                  for (final a in addOns) ...[
                    const SizedBox(height: 8),
                    _row(context, a.name, "+${formatPeso(a.price)}"),
                  ],
                  Divider(height: 24, color: AppPalette.divider(context)),
                  _row(
                    context,
                    "Total Paid",
                    formatPeso(pkg.price + addOns.fold(0, (sum, a) => sum + a.price)),
                    bold: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onReset,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: const Text("Make Another Booking", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: bold ? 14 : 12,
            color: bold ? AppPalette.textPrimary(context) : AppPalette.textSecondary(context),
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(value, style: TextStyle(fontSize: bold ? 20 : 12, color: AppPalette.textPrimary(context), fontWeight: FontWeight.bold)),
      ],
    );
  }
}
