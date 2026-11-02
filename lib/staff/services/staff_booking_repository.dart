import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/booking_record.dart';
import 'activity_log_repository.dart';

/// Thrown when approving a booking would double-book a date that already
/// has an approved booking on it.
class DoubleBookingException implements Exception {
  final String message;
  const DoubleBookingException(this.message);
  @override
  String toString() => message;
}

/// Firebase-backed booking repository — reads/writes the same `bookings`
/// collection the customer app writes to when someone books a session.
///
/// Requires `Firebase.initializeApp()` to have already run (see
/// `main_staff.dart`) and Firestore security rules that let a signed-in
/// staff account read every booking and update its `status` /
/// `rejectionReason` fields (see `firestore.rules`).
class BookingRepository {
  BookingRepository._();

  /// Reason written onto bookings the 15-minute hold sweep cancels.
  static const String holdExpiredReason = 'No payment receipt sent within the 15-minute hold.';

  /// Reason written onto same-day bookings auto-rejected because another
  /// booking for that date was approved first.
  static const String dateTakenReason = 'Slot unavailable — another booking for this date was approved.';

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('bookings');

  /// Mirrors `dateHolds` in the User app's `BookingRepository` — a single
  /// document per date that the customer-facing calendar reads to decide
  /// what's greyed out. Approving/rejecting a booking here has to keep
  /// this in sync, or the calendar would drift from what staff/admin
  /// actually decided (a rejected date staying locked forever, or an
  /// approved one not showing as taken).
  static CollectionReference<Map<String, dynamic>> get _locksCol =>
      FirebaseFirestore.instance.collection('dateHolds');

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static DateTime? _dateFromKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  static CollectionReference<Map<String, dynamic>> get _usersCol =>
      FirebaseFirestore.instance.collection('users');

  static CollectionReference<Map<String, dynamic>> get _posCol =>
      FirebaseFirestore.instance.collection('posTransactions');

  /// Whether a `dateHolds/{key}` lock's `status` should be treated as
  /// occupying that date. Mirrors the same check `updateStatus`'s
  /// `_syncLock` implies, and the User app's identically-named private
  /// helper — kept in sync by hand since these are separate Flutter
  /// modules.
  static bool _lockBlocks(Map<String, dynamic> data) {
    final status = data['status'] as String? ?? '';
    if (status == 'cancelled') return false;
    if (status == 'awaiting_receipt') {
      final expires = data['holdExpiresAt'];
      if (expires is! Timestamp) return true;
      return expires.toDate().isAfter(DateTime.now());
    }
    return true; // pending_confirmation | confirmed | completed
  }

  /// Live stream of every date that's off-limits for a new booking —
  /// same `dateHolds` collection the customer app's calendar reads, so a
  /// walk-in staff creates here can never clash with an online booking.
  static Stream<Set<DateTime>> watchLockedDates() {
    return _locksCol.snapshots().map((snap) {
      final dates = <DateTime>{};
      for (final doc in snap.docs) {
        if (!_lockBlocks(doc.data())) continue;
        final d = _dateFromKey(doc.id);
        if (d != null) dates.add(d);
      }
      return dates;
    });
  }

  /// Looks up a customer by email in the shared `users` collection (both
  /// registered accounts and past guest checkouts live there — see the
  /// User app's `AuthService`). Returns their profile data plus `uid`, or
  /// null if nobody's checked out with that email before.
  static Future<Map<String, dynamic>?> findCustomerByEmail(String email) async {
    final snap = await _usersCol.where('email', isEqualTo: email.trim()).limit(1).get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return {...doc.data(), 'uid': doc.id};
  }

  /// Books a slot for a customer standing in front of staff right now
  /// **and** rings up the payment as a POS sale in the same transaction
  /// — one action instead of a booking plus a separate manual POS entry,
  /// so a walk-in's payment is never missing from the day's POS total.
  ///
  /// Goes straight to `confirmed` (no hold/receipt step — staff have
  /// already verified the customer and payment in person) and
  /// permanently claims the date's `dateHolds` lock, so it can never
  /// double-book against an online booking landing in the same instant.
  /// Throws if [date] is no longer free.
  ///
  /// Pass [existingUserId] when [findCustomerByEmail] found a match, so
  /// the booking is tied to that real account and shows up in their "My
  /// Bookings" immediately. Otherwise a lightweight guest profile doc is
  /// created in `users` (same shape the User app's guest checkout
  /// writes) so the booking still has somewhere to attach.
  static Future<String> createWalkInBookingWithPayment({
    String? existingUserId,
    required String customerName,
    required String customerEmail,
    required String customerContact,
    required String packageId,
    required String packageName,
    required String duration,
    required int price,
    required DateTime date,
    required String time,
    int? guests,
    String occasion = '',
    required String paymentMethod, // 'cash' | 'gcash'
    int? amountReceived,
    required String staffId,
    required String staffEmail,
  }) async {
    final db = FirebaseFirestore.instance;
    final bookingRef = _col.doc();
    final lockRef = _locksCol.doc(_dateKey(date));
    final posRef = _posCol.doc();

    String userId;
    if (existingUserId != null && existingUserId.isNotEmpty) {
      userId = existingUserId;
    } else {
      // No matching account — this booking just carries the customer's
      // name/email/contact directly (already written below), so there's
      // no need for a separate `users` profile doc. Firestore rules only
      // let a signed-in person write their own `users/{uid}` doc, so
      // staff creating one on a guest's behalf would fail anyway; `.id`
      // here is just a fresh unique string, no write involved.
      userId = _usersCol.doc().id;
    }

    await db.runTransaction((tx) async {
      final lockSnap = await tx.get(lockRef);
      if (lockSnap.exists && _lockBlocks(lockSnap.data()!)) {
        throw Exception("That date was just taken by another booking — please pick a different date.");
      }

      tx.set(bookingRef, {
        'userId': userId,
        'customerName': customerName,
        'customerEmail': customerEmail,
        'customerContact': customerContact,
        'packageId': packageId,
        'packageName': packageName,
        'duration': duration,
        'price': price,
        'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
        'time': time,
        'guests': guests,
        'occasion': occasion,
        'receiptFileName': '',
        'receiptUrl': '',
        'status': 'confirmed',
        'bookedByStaff': true,
        'staffId': staffId,
        'notifyCustomer': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      tx.set(lockRef, {'bookingId': bookingRef.id, 'status': 'confirmed'});

      // The POS side of the same transaction — one line item for the
      // package, tagged with the booking it paid for so Admin's sales
      // report and the bookings list can be cross-referenced.
      tx.set(posRef, {
        'items': [
          {'name': packageName, 'category': 'Booth Package', 'unitPrice': price, 'quantity': 1},
        ],
        'total': price,
        'paymentMethod': paymentMethod,
        'amountReceived': amountReceived,
        'referenceNote': 'Walk-in booking · $customerName (${bookingRef.id.length <= 6 ? bookingRef.id.toUpperCase() : bookingRef.id.substring(bookingRef.id.length - 6).toUpperCase()})',
        'staffId': staffId,
        'staffEmail': staffEmail,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    await ActivityLogRepository.log(
      action: 'Created walk-in booking',
      targetSummary: '$packageName — ${customerName.trim().isNotEmpty ? customerName.trim() : bookingRef.id}',
    );
    return bookingRef.id;
  }

  /// If `dateHolds/{dateKey}` still points at [bookingId], queues either a
  /// delete (freeing the date) or a status update on it into [batch].
  /// The "still points at" check matters: it guards against ever touching
  /// a *different*, newer lock that's since legitimately claimed the same
  /// date — shouldn't happen given how the lock is used, but cheap to be
  /// sure rather than silently unlocking someone else's date.
  static Future<void> _syncLock(WriteBatch batch, DateTime date, String bookingId, {required bool release}) async {
    final lockRef = _locksCol.doc(_dateKey(date));
    final lockSnap = await lockRef.get();
    if (!lockSnap.exists || lockSnap.data()?['bookingId'] != bookingId) return;
    if (release) {
      batch.delete(lockRef);
    } else {
      batch.update(lockRef, {'status': 'confirmed', 'holdExpiresAt': FieldValue.delete()});
    }
  }

  /// Every booking, most recent first. Any filtering/searching/sorting
  /// the staff dashboard needs (status, date, customer) is applied on
  /// this list client-side in the UI, since the collection is small
  /// enough that a single live listener is simpler than juggling several
  /// composite Firestore indexes.
  static Stream<List<BookingRecord>> watchAllBookings() {
    return _col.orderBy('createdAt', descending: true).snapshots().map(
          (snap) => snap.docs.map(BookingRecord.fromFirestore).toList(),
        );
  }

  static Query<Map<String, dynamic>> _sameDayQuery(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    // Range query on a single field only — no composite index needed.
    return _col
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end));
  }

  /// Whether [date] already has an approved (or already-run) booking that
  /// isn't [ignoreBookingId]. This is the rule that stops a second booking
  /// being accepted for a day staff have already committed to.
  static Future<BookingRecord?> approvedBookingOn(DateTime date, {String? ignoreBookingId}) async {
    final snap = await _sameDayQuery(date).get();
    for (final doc in snap.docs) {
      if (doc.id == ignoreBookingId) continue;
      final status = doc.data()['status'] as String? ?? '';
      if (status == 'confirmed' || status == 'completed') {
        return BookingRecord.fromFirestore(doc);
      }
    }
    return null;
  }

  /// Updates a booking's status. When rejecting (`status == 'cancelled'`),
  /// pass the staff-chosen [rejectionReason] — it's written onto the
  /// document so a Cloud Function trigger (`onUpdate` of `bookings/{id}`)
  /// can email/SMS the customer. Sending that email itself needs to happen
  /// server-side (Cloud Functions + SendGrid/Mailgun, etc.) since the
  /// Flutter client shouldn't hold those credentials — this write is the
  /// event such a function would listen for.
  ///
  /// Pass [staffId]/[staffName] (from [AuthService.currentUid] and
  /// [AuthService.currentStaffDisplayName]) so the booking records which
  /// staff member actually accepted or rejected it — that's what lets the
  /// Admin app show "Accepted by <staff name>" instead of just "Confirmed".
  /// Left null, no such stamp is written (e.g. when Admin approves a
  /// booking directly through its own `BookingRepository`, which doesn't
  /// pass these at all — a booking with no staff stamp on it means an
  /// admin, not a staff member, actioned it).
  ///
  /// Approving (`status == 'confirmed'`) runs the double-booking check
  /// first and throws [DoubleBookingException] if that date is already
  /// taken; on success it auto-rejects every other still-open booking for
  /// the same date, so one approval settles the day.
  static Future<void> updateStatus(
    String bookingId,
    String status, {
    String? rejectionReason,
    String? staffId,
    String? staffName,
  }) async {
    Map<String, dynamic>? bookingData;
    if (status == 'confirmed' || status == 'cancelled') {
      final snap = await _col.doc(bookingId).get();
      bookingData = snap.data();
      if (bookingData == null) throw const DoubleBookingException("This booking no longer exists.");
    }

    if (status == 'confirmed') {
      final ts = bookingData!['date'];
      final date = ts is Timestamp ? ts.toDate() : DateTime.now();

      final clash = await approvedBookingOn(date, ignoreBookingId: bookingId);
      if (clash != null) {
        throw DoubleBookingException(
          "That date is already booked — \"${clash.packageName}\" (ref ${clash.bookingRef}) was approved for it. "
          "Reject one of them first if you need to swap.",
        );
      }
    }

    final updates = <String, dynamic>{
      'status': status,
      'statusUpdatedAt': FieldValue.serverTimestamp(),
    };
    if (status == 'cancelled') {
      updates['rejectionReason'] = rejectionReason ?? '';
    } else {
      updates['rejectionReason'] = FieldValue.delete();
    }
    if (status == 'confirmed' || status == 'cancelled') {
      // Read by the customer's own notification bell (see
      // BookingRepository.markNotificationSeen on the User side) — flips
      // back to false once they've actually seen it there.
      updates['notifyCustomer'] = true;
    }
    if (status != 'awaiting_receipt') {
      updates['holdExpiresAt'] = FieldValue.delete();
    }
    if (status == 'confirmed' && staffId != null) {
      updates['acceptedByStaffId'] = staffId;
      updates['acceptedByStaffName'] = staffName ?? '';
      updates['acceptedAt'] = FieldValue.serverTimestamp();
    }
    if (status == 'cancelled' && staffId != null) {
      updates['rejectedByStaffId'] = staffId;
      updates['rejectedByStaffName'] = staffName ?? '';
      updates['rejectedAt'] = FieldValue.serverTimestamp();
    }

    final batch = FirebaseFirestore.instance.batch();
    batch.update(_col.doc(bookingId), updates);

    // Keep `dateHolds` in sync: an approval should permanently lock the
    // date, a rejection should free it back up for other customers.
    if (status == 'confirmed' || status == 'cancelled') {
      final ts = bookingData!['date'];
      if (ts is Timestamp) {
        await _syncLock(batch, ts.toDate(), bookingId, release: status == 'cancelled');
      }
    }

    await batch.commit();

    if (status == 'confirmed') {
      final ts = bookingData!['date'];
      if (ts is Timestamp) {
        await _rejectOtherBookingsOn(ts.toDate(), keepBookingId: bookingId);
      }
    }

    final label = ActivityLogRepository.bookingActionLabel(status, rejectionReason);
    if (label != null) {
      final data = bookingData ?? (await _col.doc(bookingId).get()).data();
      await ActivityLogRepository.log(action: label, targetSummary: ActivityLogRepository.bookingSummary(bookingId, data));
    }
  }

  /// Auto-rejects every other still-open booking on [date] once one has
  /// been approved, so the same day can never end up double-booked.
  ///
  /// Under the current `dateHolds`-based reservation system this should
  /// rarely find anything — only one booking can ever hold a date's lock
  /// at a time — but stays in place as a safety net for bookings created
  /// before that system existed, or any doc touched directly in the
  /// Firestore Console outside the app's normal flow.
  static Future<void> _rejectOtherBookingsOn(DateTime date, {required String keepBookingId}) async {
    final snap = await _sameDayQuery(date).get();
    final batch = FirebaseFirestore.instance.batch();
    var found = false;

    for (final doc in snap.docs) {
      if (doc.id == keepBookingId) continue;
      final status = doc.data()['status'] as String? ?? '';
      if (status != 'pending_confirmation' && status != 'awaiting_receipt') continue;

      found = true;
      batch.update(doc.reference, {
        'status': 'cancelled',
        'rejectionReason': dateTakenReason,
        'autoRejected': true,
        'notifyCustomer': true,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
        'holdExpiresAt': FieldValue.delete(),
      });
      await _syncLock(batch, date, doc.id, release: true);
    }

    if (found) await batch.commit();
  }

  /// Auto-rejects bookings whose 15-minute hold ran out before the
  /// customer sent a receipt. The staff and admin dashboards call this on
  /// a timer so expired holds turn into rejected bookings in their list
  /// without anyone having to do it by hand.
  ///
  /// In production this same sweep is better run as a scheduled Cloud
  /// Function, so holds still expire when no dashboard is open; running it
  /// here keeps the demo self-contained and is safe to run repeatedly,
  /// since it only ever touches `awaiting_receipt` docs that are already
  /// past their expiry.
  static Future<int> expireStaleHolds() async {
    final now = Timestamp.fromDate(DateTime.now());
    // Range filter on one field only, with the status checked below in
    // Dart — combining an equality and a range across two fields would
    // need a composite index deployed before this could run at all.
    final snap = await _col.where('holdExpiresAt', isLessThanOrEqualTo: now).get();

    final expired = snap.docs
        .where((d) => (d.data()['status'] as String? ?? '') == 'awaiting_receipt')
        .toList();
    if (expired.isEmpty) return 0;

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in expired) {
      batch.update(doc.reference, {
        'status': 'cancelled',
        'rejectionReason': holdExpiredReason,
        'autoRejected': true,
        'notifyCustomer': true,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
        'holdExpiresAt': FieldValue.delete(),
      });
      final ts = doc.data()['date'];
      if (ts is Timestamp) {
        await _syncLock(batch, ts.toDate(), doc.id, release: true);
      }
    }
    await batch.commit();
    return expired.length;
  }
}