import 'package:flutter/material.dart';
import '../models/announcement_record.dart';
import '../services/announcement_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/announcement_card.dart';
import '../widgets/stream_once.dart';

/// Every announcement staff have posted (e.g. "Photobooth is closed
/// today"), pinned ones first and then newest first. Read-only — staff
/// post and delete these from the Staff app.
class UserAnnouncementsScreen extends StatelessWidget {
  const UserAnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.accentTint(0.12), shape: BoxShape.circle),
                child: const Icon(Icons.campaign_rounded, size: 21, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Announcements", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                    Text("News and updates from Memoriae staff.", style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamOnce<List<AnnouncementRecord>>(
            create: () => AnnouncementRepository.watchAll(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      "Couldn't load announcements right now. Please try again later.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator(color: AppColors.accent));
              }
              final list = snapshot.data!;
              if (list.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      "No announcements yet. Check back here for updates from staff.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
                    ),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                itemCount: list.length,
                itemBuilder: (context, i) => AnnouncementCard(announcement: list[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}
