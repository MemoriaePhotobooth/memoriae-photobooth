/// Cash handling for a POS sale, kept free of widgets so it can be tested.
enum CashStatus { none, change, short }

class CashResult {
  final CashStatus status;

  /// Change to hand back (status `change`), or the amount still missing
  /// (status `short`). Zero when no cash was entered.
  final int amount;

  const CashResult(this.status, this.amount);
}

class PosCash {
  PosCash._();

  /// [received] is null when nothing (or not a whole number) was typed.
  static CashResult compare(int total, int? received) {
    if (received == null) return const CashResult(CashStatus.none, 0);
    if (received >= total) return CashResult(CashStatus.change, received - total);
    return CashResult(CashStatus.short, total - received);
  }
}
