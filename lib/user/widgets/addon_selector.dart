import 'package:flutter/material.dart';
import '../models/booth_package.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Lets the customer toggle optional add-ons (e.g. Camera Rental) on top
/// of their chosen package. Mirrors `PackageSelector`'s look, but each
/// row is a toggle rather than a single-select choice.
class AddOnSelector extends StatelessWidget {
  final Set<String> selectedIds;
  final ValueChanged<BoothAddOn> onToggle;

  const AddOnSelector({super.key, required this.selectedIds, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.add_circle_outline, size: 16, color: AppColors.accent),
            const SizedBox(width: 8),
            Text("Add-ons", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context))),
          ],
        ),
        const SizedBox(height: 12),
        Column(
          children: kAddOns.map((a) {
            final isSelected = selectedIds.contains(a.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () => onToggle(a),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppPalette.surface(context),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: isSelected ? AppColors.accent : Colors.transparent, width: 2),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                            const SizedBox(height: 4),
                            Text(a.description, style: TextStyle(fontSize: 11, color: AppPalette.textSecondary(context))),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("+${formatPeso(a.price)}", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.accent : Colors.transparent,
                                shape: BoxShape.circle,
                                border: Border.all(color: isSelected ? AppColors.accent : AppPalette.divider(context), width: 2),
                              ),
                              child: isSelected ? const Icon(Icons.check, size: 14, color: AppColors.onAccent) : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
