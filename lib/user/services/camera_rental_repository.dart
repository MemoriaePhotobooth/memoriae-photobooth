import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/camera_rental.dart';

/// Firebase-backed camera rental repository — reads/writes the
/// `cameraRentals` collection the Admin and Staff apps also read from
/// (see their own `CameraRentalRepository`), plus a one-document-per-camera
/// `cameraLocks` collection that stops two customers from renting the same
/// physical unit at once (the same idea as `dateHolds` for bookings, just
/// keyed by camera instead of by date).
///
/// Requires `Firebase.initializeApp()` to have already run (see `main.dart`).
class CameraRentalRepository {
  CameraRentalRepository._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('cameraRentals');

  static DocumentReference<Map<String, dynamic>> _lockRef(String cameraId) =>
      FirebaseFirestore.instance.collection('cameraLocks').doc(cameraId);

  static CameraRental _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final rentedAt = (d['rentedAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final dueAt = (d['dueAt'] as Timestamp?)?.toDate() ?? rentedAt;
    return CameraRental(
      id: doc.id,
      userId: (d['userId'] ?? '') as String,
      cameraId: (d['cameraId'] ?? '') as String,
      cameraName: (d['cameraName'] ?? '') as String,
      dailyRate: (d['dailyRate'] ?? 0) as int,
      totalPrice: (d['totalPrice'] ?? 0) as int,
      duration: Duration(hours: (d['durationHours'] ?? 24) as int),
      rentedAt: rentedAt,
      dueAt: dueAt,
      returnedAt: (d['returnedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Live stream of every camera currently checked out, by any user — the
  /// Rent screen uses this to grey out a camera and show whoever is
  /// browsing it when it'll be free again, without exposing who has it.
  static Stream<List<CameraRental>> watchAllActiveRentals() {
    return _col.where('returnedAt', isNull: true).snapshots().map(
          (snap) => snap.docs.map(_fromDoc).toList(),
        );
  }

  /// Live stream of every camera the customer currently has checked out
  /// (empty list if none) — the Rent screen renders one countdown card
  /// per entry, soonest-due first.
  static Stream<List<CameraRental>> watchActiveRentalsForUser(String userId) {
    return _col.where('userId', isEqualTo: userId).where('returnedAt', isNull: true).snapshots().map((snap) {
      final list = snap.docs.map(_fromDoc).toList()..sort((a, b) => a.dueAt.compareTo(b.dueAt));
      return list;
    });
  }

  /// Live stream of every rental the customer has ever made, active and
  /// returned (newest first). Used for the Profile page's rental count and
  /// total — [watchActiveRentalsForUser] only has the ones still checked out.
  static Stream<List<CameraRental>> watchRentalsForUser(String userId) {
    return _col.where('userId', isEqualTo: userId).snapshots().map((snap) {
      final list = snap.docs.map(_fromDoc).toList()..sort((a, b) => b.rentedAt.compareTo(a.rentedAt));
      return list;
    });
  }

  static String _formatDueDate(DateTime dueAt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dueAt.month)}/${two(dueAt.day)}/${dueAt.year} ${two(dueAt.hour)}:${two(dueAt.minute)}';
  }

  /// Checks out [camera] for [durationOption], failing if it's already
  /// rented to someone else. The check-then-write is done atomically
  /// against `cameraLocks/{camera.id}` — a Firestore transaction can only
  /// read by direct document reference (not run a query), which is why
  /// this needs its own lock doc rather than querying `cameraRentals` for
  /// an existing active one inside the transaction.
  static Future<CameraRental> createRental({
    required String userId,
    required CameraOption camera,
    required RentalDurationOption durationOption,
  }) async {
    final now = DateTime.now();
    final dueAt = now.add(durationOption.duration);
    final totalPrice = durationOption.priceFor(camera.dailyRate, rate8Plus: camera.rate8Plus, rate5to7: camera.rate5to7);
    final rentalRef = _col.doc();
    final lockRef = _lockRef(camera.id);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final lockSnap = await tx.get(lockRef);
      if (lockSnap.exists) {
        final existingDue = (lockSnap.data()?['dueAt'] as Timestamp?)?.toDate();
        throw Exception(
          '${camera.name} is already rented${existingDue != null ? ' until ${_formatDueDate(existingDue)}' : ''}.',
        );
      }
      tx.set(lockRef, {'rentalId': rentalRef.id, 'dueAt': Timestamp.fromDate(dueAt)});
      tx.set(rentalRef, {
        'userId': userId,
        'cameraId': camera.id,
        'cameraName': camera.name,
        'dailyRate': camera.dailyRate,
        'totalPrice': totalPrice,
        'durationHours': durationOption.duration.inHours,
        'rentedAt': Timestamp.fromDate(now),
        'dueAt': Timestamp.fromDate(dueAt),
        'returnedAt': null,
        'acknowledged': false,
      });
    });

    return CameraRental(
      id: rentalRef.id,
      userId: userId,
      cameraId: camera.id,
      cameraName: camera.name,
      dailyRate: camera.dailyRate,
      totalPrice: totalPrice,
      duration: durationOption.duration,
      rentedAt: now,
      dueAt: dueAt,
    );
  }
}