import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/camera_rental_record.dart';
import '../models/pos_transaction_record.dart';
import 'activity_log_repository.dart';

/// Staff-side, Firestore-backed access to `cameraRentals`. Rentals are
/// started at the counter with [createWalkInRental]; this repository also
/// reads them and marks them returned/acknowledged/deleted. Same collection
/// and document shape the Admin app's copy of this repository reads too.
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
  /// commits. Also records any overdue / damage charges entered at
  /// check-in. Logs the check-in for the Activity Log.
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

  /// Starts a walk-in rental: locks the camera, records the rental, and
  /// rings up the rental fee as a POS sale — in ONE transaction, so a
  /// camera can never be handed out twice and a rental can never exist
  /// without its sale (or the other way round).
  ///
  /// [userId] is the customer's app account id when staff linked one,
  /// otherwise 'walk-in'. The deposit is refundable, so it is NOT counted
  /// as sales revenue — only [rentalFee] goes into `posTransactions`.
  /// [amountReceived] is the total cash handed over (fee + deposit).
  static Future<CameraRentalRecord> createWalkInRental({
    required String cameraId,
    required String cameraName,
    required int dailyRate,
    required Duration duration,
    required String durationLabel,
    required int rentalFee,
    required String userId,
    required String customerName,
    required String customerPhone,
    required String idType,
    required String coMakerName,
    required String coMakerPhone,
    String coMakerRelationship = '',
    int deposit = 0,
    String conditionNote = '',
    required String paymentMethod,
    int? amountReceived,
    required String staffId,
    required String staffEmail,
  }) async {
    if (cameraId.isEmpty) throw Exception('Pick a camera first.');
    if (customerName.trim().isEmpty) throw Exception("The customer's name is required.");
    if (coMakerName.trim().isEmpty || coMakerPhone.trim().isEmpty) {
      throw Exception("The co-maker's name and contact number are required.");
    }

    final now = DateTime.now();
    final dueAt = now.add(duration);
    final rentalRef = _col.doc();
    final posRef = FirebaseFirestore.instance.collection('posTransactions').doc();
    final lockRef = _lockRef(cameraId);
    final safeDeposit = deposit < 0 ? 0 : deposit;

    final line = PosLineItem(name: '$cameraName — $durationLabel', category: 'Camera Rental', unitPrice: rentalFee, quantity: 1);
    // The POS record only knows about the fee, so take the deposit out of
    // the cash handed over — its "change" then matches what the customer got.
    final posReceived = (paymentMethod == 'cash' && amountReceived != null) ? amountReceived - safeDeposit : null;

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final lockSnap = await tx.get(lockRef);
      if (lockSnap.exists) {
        final existingDue = (lockSnap.data()?['dueAt'] as Timestamp?)?.toDate();
        throw Exception(
          '$cameraName is already rented${existingDue != null ? ' until ${DateFormat('MMM d, h:mm a').format(existingDue)}' : ''}.',
        );
      }
      tx.set(lockRef, {'rentalId': rentalRef.id, 'dueAt': Timestamp.fromDate(dueAt)});
      tx.set(rentalRef, {
        'userId': userId,
        'cameraId': cameraId,
        'cameraName': cameraName,
        'dailyRate': dailyRate,
        'totalPrice': rentalFee,
        'durationHours': duration.inHours,
        'rentedAt': Timestamp.fromDate(now),
        'dueAt': Timestamp.fromDate(dueAt),
        'returnedAt': null,
        // Staff made this one themselves, so it shouldn't raise the bell.
        'acknowledged': true,
        'source': 'walk_in',
        'customerName': customerName.trim(),
        'customerPhone': customerPhone.trim(),
        'idType': idType,
        'coMakerName': coMakerName.trim(),
        'coMakerPhone': coMakerPhone.trim(),
        'coMakerRelationship': coMakerRelationship.trim(),
        'deposit': safeDeposit,
        'conditionNote': conditionNote.trim(),
        'paymentMethod': paymentMethod,
        'amountReceived': amountReceived,
        'staffId': staffId,
        'staffEmail': staffEmail,
        'posTransactionId': posRef.id,
      });
      tx.set(posRef, {
        'items': [line.toMap()],
        'total': rentalFee,
        'paymentMethod': paymentMethod,
        'amountReceived': posReceived,
        'referenceNote': 'Camera rental — ${customerName.trim()}',
        'staffId': staffId,
        'staffEmail': staffEmail,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    await ActivityLogRepository.log(
      action: 'Started walk-in rental',
      targetSummary: '$cameraName — ${customerName.trim()}',
    );

    return CameraRentalRecord(
      id: rentalRef.id,
      userId: userId,
      cameraId: cameraId,
      cameraName: cameraName,
      rentedAt: now,
      dueAt: dueAt,
      acknowledged: true,
      dailyRate: dailyRate,
      source: 'walk_in',
      customerName: customerName.trim(),
      customerPhone: customerPhone.trim(),
      idType: idType,
      coMakerName: coMakerName.trim(),
      coMakerPhone: coMakerPhone.trim(),
      coMakerRelationship: coMakerRelationship.trim(),
      totalPrice: rentalFee,
      deposit: safeDeposit,
      conditionNote: conditionNote.trim(),
      paymentMethod: paymentMethod,
      amountReceived: amountReceived,
      staffEmail: staffEmail,
    );
  }

  static Map<String, dynamic> _chargeFields({required int overdueFee, required int damageFee, required String damageNote}) => {
        'overdueFee': overdueFee < 0 ? 0 : overdueFee,
        'damageFee': damageFee < 0 ? 0 : damageFee,
        'damageNote': damageNote.trim(),
        // New charges start unpaid; clearing them all leaves nothing to settle.
        'feesSettled': false,
      };

  /// Edits the fees / damage note on a rental after the fact (e.g. a
  /// scratch is spotted the next day, or the late fee is waived).
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