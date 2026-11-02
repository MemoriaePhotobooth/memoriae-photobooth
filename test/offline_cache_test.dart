import 'package:flutter_test/flutter_test.dart';
import 'package:memoriae_photobooth/user/services/offline_cache.dart';

void main() {
  group('OfflineCache.cacheFirst', () {
    test('emits the saved copy first, then the cloud data, and saves the cloud data', () async {
      final saved = <List<int>>[];
      final out = await OfflineCache.cacheFirst<int>(
        readLocal: () async => [1],
        remote: Stream.fromIterable([const Synced<int>([2, 3])]),
        writeLocal: (items) async => saved.add(items),
      ).toList();

      expect(out, [
        [1],
        [2, 3],
      ]);
      expect(saved, [
        [2, 3],
      ]);
    });

    test('keeps showing the saved copy when the cloud stream fails (offline)', () async {
      final out = await OfflineCache.cacheFirst<int>(
        readLocal: () async => [1],
        remote: Stream<Synced<int>>.error(Exception('offline')),
        writeLocal: (_) async {},
      ).toList();

      expect(out, [
        [1],
      ]);
    });

    test('passes the error on when nothing is saved yet', () async {
      final stream = OfflineCache.cacheFirst<int>(
        readLocal: () async => [],
        remote: Stream<Synced<int>>.error(Exception('offline')),
        writeLocal: (_) async {},
      );

      await expectLater(stream, emitsError(isA<Exception>()));
    });

    test('an empty answer that only came from Firestore\'s cache does not wipe saved data', () async {
      final saved = <List<int>>[];
      final out = await OfflineCache.cacheFirst<int>(
        readLocal: () async => [1],
        remote: Stream.fromIterable([const Synced<int>([], fromCache: true)]),
        writeLocal: (items) async => saved.add(items),
      ).toList();

      expect(out, [
        [1],
      ]);
      expect(saved, isEmpty);
    });

    test('an empty answer from the server does replace the saved data', () async {
      final saved = <List<int>>[];
      final out = await OfflineCache.cacheFirst<int>(
        readLocal: () async => [1],
        remote: Stream.fromIterable([const Synced<int>([])]),
        writeLocal: (items) async => saved.add(items),
      ).toList();

      expect(out, [
        [1],
        <int>[],
      ]);
      expect(saved, [<int>[]]);
    });
  });
}
