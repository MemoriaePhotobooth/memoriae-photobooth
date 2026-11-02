import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/pos_transaction_record.dart';
import 'activity_log_repository.dart';

/// Firestore-backed repository for `posTransactions` — every over-the-
/// counter sale staff rings up through the POS screen. Admin reads the
/// same collection for sales reporting; only staff/admin ever write to
/// it (see `firestore.rules`), never the Customer app.
class PosRepository {
  PosRepository._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('posTransactions');

  /// Rings up a sale and returns the new transaction's id. [items] must
  /// be non-empty — the POS screen's "Complete Sale" button is disabled
  /// until the cart has at least one line, so this is a defensive check
  /// rather than something the UI needs to message around.
  static Future<String> createTransaction({
    required List<PosLineItem> items,
    required String paymentMethod,
    int? amountReceived,
    String referenceNote = '',
    required String staffId,
    required String staffEmail,
  }) async {
    if (items.isEmpty) {
      throw Exception("Add at least one item before completing the sale.");
    }
    final total = items.fold<int>(0, (sum, i) => sum + i.lineTotal);
    final ref = await _col.add({
      'items': items.map((i) => i.toMap()).toList(),
      'total': total,
      'paymentMethod': paymentMethod,
      'amountReceived': amountReceived,
      'referenceNote': referenceNote.trim(),
      'staffId': staffId,
      'staffEmail': staffEmail,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Audit trail: who rang up what. Best-effort — a failed log write
    // never makes a completed sale look like it failed.
    final count = items.fold<int>(0, (sum, i) => sum + i.quantity);
    final first = items.first.name;
    final more = items.length > 1 ? ' +${items.length - 1} more' : '';
    await ActivityLogRepository.log(
      action: 'Completed POS sale',
      targetSummary: '\u20b1$total ${paymentMethod == 'gcash' ? 'GCash' : 'Cash'} \u2014 $first$more ($count item${count == 1 ? '' : 's'})',
    );
    return ref.id;
  }

  /// Live feed of every sale, most recent first — used for today's
  /// running total on the POS screen itself.
  static Stream<List<PosTransactionRecord>> watchAllTransactions() {
    return _col.orderBy('createdAt', descending: true).snapshots().map(
          (snap) => snap.docs.map(PosTransactionRecord.fromFirestore).toList(),
        );
  }
}