import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/announcement_record.dart';
import '../models/booth_package.dart';
import '../models/camera_rental.dart';

/// The customer app's on-device SQLite database.
///
/// Firestore stays the source of truth (cloud database). This is the
/// local copy the app reads first, so screens show something instantly on
/// a cold start and keep working with no internet:
///
///   packages        - booth packages (from `pricing`, category "Booth Package")
///   camera_options  - rentable cameras (from `pricing`, category "Camera Rental")
///   announcements   - staff announcements
///   bookings        - the signed-in customer's own bookings
///   sync_meta       - when each dataset was last synced from the cloud
///
/// Flow (see `offline_cache.dart`): read local -> show -> listen to
/// Firestore -> write fresh data back to local -> show.
///
/// Every method is safe to call anywhere: if SQLite isn't available on the
/// platform (web, Windows, Linux) or anything fails, reads return empty and
/// writes do nothing, so the app simply behaves as it did before this file
/// existed — it never throws into the UI.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  static const String _dbName = 'memoriae_user.db';
  static const int _version = 4;

  /// sqflite only ships for Android, iOS and macOS.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<Database?>? _opening;

  Future<Database?> _open() {
    if (!isSupported) return Future.value(null);
    return _opening ??= _openReal();
  }

  Future<Database?> _openReal() async {
    try {
      final dir = await getDatabasesPath();
      return await openDatabase(
        p.join(dir, _dbName),
        version: _version,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      debugPrint('LocalDb: could not open database: $e');
      return null;
    }
  }

  /// v1 -> v2: packages gained a `description` column.
  /// v2 -> v3: camera_options gained `rate8plus` (per-day rate for 8+ days).
  /// v3 -> v4: camera_options gained `rate5to7` (per-day rate for 5-7 days).
  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE packages ADD COLUMN description TEXT NOT NULL DEFAULT ''");
    }
    if (oldVersion < 3) {
      await db.execute("ALTER TABLE camera_options ADD COLUMN rate8plus INTEGER NOT NULL DEFAULT 0");
    }
    if (oldVersion < 4) {
      await db.execute("ALTER TABLE camera_options ADD COLUMN rate5to7 INTEGER NOT NULL DEFAULT 0");
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE packages (
        id          TEXT PRIMARY KEY,
        name        TEXT NOT NULL,
        duration    TEXT NOT NULL,
        price       INTEGER NOT NULL,
        features    TEXT NOT NULL,
        image_url   TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        updated_at  INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE camera_options (
        id           TEXT PRIMARY KEY,
        name         TEXT NOT NULL,
        description  TEXT NOT NULL,
        daily_rate   INTEGER NOT NULL,
        rate8plus    INTEGER NOT NULL DEFAULT 0,
        rate5to7     INTEGER NOT NULL DEFAULT 0,
        icon         TEXT NOT NULL,
        image_url    TEXT NOT NULL DEFAULT '',
        updated_at   INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE announcements (
        id               TEXT PRIMARY KEY,
        title            TEXT NOT NULL,
        message          TEXT NOT NULL,
        type             TEXT NOT NULL,
        pinned           INTEGER NOT NULL DEFAULT 0,
        created_by_name  TEXT NOT NULL DEFAULT '',
        created_at       INTEGER NOT NULL,
        updated_at       INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE bookings (
        id          TEXT PRIMARY KEY,
        user_id     TEXT NOT NULL,
        status      TEXT NOT NULL DEFAULT '',
        created_at  INTEGER NOT NULL DEFAULT 0,
        data        TEXT NOT NULL,
        updated_at  INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_bookings_user ON bookings (user_id, created_at DESC)');
    await db.execute('''
      CREATE TABLE sync_meta (
        dataset    TEXT PRIMARY KEY,
        synced_at  INTEGER NOT NULL
      )
    ''');
  }

  // ---------------------------------------------------------------- helpers

  /// Replaces the rows of [table] (optionally only those matching [where])
  /// and stamps [dataset] in `sync_meta`, all in one transaction so a
  /// half-written cache can never be read.
  Future<void> _replace(
    String table,
    String dataset,
    List<Map<String, Object?>> rows, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    try {
      final db = await _open();
      if (db == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.transaction((txn) async {
        await txn.delete(table, where: where, whereArgs: whereArgs);
        final batch = txn.batch();
        for (final row in rows) {
          batch.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        batch.insert(
          'sync_meta',
          {'dataset': dataset, 'synced_at': now},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await batch.commit(noResult: true);
      });
    } catch (e) {
      debugPrint('LocalDb: write to $table failed: $e');
    }
  }

  Future<List<Map<String, Object?>>> _query(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
  }) async {
    try {
      final db = await _open();
      if (db == null) return const [];
      return await db.query(table, where: where, whereArgs: whereArgs, orderBy: orderBy);
    } catch (e) {
      debugPrint('LocalDb: read from $table failed: $e');
      return const [];
    }
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  static List<String> _decodeStringList(Object? raw) {
    try {
      return (jsonDecode(raw as String) as List).map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  // --------------------------------------------------------------- packages

  Future<void> replacePackages(List<BoothPackage> items) {
    final now = _now();
    return _replace('packages', 'packages', [
      for (final x in items)
        {
          'id': x.id,
          'name': x.name,
          'duration': x.duration,
          'price': x.price,
          'features': jsonEncode(x.features),
          'image_url': x.imageUrl,
          'description': x.description,
          'updated_at': now,
        },
    ]);
  }

  Future<List<BoothPackage>> loadPackages() async {
    final rows = await _query('packages');
    return [
      for (final r in rows)
        BoothPackage(
          id: r['id'] as String,
          name: r['name'] as String,
          duration: r['duration'] as String,
          price: (r['price'] as num).toInt(),
          features: _decodeStringList(r['features']),
          imageUrl: (r['image_url'] as String?) ?? '',
          description: (r['description'] as String?) ?? '',
        ),
    ];
  }

  // ---------------------------------------------------------------- cameras

  Future<void> replaceCameraOptions(List<CameraOption> items) {
    final now = _now();
    return _replace('camera_options', 'camera_options', [
      for (final x in items)
        {
          'id': x.id,
          'name': x.name,
          'description': x.description,
          'daily_rate': x.dailyRate,
          'rate8plus': x.rate8Plus,
          'rate5to7': x.rate5to7,
          'icon': x.icon,
          'image_url': x.imageUrl,
          'updated_at': now,
        },
    ]);
  }

  Future<List<CameraOption>> loadCameraOptions() async {
    final rows = await _query('camera_options');
    return [
      for (final r in rows)
        CameraOption(
          id: r['id'] as String,
          name: r['name'] as String,
          description: r['description'] as String,
          dailyRate: (r['daily_rate'] as num).toInt(),
          rate8Plus: ((r['rate8plus'] as num?) ?? 0).toInt(),
          rate5to7: ((r['rate5to7'] as num?) ?? 0).toInt(),
          icon: r['icon'] as String,
          imageUrl: (r['image_url'] as String?) ?? '',
        ),
    ];
  }

  // ----------------------------------------------------------- announcements

  Future<void> replaceAnnouncements(List<AnnouncementRecord> items) {
    final now = _now();
    return _replace('announcements', 'announcements', [
      for (final x in items)
        {
          'id': x.id,
          'title': x.title,
          'message': x.message,
          'type': x.type,
          'pinned': x.pinned ? 1 : 0,
          'created_by_name': x.createdByName,
          'created_at': x.createdAt.millisecondsSinceEpoch,
          'updated_at': now,
        },
    ]);
  }

  /// Pinned first, then newest first — same order the cloud stream uses.
  Future<List<AnnouncementRecord>> loadAnnouncements() async {
    final rows = await _query('announcements', orderBy: 'pinned DESC, created_at DESC');
    return [
      for (final r in rows)
        AnnouncementRecord(
          id: r['id'] as String,
          title: r['title'] as String,
          message: r['message'] as String,
          type: r['type'] as String,
          pinned: (r['pinned'] as num) == 1,
          createdByName: (r['created_by_name'] as String?) ?? '',
          createdAt: DateTime.fromMillisecondsSinceEpoch((r['created_at'] as num).toInt()),
        ),
    ];
  }

  // --------------------------------------------------------------- bookings

  /// Firestore [Timestamp]s aren't JSON — store them as `{"__ts": millis}`
  /// and turn them back into Timestamps on read (see [_revive]).
  static Object? _encodable(Object? o) {
    if (o is Timestamp) return {'__ts': o.millisecondsSinceEpoch};
    return o.toString();
  }

  static dynamic _revive(dynamic v) {
    if (v is Map) {
      if (v.length == 1 && v['__ts'] is int) {
        return Timestamp.fromMillisecondsSinceEpoch(v['__ts'] as int);
      }
      return {for (final e in v.entries) e.key as String: _revive(e.value)};
    }
    if (v is List) return v.map(_revive).toList();
    return v;
  }

  static int _millisOf(dynamic ts) => ts is Timestamp ? ts.millisecondsSinceEpoch : 0;

  /// Saves [bookings] as the customer's complete list (anything no longer
  /// in the cloud is removed locally too). The receipt photo
  /// (`receiptUrl`, a base64 `data:` URI) is left out to keep the database
  /// small — the customer app only ever writes that field, never reads it.
  Future<void> replaceBookingsForUser(String userId, List<Map<String, dynamic>> bookings) {
    final now = _now();
    return _replace(
      'bookings',
      'bookings:$userId',
      [
        for (final b in bookings)
          {
            'id': b['id'] as String,
            'user_id': userId,
            'status': (b['status'] ?? '').toString(),
            'created_at': _millisOf(b['createdAt']),
            'data': jsonEncode(_slim(b), toEncodable: _encodable),
            'updated_at': now,
          },
      ],
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  static Map<String, dynamic> _slim(Map<String, dynamic> b) {
    final copy = Map<String, dynamic>.from(b);
    final receipt = copy['receiptUrl'];
    if (receipt is String && receipt.startsWith('data:')) copy['receiptUrl'] = '';
    return copy;
  }

  Future<List<Map<String, dynamic>>> loadBookingsForUser(String userId) async {
    final rows = await _query(
      'bookings',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      try {
        final map = _revive(jsonDecode(r['data'] as String)) as Map<String, dynamic>;
        out.add({...map, 'id': r['id']});
      } catch (_) {
        // Skip a corrupt row rather than failing the whole list.
      }
    }
    return out;
  }

  /// Wipes the per-customer data. Called on logout so the next person to
  /// use the phone can't see the previous customer's bookings.
  Future<void> clearUserData() async {
    try {
      final db = await _open();
      if (db == null) return;
      await db.transaction((txn) async {
        await txn.delete('bookings');
        await txn.delete('sync_meta', where: "dataset LIKE 'bookings:%'");
      });
    } catch (e) {
      debugPrint('LocalDb: clearUserData failed: $e');
    }
  }

  // -------------------------------------------------------------- sync info

  /// When any dataset was last refreshed from the cloud (null = never).
  Future<DateTime?> lastSyncedAt() async {
    try {
      final db = await _open();
      if (db == null) return null;
      final rows = await db.rawQuery('SELECT MAX(synced_at) AS t FROM sync_meta');
      final t = rows.isEmpty ? null : rows.first['t'];
      return t is num ? DateTime.fromMillisecondsSinceEpoch(t.toInt()) : null;
    } catch (_) {
      return null;
    }
  }
}
