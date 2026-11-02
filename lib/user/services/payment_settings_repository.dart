import 'package:cloud_firestore/cloud_firestore.dart';

/// How much a customer must pay up-front to lock their booking.
///
/// Stored by Admin in Firestore at `settings/payment` (see the Admin app's
/// `PaymentSettingsRepository`). The customer app only ever reads it.
///
/// Customers can always choose to pay in full instead — the downpayment is
/// the *minimum* they need to send to reserve the date.
class PaymentSettings {
  /// When false, every booking is full-payment only.
  final bool downpaymentEnabled;

  /// true  → [value] is a percentage of the total (1–99).
  /// false → [value] is a fixed peso amount.
  final bool isPercent;
  final int value;

  const PaymentSettings({
    this.downpaymentEnabled = true,
    this.isPercent = true,
    this.value = 30,
  });

  /// Used while loading, offline, or before Admin has saved anything.
  static const PaymentSettings defaults = PaymentSettings();

  /// The downpayment for a booking worth [total] pesos — never below ₱1
  /// and never more than [total].
  int downpaymentFor(int total) {
    if (total <= 0) return total;
    if (!downpaymentEnabled) return total;
    final raw = isPercent ? (total * value / 100).ceil() : value;
    if (raw >= total) return total;
    return raw < 1 ? 1 : raw;
  }

  /// Whether splitting makes sense at all for [total] — false when the
  /// downpayment would equal the full price (or downpayments are off).
  bool canSplit(int total) => downpaymentEnabled && downpaymentFor(total) < total;

  /// Short label like "30%" or "₱500".
  String get label => isPercent ? '$value%' : '₱$value';

  factory PaymentSettings.fromMap(Map<String, dynamic>? d) {
    if (d == null) return defaults;
    final type = (d['downpaymentType'] as String?) ?? 'percent';
    final v = (d['downpaymentValue'] as num?)?.toInt() ?? 30;
    return PaymentSettings(
      downpaymentEnabled: d['downpaymentEnabled'] != false,
      isPercent: type != 'fixed',
      value: v < 1 ? 1 : v,
    );
  }
}

/// Read-only access to `settings/payment` for the customer app.
class PaymentSettingsRepository {
  PaymentSettingsRepository._();

  static DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection('settings').doc('payment');

  /// Loads the current settings once. Any failure (offline, rules not
  /// deployed yet, no document) falls back to [PaymentSettings.defaults]
  /// so checkout is never blocked by this.
  static Future<PaymentSettings> fetch() async {
    try {
      final snap = await _doc.get();
      return PaymentSettings.fromMap(snap.data());
    } catch (_) {
      return PaymentSettings.defaults;
    }
  }
}
