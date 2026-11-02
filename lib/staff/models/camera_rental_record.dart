import 'package:cloud_firestore/cloud_firestore.dart';

/// Plain data class for a camera rental, parsed from a `cameraRentals`
/// Firestore document — same collection the customer app's
/// `CameraRentalRepository.createRental` writes to.
class CameraRentalRecord {
  final String id;
  final String userId;
  final String cameraId;
  final String cameraName;
  final DateTime rentedAt;
  final DateTime dueAt;
  final DateTime? returnedAt;

  /// Whether staff/admin has already seen/dismissed this in the notification
  /// tray. New rentals arrive with this `false`, which is what raises the
  /// bell badge — same "unattended until acted on" idea as a booking
  /// sitting in `pending_confirmation`.
  final bool acknowledged;

  /// What the camera costs per 24 hours (snapshotted by the customer app
  /// at rental time); 0 when the document doesn't carry it. Used to
  /// suggest an overdue fee.
  final int dailyRate;

  /// Fee charged for returning late, in pesos. 0 = none.
  final int overdueFee;

  /// What staff/admin noted about the camera's condition on return
  /// (scratches, missing accessories…). Empty = no issues recorded.
  final String damageNote;

  /// Extra charge for damage, in pesos. 0 = none.
  final int damageFee;

  /// Whether the overdue/damage charges have been collected.
  final bool feesSettled;

  // ---- Walk-in rental details (empty / 0 on older rentals) ----

  /// 'walk_in' when staff started the rental at the counter.
  final String source;
  final String customerName;
  final String customerPhone;

  /// Type of ID the customer left with the shop. Never the ID number.
  final String idType;

  /// Backup contact (co-maker) the customer named at the counter, for when
  /// the renter can't be reached. Empty on older rentals.
  final String coMakerName;
  final String coMakerPhone;
  final String coMakerRelationship;

  /// Rental fee charged up front, in pesos (excludes the deposit).
  final int totalPrice;

  /// Refundable deposit collected, and how much of it was handed back at
  /// check-in (deposit minus any overdue/damage fees).
  final int deposit;
  final int depositRefunded;

  /// Condition / items handed over when the camera left the counter.
  final String conditionNote;

  /// 'cash' | 'gcash', and the cash handed over (fee + deposit) if cash.
  final String paymentMethod;
  final int? amountReceived;
  final String staffEmail;

  const CameraRentalRecord({
    required this.id,
    required this.userId,
    required this.cameraId,
    required this.cameraName,
    required this.rentedAt,
    required this.dueAt,
    this.returnedAt,
    this.acknowledged = false,
    this.dailyRate = 0,
    this.overdueFee = 0,
    this.damageNote = '',
    this.damageFee = 0,
    this.feesSettled = false,
    this.source = '',
    this.customerName = '',
    this.customerPhone = '',
    this.idType = '',
    this.coMakerName = '',
    this.coMakerPhone = '',
    this.coMakerRelationship = '',
    this.totalPrice = 0,
    this.deposit = 0,
    this.depositRefunded = 0,
    this.conditionNote = '',
    this.paymentMethod = '',
    this.amountReceived,
    this.staffEmail = '',
  });

  bool get isWalkIn => source == 'walk_in';

  bool get hasCoMaker => coMakerName.trim().isNotEmpty || coMakerPhone.trim().isNotEmpty;

  /// "Name (Relationship) · number" for the backup contact; empty if none.
  String get coMakerLabel {
    final name = coMakerName.trim();
    final rel = coMakerRelationship.trim();
    final phone = coMakerPhone.trim();
    final who = rel.isNotEmpty && name.isNotEmpty ? '$name ($rel)' : name;
    if (who.isEmpty) return phone;
    return phone.isNotEmpty ? '$who · $phone' : who;
  }

  /// Who has the camera: the name + number staff recorded for a walk-in,
  /// otherwise the account id (customer-app rentals).
  String get renterLabel {
    if (customerName.trim().isNotEmpty) {
      return customerPhone.trim().isNotEmpty ? '${customerName.trim()} · ${customerPhone.trim()}' : customerName.trim();
    }
    return 'Renter: $userId';
  }

  /// One line of counter details for the rental card.
  String get walkInDetails {
    final parts = <String>[];
    if (idType.isNotEmpty) parts.add('ID held: $idType');
    if (hasCoMaker) parts.add('Co-maker: $coMakerLabel');
    if (deposit > 0) {
      parts.add(isReturned ? 'Deposit ₱$deposit (₱$depositRefunded refunded)' : 'Deposit ₱$deposit held');
    }
    if (conditionNote.trim().isNotEmpty) parts.add('Out: ${conditionNote.trim()}');
    return parts.join('  ·  ');
  }

  int get totalFees => overdueFee + damageFee;
  bool get hasCharges => totalFees > 0 || damageNote.trim().isNotEmpty;

  /// Whole hours past due (rounded up) — 0 when not late. Uses the return
  /// time once returned, otherwise "now".
  int get overdueHours {
    final end = returnedAt ?? DateTime.now();
    if (!end.isAfter(dueAt)) return 0;
    return (end.difference(dueAt).inMinutes / 60).ceil();
  }

  /// Suggested late fee: the camera's hourly rate (daily rate ÷ 24) times
  /// the hours late, rounded up. 0 when the rate isn't known.
  int get suggestedOverdueFee => (dailyRate * overdueHours / 24).ceil();

  bool get isReturned => returnedAt != null;
  bool get isOverdue => !isReturned && DateTime.now().isAfter(dueAt);

  String get status {
    if (isReturned) return 'returned';
    if (isOverdue) return 'overdue';
    return 'active';
  }

  factory CameraRentalRecord.fromFirestore(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final rentedAt = (d['rentedAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    return CameraRentalRecord(
      id: doc.id,
      userId: (d['userId'] ?? '') as String,
      cameraId: (d['cameraId'] ?? '') as String,
      cameraName: (d['cameraName'] ?? '') as String,
      rentedAt: rentedAt,
      dueAt: (d['dueAt'] as Timestamp?)?.toDate() ?? rentedAt,
      returnedAt: (d['returnedAt'] as Timestamp?)?.toDate(),
      acknowledged: d['acknowledged'] == true,
      dailyRate: (d['dailyRate'] as num?)?.toInt() ?? 0,
      overdueFee: (d['overdueFee'] as num?)?.toInt() ?? 0,
      damageNote: (d['damageNote'] ?? '') as String,
      damageFee: (d['damageFee'] as num?)?.toInt() ?? 0,
      feesSettled: d['feesSettled'] == true,
      source: (d['source'] ?? '') as String,
      customerName: (d['customerName'] ?? '') as String,
      customerPhone: (d['customerPhone'] ?? '') as String,
      idType: (d['idType'] ?? '') as String,
      coMakerName: (d['coMakerName'] ?? '') as String,
      coMakerPhone: (d['coMakerPhone'] ?? '') as String,
      coMakerRelationship: (d['coMakerRelationship'] ?? '') as String,
      totalPrice: (d['totalPrice'] as num?)?.toInt() ?? 0,
      deposit: (d['deposit'] as num?)?.toInt() ?? 0,
      depositRefunded: (d['depositRefunded'] as num?)?.toInt() ?? 0,
      conditionNote: (d['conditionNote'] ?? '') as String,
      paymentMethod: (d['paymentMethod'] ?? '') as String,
      amountReceived: (d['amountReceived'] as num?)?.toInt(),
      staffEmail: (d['staffEmail'] ?? '') as String,
    );
  }

  CameraRentalRecord copyWith({DateTime? returnedAt, bool? acknowledged}) {
    return CameraRentalRecord(
      id: id,
      userId: userId,
      cameraId: cameraId,
      cameraName: cameraName,
      rentedAt: rentedAt,
      dueAt: dueAt,
      returnedAt: returnedAt ?? this.returnedAt,
      acknowledged: acknowledged ?? this.acknowledged,
      dailyRate: dailyRate,
      overdueFee: overdueFee,
      damageNote: damageNote,
      damageFee: damageFee,
      feesSettled: feesSettled,
      source: source,
      customerName: customerName,
      customerPhone: customerPhone,
      idType: idType,
      coMakerName: coMakerName,
      coMakerPhone: coMakerPhone,
      coMakerRelationship: coMakerRelationship,
      totalPrice: totalPrice,
      deposit: deposit,
      depositRefunded: depositRefunded,
      conditionNote: conditionNote,
      paymentMethod: paymentMethod,
      amountReceived: amountReceived,
      staffEmail: staffEmail,
    );
  }
}