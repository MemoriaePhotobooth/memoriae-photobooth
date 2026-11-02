import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/announcement_record.dart';
import '../theme/app_palette.dart';

/// One announcement in the customer's list — tinted by type (red for
/// "closed", amber for reminders, blue for general info), with a pin icon
/// when staff pinned it to the top.
class AnnouncementCard extends StatelessWidget {
  final AnnouncementRecord announcement;

  const AnnouncementCard({super.key, required this.announcement});

  @override
  Widget build(BuildContext context) {
    final a = announcement;
    final color = AnnouncementType.color(a.type);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(AnnouncementType.icon(a.type), size: 19, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        AnnouncementType.label(a.type).toUpperCase(),
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: color),
                      ),
                    ),
                    if (a.pinned) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.push_pin_rounded, size: 14, color: AppPalette.textMuted(context)),
                      const SizedBox(width: 2),
                      Text("Pinned", style: TextStyle(fontSize: 10.5, color: AppPalette.textMuted(context))),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  a.title,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
                ),
                const SizedBox(height: 4),
                Text(
                  a.message,
                  style: TextStyle(fontSize: 13, height: 1.4, color: AppPalette.textSecondary(context)),
                ),
                const SizedBox(height: 10),
                Text(
                  "${a.createdByName.isEmpty ? 'Memoriae Staff' : a.createdByName} · ${DateFormat('MMM d, yyyy · h:mm a').format(a.createdAt)}",
                  style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
