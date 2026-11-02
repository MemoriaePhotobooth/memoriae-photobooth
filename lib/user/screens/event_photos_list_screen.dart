import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/auth_service.dart';
import '../services/booking_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/circle_back_button.dart';
import 'event_photos_screen.dart';

/// Every event photo the customer can see, grouped by booking. Each row opens
/// that booking's photos. Only bookings that are confirmed or completed and
/// have photos from staff are listed.
class EventPhotosListScreen extends StatelessWidget {
  const EventPhotosListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.instance.currentUid ?? '';
    final signedIn = FirebaseAuth.instance.currentUser != null && uid.isNotEmpty;

    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        leading: const CircleBackButton.appBar(),
        leadingWidth: CircleBackButton.appBarLeadingWidth,
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppPalette.textPrimary(context)),
        title: Text(
          'Event Photos',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
        ),
      ),
      body: !signedIn
          ? _message(context, Icons.lock_outline, 'Log in to see the photos from your events.')
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: BookingRepository.watchBookingsForUser(uid),
              builder: (context, snap) {
                if (snap.hasError) {
                  return _message(context, Icons.error_outline, "Couldn't load your photos. Please try again.");
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent));
                }
                final withPhotos = snap.data!.where((b) {
                  final status = b['status'] as String? ?? '';
                  final count = (b['eventPhotoCount'] as num?)?.toInt() ?? 0;
                  return (status == 'confirmed' || status == 'completed') && count > 0;
                }).toList();

                if (withPhotos.isEmpty) {
                  return _message(
                    context,
                    Icons.photo_library_outlined,
                    'No event photos yet. Photos from your booking will show up here.',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  itemCount: withPhotos.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final b = withPhotos[i];
                    final count = (b['eventPhotoCount'] as num).toInt();
                    final ts = b['date'];
                    final dateLabel = ts is Timestamp ? DateFormat('MMM d, yyyy').format(ts.toDate()) : '';
                    return Material(
                      color: AppPalette.surface(context),
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EventPhotosScreen(
                              bookingId: b['id'] as String,
                              userId: uid,
                              title: (b['packageName'] as String?) ?? 'Event Photos',
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppColors.accentTint(0.10),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.photo_library_outlined, size: 18, color: AppColors.accent),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (b['packageName'] as String?) ?? 'Booking',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context)),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      dateLabel.isEmpty ? '$count photos' : '$dateLabel · $count photos',
                                      style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded, size: 20, color: AppPalette.textMuted(context)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _message(BuildContext context, IconData icon, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppPalette.textMuted(context)),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.45, color: AppPalette.textSecondary(context)),
            ),
          ],
        ),
      ),
    );
  }
}
