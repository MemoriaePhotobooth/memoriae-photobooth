import 'package:flutter/material.dart';
import '../models/camera_rental_record.dart';
import '../models/message_record.dart';
import '../services/camera_rental_repository.dart';
import '../theme/app_palette.dart';

/// Card for a booking or camera the customer shared. Cameras show live
/// availability (a rental with no return date means it is out).
Widget buildRefCard(BuildContext context, MessageRecord m, {required bool mine, required Color textColor}) {
  final isCamera = m.refType == 'camera';
  final muted = mine ? Colors.white.withValues(alpha: 0.8) : AppPalette.textMuted(context);
  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: mine ? Colors.white.withValues(alpha: 0.14) : AppPalette.surface(context),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(isCamera ? 'CAMERA' : 'BOOKING',
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: muted)),
        const SizedBox(height: 2),
        Text(m.refTitle, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: textColor)),
        if (m.refSubtitle.isNotEmpty)
          Text(m.refSubtitle, style: TextStyle(fontSize: 11.5, color: muted)),
        if (isCamera) ...[
          const SizedBox(height: 6),
          _staffCameraStatus(context, m.refId, mine: mine),
        ],
      ],
    ),
  );
}

Widget _staffCameraStatus(BuildContext context, String cameraId, {required bool mine}) {
  return StreamBuilder<List<CameraRentalRecord>>(
    stream: CameraRentalRepository.watchAllRentals(),
    builder: (context, snap) {
      if (!snap.hasData) {
        return Text('Checking availability…',
            style: TextStyle(fontSize: 11.5, color: mine ? Colors.white.withValues(alpha: 0.8) : AppPalette.textMuted(context)));
      }
      final out = snap.data!.any((r) => r.cameraId == cameraId && r.returnedAt == null);
      final color = out ? Colors.redAccent : const Color(0xFF34C759);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(out ? 'Rented out right now' : 'Available now',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
        ],
      );
    },
  );
}

