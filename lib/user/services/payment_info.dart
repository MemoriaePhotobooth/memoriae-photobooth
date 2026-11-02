/// How a booking's total has been paid so far, derived from the raw
/// `bookings/{id}` map. Used by the invoice screen, the invoice PDF and
/// My Bookings so they can never disagree.
///
/// Bookings made before downpayments existed have no `paymentOption`
/// field — they're treated as fully paid, exactly as before.
class PaymentInfo {
  final int total;
  final int paid;
  final int balance;

  /// True when the customer chose a downpayment (even if the balance has
  /// since been settled).
  final bool isSplit;

  const PaymentInfo({required this.total, required this.paid, required this.balance, required this.isSplit});

  bool get hasBalance => balance > 0;

  factory PaymentInfo.fromBooking(Map<String, dynamic> b) {
    final price = (b['price'] as num?)?.toInt() ?? 0;
    final addOns = (b['addOnsPrice'] as num?)?.toInt() ?? 0;
    final total = price + addOns;
    final option = b['paymentOption'] as String?;
    if (option != 'downpayment') {
      return PaymentInfo(total: total, paid: total, balance: 0, isSplit: false);
    }
    final amountPaid = ((b['amountPaid'] as num?)?.toInt() ?? total).clamp(0, total).toInt();
    final settled = b['balancePaid'] == true;
    return PaymentInfo(
      total: total,
      paid: settled ? total : amountPaid,
      balance: settled ? 0 : total - amountPaid,
      isSplit: true,
    );
  }
}
