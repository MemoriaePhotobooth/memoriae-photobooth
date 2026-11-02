import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/pos_transaction_record.dart';
import 'activity_log_repository.dart';

/// Admin-side, read/void access to `posTransactions` — the Staff app's
/// POS screen is the only place these are created (see
/// `lib/staff/services/pos_repository.dart`); Admin only reads them for
/// sales reporting and can void a mistaken entry (`firestore.rules`
/// allows delete for admins only — sales are otherwise immutable).
class PosRepository {
  PosRepository._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('posTransactions');

  /// Live feed of every sale, most recent first.
  static Stream<List<PosTransactionRecord>> watchAllTransactions() {
    return _col.orderBy('createdAt', descending: true).snapshots().map(
          (snap) => snap.docs.map(PosTransactionRecord.fromFirestore).toList(),
        );
  }

  /// Voids a mistaken sale. There's no "edit" — a wrong sale gets deleted
  /// and re-rung, so the log never holds a silently-modified total.
  static Future<void> deleteTransaction(String transactionId) async {
    final snap = await _col.doc(transactionId).get();
    final d = snap.data();
    await _col.doc(transactionId).delete();
    final total = d?['total'] ?? 0;
    final method = (d?['paymentMethod'] ?? '') == 'gcash' ? 'GCash' : 'Cash';
    final by = (d?['staffEmail'] ?? '') as String;
    await ActivityLogRepository.log(
      action: 'Voided POS sale',
      targetSummary: '₱$total $method sale${by.isNotEmpty ? " (rung up by $by)" : ""}',
    );
  }
}