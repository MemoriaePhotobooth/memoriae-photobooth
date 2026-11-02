import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Tells the UI whether the phone currently has a network connection.
///
/// [isOnline] is a plain [ValueNotifier], so any widget can listen with a
/// `ValueListenableBuilder`. It starts as `true` (assume online) until the
/// first real reading arrives, and stays `true` if the plugin isn't
/// available — an unknown state never shows a false "offline" warning.
///
/// Note: this reports whether a network interface (Wi-Fi/mobile data) is
/// connected, not whether the internet is reachable behind it.
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _started = false;

  /// Safe to call many times; only the first call does anything.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final connectivity = Connectivity();
      _apply(await connectivity.checkConnectivity());
      _sub = connectivity.onConnectivityChanged.listen(_apply, onError: (_) {});
    } catch (e) {
      debugPrint('ConnectivityService: unavailable, assuming online ($e)');
    }
  }

  void _apply(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (isOnline.value != online) isOnline.value = online;
  }

  @visibleForTesting
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
  }
}
