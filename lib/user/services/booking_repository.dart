import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/booth_package.dart';
import 'booking_hours.dart';
import 'local_db.dart';
import 'offline_cache.dart';
import 'server_clock.dart';

/// Thrown when the date the customer picked is no longer available —
/// either someone else's booking on that day has already been approved by
/// staff, or another customer is mid-checkout holding the slot.
class DateUnavailableException implements Exception {
  final String message;
  const DateUnavailableException(this.message);
  @override
  String toString() => message;
}

/// Firebase-backed booking repository. Writes to the same `bookings`
/// Firestore collection the staff dashboard reads from. Receipts are
/// embedded directly in the booking document as a base64 `data:` URI
/// (see [_encodeReceipt]) rather than uploaded to Firebase Storage.
///
/// ## Slot holds and the 15-minute window
///
/// Opening the booking screen *reserves* the slot straight away as an
/// `awaiting_receipt` booking carrying a `holdExpiresAt` 15 minutes out.
/// That makes the on-screen countdown mean something: while it runs, no
/// one else can take the date. Sending the receipt promotes the booking to
/// `pending_confirmation` so staff can review it. If the countdown runs
/// out first, [expireHold] (client) or `expireStaleHolds` (staff/admin
/// dashboards) auto-rejects it, and the date frees up again.
///
/// ## Why there's a separate `dateHolds` collection
///
/// Reserving a date used to be "query `bookings` for that date, and if
/// nothing's there, create one" — two separate steps, not one atomic
/// operation. Two customers opening checkout for the same date within the
/// same few hundred milliseconds could both see the date as free and both
/// successfully create a hold, because neither one's write had landed yet
/// when the other one checked.
///
/// `dateHolds/{yyyy-MM-dd}` is a single document per date that acts as a
/// lock: [reserveSlot] and [updateReservation] check-and-claim it inside a
/// Firestore *transaction*, which Firestore guarantees is atomic even
/// under concurrent calls — if two requests race, one succeeds and the
/// other is automatically retried, and on retry correctly sees the date
/// as taken. `bookings` itself still holds the full record of every
/// booking ever made (including cancelled ones); `dateHolds` only ever
/// holds one entry per currently-blocked date and is the sole source of
/// truth for "is this date available", which is also why it's cheaper to
/// query than scanning `bookings` was.
class BookingRepository {
  BookingRepository._();

  /// How long a slot stays held while the customer finishes checkout.
  static const Duration holdDuration = Duration(minutes: 15);

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('bookings');

  static CollectionReference<Map<String, dynamic>> get _locksCol =>
      FirebaseFirestore.instance.collection('dateHolds');

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Sums add-on prices, treating a missing/null price as 0 rather than
  /// throwing — `BoothAddOn.price` may be nullable (e.g. a "quote on
  /// request" add-on with no fixed price yet).
  static int _addOnsTotal(List<BoothAddOn> addOns) =>
      addOns.fold(0, (sum, a) => sum + (a.price ?? 0));

  /// `yyyy-MM-dd` — used as the `dateHolds` document id, since Firestore
  /// document ids have to be strings, not `DateTime`s.
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

  /// Statuses that mean "this date is spoken for". A `cancelled` lock
  /// never blocks (shouldn't normally exist — locks are deleted, not
  /// cancelled — but handled defensively); an `awaiting_receipt` one
  /// blocks only while its hold is still live (see [_holdStillLive]).
  static bool _lockBlocks(Map<String, dynamic> data) {
    final status = data['status'] as String? ?? '';
    if (status == 'cancelled') return false;
    if (status == 'awaiting_receipt') return _holdStillLive(data);
    return true; // pending_confirmation | confirmed | completed
  }

  /// Whether an `awaiting_receipt` lock's 15-minute hold hasn't lapsed. A
  /// lapsed hold is treated as free even before the sweep cancels it, so
  /// the calendar never shows a stale lock, and so a brand new
  /// [reserveSlot] can claim the date immediately rather than waiting on
  /// `expireStaleHolds` to run first.
  static bool _holdStillLive(Map<String, dynamic> data) {
    final expires = data['holdExpiresAt'];
    if (expires is! Timestamp) return true; // no expiry recorded — treat as held
    return expires.toDate().isAfter(ServerClock.now());
  }

  /// Whether an active booking already exists for [date]. Pass
  /// [ignoreBookingId] to exclude the customer's own in-progress hold.
  /// A single document read against `dateHolds` — no query needed.
  static Future<bool> isDateBooked(DateTime date, {String? ignoreBookingId}) async {
    final snap = await _locksCol.doc(_dateKey(date)).get();
    final data = snap.data();
    if (data == null) return false;
    if (ignoreBookingId != null && data['bookingId'] == ignoreBookingId) return false;
    return _lockBlocks(data);
  }

  /// Live stream of every locked-out date, for the booking screen's
  /// calendar to grey out. Streams `dateHolds` rather than the full
  /// `bookings` collection — cheaper, and it's the authoritative source.
  static Stream<Set<DateTime>> watchBookedDates({String? ignoreBookingId}) {
    return _locksCol.snapshots().map((snap) {
      final dates = <DateTime>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        if (ignoreBookingId != null && data['bookingId'] == ignoreBookingId) continue;
        if (!_lockBlocks(data)) continue;
        final d = _dateFromKey(doc.id);
        if (d != null) dates.add(d);
      }
      return dates;
    });
  }

  /// Encodes the receipt screenshot as a `data:` URI and returns it,
  /// stored directly in the booking's Firestore document rather than
  /// Firebase Storage.
  ///
  /// Firebase Storage requires the project to be on the Blaze (pay-as-you-go)
  /// billing plan even for tiny amounts of usage — a hurdle this app
  /// intentionally avoids for a small deployment. The trade-off is
  /// Firestore's ~1MB per-document limit, which is why `ReceiptUpload`
  /// constrains the picked image's dimensions/quality before it ever
  /// reaches here — [bytes] should already be well under that by the time
  /// this runs. [_guessMimeType] picks the `data:` URI's MIME type from
  /// the file extension so `Image.memory` callers know how to decode it.
  static String _encodeReceipt(Uint8List bytes, String fileName) {
    final mimeType = _guessMimeType(fileName);
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  static String _guessMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg'; // .jpg/.jpeg and anything unrecognized
  }

  /// Holds [date] for this customer for [holdDuration] while they finish
  /// checkout, and returns the new booking's id. The booking starts as
  /// `awaiting_receipt` — staff see it as "awaiting payment", and it turns
  /// into a real request once [attachReceipt] runs.
  ///
  /// Runs as a single Firestore transaction: checking whether the date's
  /// `dateHolds` lock is free and claiming it happen atomically, so two
  /// customers racing for the same date can't both win.
  ///
  /// Throws [DateUnavailableException] if someone else already holds or
  /// owns the date.
  /// Returns the new booking's id together with the exact moment its hold
  /// expires, so callers (the receipt modal) can drive their countdown off
  /// that fixed timestamp instead of a local decrementing counter — one
  /// that keeps reading correctly even if the app was backgrounded and its
  /// timer got paused/throttled in between.
  static Future<({String id, DateTime holdExpiresAt})> reserveSlot({
    required String userId,
    String customerName = '',
    required BoothPackage package,
    List<BoothAddOn> addOns = const [],
    required DateTime date,
    required String time,
    int? guests,
    String location = '',
    double? locationLat,
    double? locationLng,
  }) async {
    // Use Firebase's clock, not the phone's, for the curfew and the hold.
    await ServerClock.sync();

    // Booking curfew: no new bookings from 12:00 AM to 6:00 AM.
    if (!BookingHours.isOpen()) throw const BookingClosedException();

    final bookingRef = _col.doc(); // client-generated id, no network call yet
    final lockRef = _locksCol.doc(_dateKey(date));
    final holdExpiresAt = Timestamp.fromDate(ServerClock.now().add(holdDuration));

    await _db.runTransaction((tx) async {
      final lockSnap = await tx.get(lockRef);
      if (lockSnap.exists && _lockBlocks(lockSnap.data()!)) {
        throw const DateUnavailableException(
          "That date was just taken by someone else — please pick another.",
        );
      }

      tx.set(bookingRef, {
        'userId': userId,
        'customerName': customerName,
        'packageId': package.id,
        'packageName': package.name,
        'duration': package.duration,
        'price': package.price,
        'addOnNames': addOns.map((a) => a.name).toList(),
        'addOns': addOns.map((a) => {'name': a.name, 'price': a.price}).toList(),
        'addOnsPrice': _addOnsTotal(addOns),
        'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
        'time': time,
        'guests': guests,
        'receiptFileName': '',
        'receiptUrl': '',
        'status': 'awaiting_receipt',
        'holdExpiresAt': holdExpiresAt,
        'createdAt': FieldValue.serverTimestamp(),
        'location': location,
        'locationLat': locationLat,
        'locationLng': locationLng,
      });

      tx.set(lockRef, {
        'bookingId': bookingRef.id,
        'status': 'awaiting_receipt',
        'holdExpiresAt': holdExpiresAt,
      });
    });

    return (id: bookingRef.id, holdExpiresAt: holdExpiresAt.toDate());
  }

  /// Keeps an existing hold in sync as the customer changes their mind
  /// (different date, package, add-ons, time, location) without dropping
  /// the hold or restarting the countdown.
  ///
  /// When the date actually changes, moving the `dateHolds` lock from the
  /// old date to the new one happens in the same transaction as checking
  /// the new date is free — same atomicity guarantee as [reserveSlot].
  ///
  /// Throws [DateUnavailableException] if they move the booking onto a date
  /// someone else already holds or owns.
  static Future<void> updateReservation(
    String bookingId, {
    required BoothPackage package,
    List<BoothAddOn> addOns = const [],
    required DateTime date,
    required String time,
    int? guests,
    String location = '',
    double? locationLat,
    double? locationLng,
  }) async {
    final bookingRef = _col.doc(bookingId);
    final newDateKey = _dateKey(date);

    await _db.runTransaction((tx) async {
      final bookingSnap = await tx.get(bookingRef);
      final existing = bookingSnap.data();
      if (existing == null) {
        throw const DateUnavailableException("This booking no longer exists — please start again.");
      }

      final oldDateTs = existing['date'];
      final oldDateKey = oldDateTs is Timestamp ? _dateKey(oldDateTs.toDate()) : null;
      final dateChanged = oldDateKey != newDateKey;

      DocumentSnapshot<Map<String, dynamic>>? newLockSnap;
      if (dateChanged) {
        newLockSnap = await tx.get(_locksCol.doc(newDateKey));
        if (newLockSnap.exists && _lockBlocks(newLockSnap.data()!)) {
          throw const DateUnavailableException(
            "That date was just taken by someone else — please pick another.",
          );
        }
      }

      // All reads are done — safe to write now.
      if (dateChanged) {
        if (oldDateKey != null) tx.delete(_locksCol.doc(oldDateKey));
        tx.set(_locksCol.doc(newDateKey), {
          'bookingId': bookingId,
          'status': 'awaiting_receipt',
          // Reuse whatever's left of the original countdown rather than
          // restarting it — changing your mind about the date shouldn't
          // buy extra hold time.
          'holdExpiresAt': existing['holdExpiresAt'],
        });
      }

      tx.update(bookingRef, {
        'packageId': package.id,
        'packageName': package.name,
        'duration': package.duration,
        'price': package.price,
        'addOnNames': addOns.map((a) => a.name).toList(),
        'addOns': addOns.map((a) => {'name': a.name, 'price': a.price}).toList(),
        'addOnsPrice': _addOnsTotal(addOns),
        'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
        'time': time,
        'guests': guests,
        'location': location,
        'locationLat': locationLat,
        'locationLng': locationLng,
      });
    });
  }

  /// Attaches the receipt and promotes the held booking to
  /// `pending_confirmation`, which is what puts it in front of staff for
  /// approval. Clears `holdExpiresAt` on both the booking and its
  /// `dateHolds` lock so the auto-reject sweep leaves it alone from here
  /// on, and updates the lock's status to match so it now blocks the date
  /// unconditionally (a real pending request, not just a timed hold).
  ///
  /// No date-availability re-check is needed here: because [reserveSlot]
  /// and [updateReservation] are atomic, nothing else could have taken
  /// this date while this booking held its lock. If the hold *did* expire
  /// in the meantime (sweep beat you to it, or you waited past your own
  /// countdown), the status check below already catches that.
  ///
  /// [paymentOption] is `'full'` or `'downpayment'`. For a downpayment,
  /// [amountPaid] is how much the customer sent now; the rest is stored as
  /// `balanceDue` for staff to collect later (and mark with
  /// `markBalancePaid` on the Staff/Admin side). Omitting [amountPaid]
  /// means the full total.
  static Future<void> attachReceipt({
    required String bookingId,
    required String userId,
    required Uint8List receiptBytes,
    required String receiptFileName,
    String paymentOption = 'full',
    int? amountPaid,
    String? receiptRefNo,
    double? receiptOcrAmount,
  }) async {
    final bookingRef = _col.doc(bookingId);
    final snap = await bookingRef.get();
    final data = snap.data();
    if (data == null) {
      throw const DateUnavailableException("This booking no longer exists — please start again.");
    }
    if ((data['status'] as String? ?? '') == 'cancelled') {
      throw const DateUnavailableException(
        "Your 15-minute hold ran out and the slot was released. Please book again.",
      );
    }

    final receiptDataUri = _encodeReceipt(receiptBytes, receiptFileName);
    // Base64 inflates size by ~33% — this is a second guard on top of
    // ReceiptUpload's pre-encoding size check, in case bytes ever arrive
    // here some other way. Firestore's hard limit is 1 MiB per document.
    if (receiptDataUri.length > 950 * 1024) {
      throw Exception("That receipt image is too large to attach — please pick a smaller screenshot.");
    }

    final total = ((data['price'] as num?)?.toInt() ?? 0) + ((data['addOnsPrice'] as num?)?.toInt() ?? 0);
    final isDown = paymentOption == 'downpayment';
    final paid = isDown ? (amountPaid ?? total).clamp(1, total > 0 ? total : 1).toInt() : total;
    final balance = total - paid;

    final batch = _db.batch();
    batch.update(bookingRef, {
      'receiptFileName': receiptFileName,
      'receiptUrl': receiptDataUri,
      'paymentOption': isDown && balance > 0 ? 'downpayment' : 'full',
      'amountPaid': paid,
      'balanceDue': balance,
      'balancePaid': balance <= 0,
      'status': 'pending_confirmation',
      'holdExpiresAt': FieldValue.delete(),
      'receiptSubmittedAt': FieldValue.serverTimestamp(),
      // Read off the screenshot by on-device OCR (best-effort, may be
      // absent or slightly off) — lets staff match it against GCash.
      if (receiptRefNo != null && receiptRefNo.isNotEmpty) 'receiptRefNo': receiptRefNo,
      if (receiptOcrAmount != null) 'receiptOcrAmount': receiptOcrAmount,
    });

    final dateTs = data['date'];
    if (dateTs is Timestamp) {
      batch.update(_locksCol.doc(_dateKey(dateTs.toDate())), {
        'status': 'pending_confirmation',
        'holdExpiresAt': FieldValue.delete(),
      });
    }
    await batch.commit();

    // Best-effort: give the booking its running invoice number. Never
    // allowed to fail the receipt upload itself.
    await _assignInvoiceNumber(bookingId);
  }

  /// The booking's total (package + add-ons) in pesos, or null if the
  /// booking can't be read. Lets the receipt modal show what to pay
  /// without its callers having to pass the amount in.
  static Future<int?> fetchTotal(String bookingId) async {
    try {
      final d = (await _col.doc(bookingId).get()).data();
      if (d == null) return null;
      return ((d['price'] as num?)?.toInt() ?? 0) + ((d['addOnsPrice'] as num?)?.toInt() ?? 0);
    } catch (_) {
      return null;
    }
  }

  /// Gives [bookingId] the next running invoice number (`MEM-000123`),
  /// using an atomic counter in `counters/invoice`. Does nothing if the
  /// booking already has one. If anything goes wrong (e.g. the `counters`
  /// rule isn't deployed yet) it's skipped silently, and the invoice just
  /// shows its date-based number instead.
  static Future<void> _assignInvoiceNumber(String bookingId) async {
    try {
      final counterRef = _db.collection('counters').doc('invoice');
      final bookingRef = _col.doc(bookingId);
      await _db.runTransaction((tx) async {
        final b = await tx.get(bookingRef);
        final existing = (b.data()?['invoiceNo'] as String? ?? '').trim();
        if (existing.isNotEmpty) return;
        final c = await tx.get(counterRef);
        final next = ((c.data()?['n'] as num?)?.toInt() ?? 0) + 1;
        tx.set(counterRef, {'n': next});
        tx.update(bookingRef, {'invoiceNo': 'MEM-${next.toString().padLeft(6, '0')}'});
      });
    } catch (_) {}
  }

  /// Releases this customer's own hold — used when their countdown hits
  /// zero, or when they back out of checkout. Only touches a booking still
  /// sitting in `awaiting_receipt`, so it can never cancel a request staff
  /// are already reviewing. Also clears the `dateHolds` lock, but only if
  /// it still points back to this booking — guards against ever deleting
  /// someone else's newer, legitimate lock on the same date.
  static Future<void> expireHold(String bookingId, {String reason = 'No payment receipt sent within the 15-minute hold.'}) async {
    final ref = _col.doc(bookingId);
    final snap = await ref.get();
    final data = snap.data();
    if (data == null) return;
    if ((data['status'] as String? ?? '') != 'awaiting_receipt') return;

    final batch = _db.batch();
    batch.update(ref, {
      'status': 'cancelled',
      'rejectionReason': reason,
      'autoRejected': true,
      'statusUpdatedAt': FieldValue.serverTimestamp(),
      'holdExpiresAt': FieldValue.delete(),
    });

    final dateTs = data['date'];
    if (dateTs is Timestamp) {
      final lockRef = _locksCol.doc(_dateKey(dateTs.toDate()));
      final lockSnap = await lockRef.get();
      if (lockSnap.exists && lockSnap.data()?['bookingId'] == bookingId) {
        batch.delete(lockRef);
      }
    }
    await batch.commit();
  }

  /// Live stream of a user's own bookings, most recent first.
  ///
  /// Cache-first: the customer's saved bookings in the local database show
  /// immediately (and when offline), then live Firestore updates replace
  /// them. The local copy is cleared on logout.
  static Stream<List<Map<String, dynamic>>> watchBookingsForUser(String userId) {
    final remote = _col.where('userId', isEqualTo: userId).snapshots().map((snap) {
      final list = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      list.sort((a, b) {
        final at = a['createdAt'];
        final bt = b['createdAt'];
        final ad = at is Timestamp ? at.toDate() : DateTime(0);
        final bd = bt is Timestamp ? bt.toDate() : DateTime(0);
        return bd.compareTo(ad);
      });
      return Synced<Map<String, dynamic>>(list, fromCache: snap.metadata.isFromCache);
    });
    return OfflineCache.cacheFirst<Map<String, dynamic>>(
      readLocal: () => LocalDb.instance.loadBookingsForUser(userId),
      remote: remote,
      writeLocal: (items) => LocalDb.instance.replaceBookingsForUser(userId, items),
    );
  }

  /// Clears the "staff just changed this booking's status" flag once the
  /// customer has actually seen it in their notification bell — same
  /// `notifyCustomer` field Staff/Admin set to `true` on approve/reject,
  /// just flipped back off from this side instead of a push notification
  /// consuming it.
  static Future<void> markNotificationSeen(String bookingId) async {
    await _col.doc(bookingId).update({'notifyCustomer': false});
  }

  /// Live stream of this customer's unseen status-change notifications —
  /// every booking of theirs where staff/admin just approved, rejected,
  /// or auto-cancelled it (`notifyCustomer == true`) and they haven't
  /// opened the notification bell to clear it yet. Powers the bell badge
  /// on the dashboard and the "you're approved" banner. Most recently
  /// updated first.
  static Stream<List<Map<String, dynamic>>> watchNotifications(String userId) {
    return _col
        .where('userId', isEqualTo: userId)
        .where('notifyCustomer', isEqualTo: true)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      list.sort((a, b) {
        final at = a['statusUpdatedAt'] ?? a['createdAt'];
        final bt = b['statusUpdatedAt'] ?? b['createdAt'];
        final ad = at is Timestamp ? at.toDate() : DateTime(0);
        final bd = bt is Timestamp ? bt.toDate() : DateTime(0);
        return bd.compareTo(ad);
      });
      return list;
    });
  }
}