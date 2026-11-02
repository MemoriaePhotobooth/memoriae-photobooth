import 'dart:async';

/// One emission from a Firestore listener, reduced to what the cache needs.
/// [fromCache] mirrors `QuerySnapshot.metadata.isFromCache`.
class Synced<T> {
  final List<T> items;
  final bool fromCache;
  const Synced(this.items, {this.fromCache = false});
}

/// Cache-first reads: local database first, cloud second.
///
/// 1. Emit whatever is saved in the local database straight away (so the
///    screen isn't blank on a cold start or with no internet).
/// 2. Listen to the live Firestore stream and emit each update.
/// 3. Write every fresh result back to the local database.
///
/// If the cloud stream fails (offline, rules, etc.) and the local copy was
/// already shown, the error is swallowed so the screen keeps the saved
/// data instead of flipping to an error message. With nothing saved, the
/// error is passed on exactly like before.
class OfflineCache {
  OfflineCache._();

  static Stream<List<T>> cacheFirst<T>({
    required Future<List<T>> Function() readLocal,
    required Stream<Synced<T>> remote,
    required Future<void> Function(List<T> items) writeLocal,
  }) async* {
    var emittedLocal = false;
    try {
      final local = await readLocal();
      if (local.isNotEmpty) {
        emittedLocal = true;
        yield local;
      }
    } catch (_) {
      // A bad local read must never block the cloud data.
    }

    try {
      await for (final snap in remote) {
        // An empty answer that came only from Firestore's own cache (e.g.
        // cold start with no internet) says nothing about the real data —
        // don't let it wipe the saved copy or blank the screen.
        final emptyFromCache = snap.fromCache && snap.items.isEmpty;
        if (emptyFromCache && emittedLocal) continue;
        if (!emptyFromCache) {
          unawaited(writeLocal(snap.items).catchError((_) {}));
        }
        yield snap.items;
      }
    } catch (_) {
      if (!emittedLocal) rethrow;
    }
  }
}
