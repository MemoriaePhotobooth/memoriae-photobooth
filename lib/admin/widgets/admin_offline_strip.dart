import 'package:flutter/material.dart';

import '../../shared/connectivity_service.dart';

/// Amber strip shown only while the phone has no connection. Takes no space
/// while online.
class AdminOfflineStrip extends StatelessWidget {
  const AdminOfflineStrip({super.key});

  @override
  Widget build(BuildContext context) {
    ConnectivityService.instance.start(); // idempotent
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.instance.isOnline,
      builder: (context, online, _) {
        if (online) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4DE),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE08A00).withValues(alpha: 0.4)),
          ),
          child: const Row(
            children: [
              Icon(Icons.cloud_off_rounded, size: 18, color: Color(0xFFE08A00)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "You're offline. Changes are kept on this phone and sync when the connection is back.",
                  style: TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF7A4D00)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
