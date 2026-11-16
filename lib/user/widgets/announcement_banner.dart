import 'package:flutter/material.dart';
import '../models/announcement_record.dart';
import '../services/announcement_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import 'stream_once.dart';

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
    return StreamOnce<List<AnnouncementRecord>>(
      create: () => AnnouncementRepository.watchAll(),
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <AnnouncementRecord>[];
        final cutoff = DateTime.now().subtract(const Duration(hours: 48));
        final recent = all.where((a) => a.pinned || a.createdAt.isAfter(cutoff)).toList();
        if (recent.isEmpty) return const SizedBox.shrink();
        final shown = recent.take(2).toList();
        final color = AnnouncementType.color(shown.first.type);

        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final a in shown) _BannerTile(announcement: a, onTap: () => _openAll(context)),
              GestureDetector(
                onTap: () => _openAll(context),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        all.length > shown.length ? "View all announcements (${all.length})" : "View announcements",
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, size: 15, color: color),
                    ],
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

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${t.month}/${t.day}';
}

class _BannerTile extends StatelessWidget {
  final AnnouncementRecord announcement;
  final VoidCallback onTap;

  const _BannerTile({required this.announcement, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = announcement;
    final color = AnnouncementType.color(a.type);
    final base = AppPalette.cardBg(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), boxShadow: AppShadows.soft),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Container(
            decoration: BoxDecoration(
              color: Color.alphaBlend(color.withValues(alpha: 0.07), base),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: color.withValues(alpha: 0.22)),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 5, color: color),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(AnnouncementType.icon(a.type), color: color, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        AnnouncementType.label(a.type),
                                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color),
                                      ),
                                    ),
                                    if (a.pinned) ...[
                                      const SizedBox(width: 6),
                                      Icon(Icons.push_pin_rounded, size: 13, color: color),
                                    ],
                                    const Spacer(),
                                    Text(_ago(a.createdAt), style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  a.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                    letterSpacing: -0.2,
                                    color: AppPalette.textPrimary(context),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  a.message,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12.5, height: 1.4, color: AppPalette.textSecondary(context)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
