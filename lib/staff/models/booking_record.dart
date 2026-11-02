import 'package:cloud_firestore/cloud_firestore.dart';

/// Data class for a booking, backed by a `bookings/{id}` Firestore
/// document. `fromFirestore` does the parsing; `BookingRepository` does
/// the reading/writing.
class BookingRecord {
  final String id;
  final String userId;
  final String customerName;
  final String packageId;
  final String packageName;
  final String duration;
  final int price;
  final List<String> addOnNames;
  final int addOnsPrice;
  final DateTime date;
  final String time;
  final int? guests;
  final String receiptFileName;
  final String receiptUrl;

  /// GCash reference number and amount the Customer app's on-device OCR read
  /// off the receipt screenshot. Best-effort: empty / null when the booking
  /// was made on web, scanning failed, or it predates the feature.
  final String receiptRefNo;
  final double? receiptOcrAmount;
  final String status; // pending_confirmation | confirmed | completed | cancelled
  final String? rejectionReason;
  final DateTime? createdAt;
  final String location;
  /// When this booking's 15-minute checkout hold lapses. Only set while
  /// [status] is `awaiting_receipt`; cleared once a receipt arrives.
  final DateTime? holdExpiresAt;
  /// True when the system cancelled this booking on its own — an expired
  /// hold, or another booking for the same date being approved first.
  final bool autoRejected;
  /// Which staff member accepted this booking, if a staff member (not an
  /// Admin) is the one who did — see `BookingRepository.updateStatus`'s
  /// `staffId`/`staffName` params. Null when Admin approved it directly,
  /// or when the booking hasn't been accepted at all.
  final String? acceptedByStaffId;
  final String? acceptedByStaffName;
  final DateTime? acceptedAt;
  /// Same idea as the accepted-by fields above, but for rejection.
  final String? rejectedByStaffId;
  final String? rejectedByStaffName;
  final DateTime? rejectedAt;

  /// How the customer chose to pay: `'full'` or `'downpayment'`. Null on
  /// bookings made before downpayments existed (treated as fully paid).
  final String? paymentOption;

  /// What the customer sent with their receipt. For a downpayment this is
  /// less than [totalPrice]; the rest is [balanceDue] until staff mark it
  /// collected ([balancePaid]).
  final int? amountPaid;
  final bool balancePaid;

  /// Refund trail for a rejected/cancelled booking that had money paid.
  /// `pending` = decided, still to be sent back by GCash; `refunded` = sent;
  /// `none` = decided nothing goes back. Null = no decision recorded.
  final String? refundStatus;
  final int refundAmount;

  /// Money the business keeps from a cancelled booking (forfeited
  /// downpayment, cancellation fee). Counted as revenue.
  final int retainedAmount;
  final String refundNote;
  final DateTime? refundedAt;
  final String? refundedByStaffName;
  /// Reschedule trail — set when a staff member moves this booking to a
  /// new date/time (see `BookingRepository.rescheduleBooking`). The
  /// customer's notification bell reads the same fields to show
  /// "was Sat, Oct 4 · 2:00 PM  →  now Sun, Oct 5 · 3:00 PM".
  final DateTime? previousDate;
  final String? previousTime;
  final DateTime? rescheduledAt;
  final String? rescheduledByStaffName;
  final String? rescheduleReason;
  final int rescheduleCount;

  const BookingRecord({
    required this.id,
    required this.userId,
    this.customerName = '',
    required this.packageId,
    required this.packageName,
    required this.duration,
    required this.price,
    this.addOnNames = const [],
    this.addOnsPrice = 0,
    required this.date,
    required this.time,
    required this.guests,
    required this.receiptFileName,
    required this.receiptUrl,
    this.receiptRefNo = '',
    this.receiptOcrAmount,
    required this.status,
    this.rejectionReason,
    required this.createdAt,
    this.location = '',
    this.holdExpiresAt,
    this.autoRejected = false,
    this.acceptedByStaffId,
    this.acceptedByStaffName,
    this.acceptedAt,
    this.rejectedByStaffId,
    this.rejectedByStaffName,
    this.rejectedAt,
    this.paymentOption,
    this.amountPaid,
    this.balancePaid = false,
    this.refundStatus,
    this.refundAmount = 0,
    this.retainedAmount = 0,
    this.refundNote = '',
    this.refundedAt,
    this.refundedByStaffName,
    this.previousDate,
    this.previousTime,
    this.rescheduledAt,
    this.rescheduledByStaffName,
    this.rescheduleReason,
    this.rescheduleCount = 0,
  });

  /// True once a staff member has moved this booking at least once.
  bool get wasRescheduled => rescheduledAt != null || rescheduleCount > 0;

  /// Package price plus any add-ons (e.g. camera rental).
  int get totalPrice => price + addOnsPrice;

  /// True when the customer reserved with a downpayment.
  bool get isDownpayment => paymentOption == 'downpayment';

  /// Money actually received so far. Equals [totalPrice] for full payments
  /// (and for older bookings with no payment fields).
  int get paidAmount {
    if (!isDownpayment || balancePaid) return totalPrice;
    final paid = amountPaid ?? totalPrice;
    return paid < 0 ? 0 : (paid > totalPrice ? totalPrice : paid);
  }

  /// What the customer still owes (0 once paid in full or settled).
  int get balanceDue => status == 'cancelled' ? 0 : totalPrice - paidAmount;

  bool get hasBalance => balanceDue > 0;

  /// A refund has been decided but not yet sent back to the customer.
  bool get refundPending => refundStatus == 'pending';

  /// True when this booking had a real payment that a reject/cancel has to
  /// settle — i.e. the receipt is in and it isn't already cancelled.
  bool get hasPaymentToSettle =>
      status != 'cancelled' && status != 'awaiting_receipt' && receiptUrl.isNotEmpty && paidAmount > 0;

  /// Still holding a slot while the customer finishes checkout — no
  /// receipt yet, hold not lapsed.
  bool get isAwaitingReceipt => status == 'awaiting_receipt';

  /// How long is left on the checkout hold, or null when there isn't one.
  Duration? get holdRemaining {
    if (holdExpiresAt == null) return null;
    final left = holdExpiresAt!.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// Short, human-friendly reference for search — last 6 chars of the
  /// Firestore doc id, upper-cased (e.g. "AB12CD").
  String get bookingRef => id.length <= 6 ? id.toUpperCase() : id.substring(id.length - 6).toUpperCase();

  static DateTime _asDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.now();
  }

  static DateTime? _asDateOrNull(dynamic v) => v == null ? null : _asDate(v);

  static int _asInt(dynamic v) => (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;

  /// Parses a `bookings/{id}` document from Firestore into a [BookingRecord].
  factory BookingRecord.fromFirestore(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return BookingRecord(
      id: doc.id,
      userId: (d['userId'] ?? '') as String,
      customerName: (d['customerName'] ?? '') as String,
      packageId: (d['packageId'] ?? '') as String,
      packageName: (d['packageName'] ?? '') as String,
      duration: (d['duration'] ?? '') as String,
      price: _asInt(d['price']),
      addOnNames: List<String>.from(d['addOnNames'] ?? const []),
      addOnsPrice: _asInt(d['addOnsPrice']),
      date: _asDate(d['date']),
      time: (d['time'] ?? '') as String,
      guests: d['guests'] == null ? null : _asInt(d['guests']),
      receiptFileName: (d['receiptFileName'] ?? '') as String,
      receiptUrl: (d['receiptUrl'] ?? '') as String,
      receiptRefNo: (d['receiptRefNo'] ?? '') as String,
      receiptOcrAmount: (d['receiptOcrAmount'] as num?)?.toDouble(),
      status: (d['status'] ?? 'pending_confirmation') as String,
      rejectionReason: d['rejectionReason'] as String?,
      createdAt: _asDateOrNull(d['createdAt']),
      location: (d['location'] ?? '') as String,
      holdExpiresAt: _asDateOrNull(d['holdExpiresAt']),
      autoRejected: d['autoRejected'] == true,
      acceptedByStaffId: d['acceptedByStaffId'] as String?,
      acceptedByStaffName: d['acceptedByStaffName'] as String?,
      acceptedAt: _asDateOrNull(d['acceptedAt']),
      rejectedByStaffId: d['rejectedByStaffId'] as String?,
      rejectedByStaffName: d['rejectedByStaffName'] as String?,
      rejectedAt: _asDateOrNull(d['rejectedAt']),
      paymentOption: d['paymentOption'] as String?,
      amountPaid: d['amountPaid'] == null ? null : _asInt(d['amountPaid']),
      balancePaid: d['balancePaid'] == true,
      refundStatus: d['refundStatus'] as String?,
      refundAmount: _asInt(d['refundAmount']),
      retainedAmount: _asInt(d['retainedAmount']),
      refundNote: (d['refundNote'] ?? '') as String,
      refundedAt: _asDateOrNull(d['refundedAt']),
      refundedByStaffName: d['refundedByStaffName'] as String?,
      previousDate: _asDateOrNull(d['previousDate']),
      previousTime: d['previousTime'] as String?,
      rescheduledAt: _asDateOrNull(d['rescheduledAt']),
      rescheduledByStaffName: d['rescheduledByStaffName'] as String?,
      rescheduleReason: d['rescheduleReason'] as String?,
      rescheduleCount: _asInt(d['rescheduleCount']),
    );
  }

  BookingRecord copyWith({
    String? status,
    String? rejectionReason,
    DateTime? date,
    String? time,
    DateTime? previousDate,
    String? previousTime,
    DateTime? rescheduledAt,
    String? rescheduledByStaffName,
    String? rescheduleReason,
    int? rescheduleCount,
  }) {
    return BookingRecord(
      id: id,
      userId: userId,
      customerName: customerName,
      packageId: packageId,
      packageName: packageName,
      duration: duration,
      price: price,
      addOnNames: addOnNames,
      addOnsPrice: addOnsPrice,
      date: date ?? this.date,
      time: time ?? this.time,
      guests: guests,
      receiptFileName: receiptFileName,
      receiptUrl: receiptUrl,
      receiptRefNo: receiptRefNo,
      receiptOcrAmount: receiptOcrAmount,
      status: status ?? this.status,
      rejectionReason: status == 'cancelled' ? (rejectionReason ?? this.rejectionReason) : null,
      createdAt: createdAt,
      location: location,
      holdExpiresAt: holdExpiresAt,
      autoRejected: autoRejected,
      acceptedByStaffId: acceptedByStaffId,
      acceptedByStaffName: acceptedByStaffName,
      acceptedAt: acceptedAt,
      rejectedByStaffId: rejectedByStaffId,
      rejectedByStaffName: rejectedByStaffName,
      rejectedAt: rejectedAt,
      paymentOption: paymentOption,
      amountPaid: amountPaid,
      balancePaid: balancePaid,
      refundStatus: refundStatus,
      refundAmount: refundAmount,
      retainedAmount: retainedAmount,
      refundNote: refundNote,
      refundedAt: refundedAt,
      refundedByStaffName: refundedByStaffName,
      previousDate: previousDate ?? this.previousDate,
      previousTime: previousTime ?? this.previousTime,
      rescheduledAt: rescheduledAt ?? this.rescheduledAt,
      rescheduledByStaffName: rescheduledByStaffName ?? this.rescheduledByStaffName,
      rescheduleReason: rescheduleReason ?? this.rescheduleReason,
      rescheduleCount: rescheduleCount ?? this.rescheduleCount,
    );
  }
}

/// What staff/admin decided to do with a customer's money when rejecting or
/// cancelling a paid booking. [refundAmount] goes back to the customer
/// (manually, by GCash); [retainedAmount] is kept by the business.
class RefundDecision {
  final int refundAmount;
  final int retainedAmount;
  final String note;

  const RefundDecision({required this.refundAmount, required this.retainedAmount, this.note = ''});

  /// `pending` when something must be sent back, else `none`.
  String get status => refundAmount > 0 ? 'pending' : 'none';
}
