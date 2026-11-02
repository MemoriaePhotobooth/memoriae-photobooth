import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/camera_rental_record.dart';
import 'activity_log_repository.dart';

/// Admin-side, Firestore-backed access to `cameraRentals` — the customer
/// app's `CameraRentalRepository.createRental` is the only place these are
/// created; this repository just reads them and marks them
/// returned/acknowledged/deleted. Same collection and document shape the
/// Staff app's copy of this repository reads too.
class CameraRentalRepository {
  CameraRentalRepository._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('cameraRentals');

  static DocumentReference<Map<String, dynamic>> _lockRef(String cameraId) =>
      FirebaseFirestore.instance.collection('cameraLocks').doc(cameraId);

  /// Every camera rental, most recent first.
  static Stream<List<CameraRentalRecord>> watchAllRentals() {
    return _col.orderBy('rentedAt', descending: true).snapshots().map(
          (snap) => snap.docs.map(CameraRentalRecord.fromFirestore).toList(),
        );
  }

  /// Marks a rental returned and frees up its `cameraLocks` entry in the
  /// same batch, so the camera becomes rentable again the moment this
  /// commits. Logs the check-in for the Activity Log.
  static Future<void> markReturned(
    String rentalId, {
    int overdueFee = 0,
    int damageFee = 0,
    String damageNote = '',
    int? depositRefunded,
  }) async {
    final snap = await _col.doc(rentalId).get();
    final d = snap.data();
    final cameraId = d?['cameraId'] as String?;
    final cameraName = (d?['cameraName'] ?? 'Camera') as String;
    // Quick check-ins (no dialog) must not lose the deposit: unless a refund
    // amount is given, hand back the deposit minus any fees.
    final deposit = (d?['deposit'] as num?)?.toInt() ?? 0;
    final refund = depositRefunded ?? (deposit - overdueFee - damageFee).clamp(0, deposit).toInt();

    final batch = FirebaseFirestore.instance.batch();
    batch.update(_col.doc(rentalId), {
      'returnedAt': FieldValue.serverTimestamp(),
      if (deposit > 0) 'depositRefunded': refund,
      ..._chargeFields(overdueFee: overdueFee, damageFee: damageFee, damageNote: damageNote),
    });
    if (cameraId != null && cameraId.isNotEmpty) {
      batch.delete(_lockRef(cameraId));
    }
    await batch.commit();
    final fees = overdueFee + damageFee;
    await ActivityLogRepository.log(
      action: 'Checked in rental',
      targetSummary: fees > 0 ? '$cameraName (₱$fees in fees)' : cameraName,
    );
  }

  static Map<String, dynamic> _chargeFields({required int overdueFee, required int damageFee, required String damageNote}) => {
        'overdueFee': overdueFee < 0 ? 0 : overdueFee,
        'damageFee': damageFee < 0 ? 0 : damageFee,
        'damageNote': damageNote.trim(),
        // New charges start unpaid; clearing them all leaves nothing to settle.
        'feesSettled': false,
      };

  /// Edits the fees / damage note on a rental after the fact (e.g. the
  /// admin spots a scratch the next day, or waives the late fee).
  static Future<void> updateCharges(
    String rentalId, {
    required int overdueFee,
    required int damageFee,
    required String damageNote,
  }) async {
    await _col.doc(rentalId).update(_chargeFields(overdueFee: overdueFee, damageFee: damageFee, damageNote: damageNote));
    await ActivityLogRepository.log(action: 'Updated rental fees / damage note', targetSummary: rentalId);
  }

  /// Marks the overdue/damage charges as collected (or not yet).
  static Future<void> setFeesSettled(String rentalId, bool settled) =>
      _col.doc(rentalId).update({'feesSettled': settled});

  /// Clears the notification badge for a rental once the admin has opened
  /// it — same idea as tapping into a booking from the notification tray.
  static Future<void> acknowledge(String rentalId) => _col.doc(rentalId).update({'acknowledged': true});

  /// Removes a rental record (e.g. a mistaken or duplicate entry). Also
  /// frees the camera lock if the rental was still active, so a deleted
  /// active rental doesn't leave the camera stuck as permanently rented.
  static Future<void> deleteRental(String rentalId) async {
    final snap = await _col.doc(rentalId).get();
    final d = snap.data();
    final cameraId = d?['cameraId'] as String?;
    final returnedAt = d?['returnedAt'];

    final batch = FirebaseFirestore.instance.batch();
    batch.delete(_col.doc(rentalId));
    if (returnedAt == null && cameraId != null && cameraId.isNotEmpty) {
      batch.delete(_lockRef(cameraId));
    }
    await batch.commit();
  }
}