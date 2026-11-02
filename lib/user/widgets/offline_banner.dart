import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/connectivity_service.dart';
import '../services/local_db.dart';

/// A slim strip at the top of every tab: amber "You're offline" while
/// there's no connection (with when the saved data was last synced), then
/// a brief green "Back online" once it returns. Takes no space while
/// online.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  final _service = ConnectivityService.instance;

  bool _wasOffline = false;
  bool _showBackOnline = false;
  DateTime? _lastSynced;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _service.start();
    _wasOffline = !_service.isOnline.value;
    _service.isOnline.addListener(_onChanged);
    if (_wasOffline) _loadLastSynced();
  }

  @override
  void dispose() {
    _service.isOnline.removeListener(_onChanged);
    _hideTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLastSynced() async {
    final t = await LocalDb.instance.lastSyncedAt();
    if (mounted) setState(() => _lastSynced = t);
  }

  void _onChanged() {
    final online = _service.isOnline.value;
    if (!online) {
      _hideTimer?.cancel();
      _wasOffline = true;
      setState(() => _showBackOnline = false);
      _loadLastSynced();
    } else if (_wasOffline) {
      _wasOffline = false;
      setState(() => _showBackOnline = true);
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showBackOnline = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = _service.isOnline.value;

    Widget? bar;
    if (!online) {
      final synced = _lastSynced;
      final detail = synced == null
          ? "Showing saved data."
          : "Showing saved data · last synced ${DateFormat('MMM d, h:mm a').format(synced)}";
      bar = _bar(
        key: const ValueKey('offline'),
        color: const Color(0xFFB7791F),
        icon: Icons.wifi_off_rounded,
        title: "You're offline",
        detail: detail,
      );
    } else if (_showBackOnline) {
      bar = _bar(
        key: const ValueKey('online'),
        color: const Color(0xFF2E7D32),
        icon: Icons.cloud_done_rounded,
        title: "Back online",
        detail: "Syncing your latest data…",
      );
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: bar ?? const SizedBox(width: double.infinity),
    );
  }

  Widget _bar({
    required Key key,
    required Color color,
    required IconData icon,
    required String title,
    required String detail,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: '  $detail'),
                ],
              ),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
