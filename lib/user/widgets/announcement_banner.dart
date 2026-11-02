import 'package:flutter/material.dart';
import '../models/announcement_record.dart';
import '../services/announcement_repository.dart';
import '../theme/app_palette.dart';

/// Inline banner for the Home screen so a staff announcement (e.g. "closed
/// today") can't be missed. Shows up to two announcements that are either
/// pinned or were posted in the last 48 hours; older ones stay reachable
/// from the Announcements tab. Renders nothing when there's nothing recent.
class AnnouncementBanner extends StatelessWidget {
  const AnnouncementBanner({super.key});

  void _openAll(BuildContext context) {
    Navigator.of(context).pushReplacementNamed('/announcements');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AnnouncementRecord>>(
      stream: AnnouncementRepository.watchAll(),
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <AnnouncementRecord>[];
        final cutoff = DateTime.now().subtract(const Duration(hours: 48));
        final recent = all.where((a) => a.pinned || a.createdAt.isAfter(cutoff)).toList();
        if (recent.isEmpty) return const SizedBox.shrink();
        final shown = recent.take(2).toList();

        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final a in shown) _BannerTile(announcement: a, onTap: () => _openAll(context)),
              GestureDetector(
                onTap: () => _openAll(context),
                child: Padding(
                  padding: const EdgeInsets.only(left: 2, top: 2),
                  child: Text(
                    all.length > shown.length ? "View all announcements (${all.length})" : "View announcements",
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: AnnouncementType.color(shown.first.type),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BannerTile extends StatelessWidget {
  final AnnouncementRecord announcement;
  final VoidCallback onTap;

  const _BannerTile({required this.announcement, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = announcement;
    final color = AnnouncementType.color(a.type);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(AnnouncementType.icon(a.type), color: color, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    a.message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, height: 1.35, color: AppPalette.textSecondary(context)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
