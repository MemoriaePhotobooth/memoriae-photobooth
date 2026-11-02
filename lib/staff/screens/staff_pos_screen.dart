import '../../shared/app_modal.dart';
import '../../shared/top_toast.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/pos_cash.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/pos_transaction_record.dart';
import '../models/pricing_item_record.dart';
import '../services/auth_service.dart';
import '../services/pos_repository.dart';
import '../services/pricing_repository.dart';
import '../services/staff_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import 'staff_shift_closeout_screen.dart';

String _peso(int amount) => '₱${NumberFormat('#,##0').format(amount)}';

const Color _kDanger = Color(0xFFDC2626);

IconData _categoryIcon(String category) {
  switch (category) {
    case 'Booth Package':
      return Icons.photo_library_rounded;
    case 'Camera Rental':
      return Icons.photo_camera_rounded;
    case 'Add-on':
      return Icons.add_shopping_cart_rounded;
    default:
      return Icons.sell_rounded;
  }
}

/// Over-the-counter checkout: staff pick packages, camera-rental fees,
/// and add-ons (extra prints, merch, etc. — anything Admin has priced on
/// the shared `pricing` catalog) into a cart, then ring it up as Cash or
/// GCash. Every completed sale is logged to `posTransactions`
/// (see [PosRepository]) for Admin's sales reporting.
///
/// Layout:
///  * Wide (desktop / landscape tablet): two panes — the item catalog on the
///    left and a permanent "Current Sale" checkout panel on the right, so the
///    cart is always visible and nothing needs a pop-up.
///  * Narrow (phone): the catalog full-width, with a sticky cart bar at the
///    bottom that opens the same checkout panel as a bottom sheet.
class StaffPosScreen extends StatefulWidget {
  const StaffPosScreen({super.key});

  @override
  State<StaffPosScreen> createState() => _StaffPosScreenState();
}

class _StaffPosScreenState extends State<StaffPosScreen> {
  /// Width of this screen's own area at which the checkout panel moves from a
  /// bottom sheet to a permanent right-hand pane.
  static const double _splitBreakpoint = 820;

  // One shared stream so rebuilds (typing in search, adding to cart) don't
  // re-subscribe to Firestore.
  late final Stream<List<PricingItemRecord>> _catalogStream = PricingRepository.watchAllPricing();

  final _PosCart _cart = _PosCart();
  final TextEditingController _searchController = TextEditingController();
  String _category = 'All';
  String _query = '';

  /// Latest catalog snapshot — read by the checkout panel (inline or in the
  /// phone sheet) so it always prices lines from fresh data.
  List<PricingItemRecord> _catalog = const [];

  @override
  void dispose() {
    _cart.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _completeSale({required bool inSheet}) async {
    final lines = _cart.lines(_catalog);
    if (lines.isEmpty) return;

    final lineItems = <PosLineItem>[
      for (final l in lines) PosLineItem(name: l.item.name, category: l.item.category, unitPrice: l.item.price, quantity: l.quantity),
    ];
    final total = lineItems.fold<int>(0, (sum, i) => sum + i.lineTotal);

    int? amountReceived;
    if (_cart.payment == 'cash') {
      amountReceived = int.tryParse(_cart.cashReceived.text.trim());
      if (amountReceived == null || amountReceived < total) {
        TopToast.show(context, amountReceived == null ? "Enter the cash amount received." : "Amount received is less than the total.");
        return;
      }
    }

    _cart.setSubmitting(true);
    try {
      final staffId = AuthService.instance.currentUid ?? '';
      final staffEmail = AuthService.instance.currentEmail ?? '';
      await PosRepository.createTransaction(
        items: lineItems,
        paymentMethod: _cart.payment,
        amountReceived: amountReceived,
        referenceNote: _cart.reference.text,
        staffId: staffId,
        staffEmail: staffEmail,
      );
      if (!mounted) return;
      if (inSheet) Navigator.of(context).pop(); // close the phone cart sheet
      final usedPaymentMethod = _cart.payment;
      final reference = _cart.reference.text.trim();
      _cart.reset();
      await showDialog<void>(
        context: context,
        builder: (_) => _ReceiptDialog(
          items: lineItems,
          total: total,
          paymentMethod: usedPaymentMethod,
          amountReceived: amountReceived,
          reference: reference,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      TopToast.show(context, e.toString().replaceFirst('Exception: ', ''), kind: TopToastKind.error);
    } finally {
      if (mounted) _cart.setSubmitting(false);
    }
  }

  void _openCartSheet() {
    // The popup itself lifts above the keyboard while typing the cash amount.
    showAppModal<void>(
      context,
      maxWidth: 560,
      builder: (sheetContext) => _CheckoutPanel(
        cart: _cart,
        catalogOf: () => _catalog,
        onComplete: () => _completeSale(inSheet: true),
        inSheet: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: StreamBuilder<List<PricingItemRecord>>(
        stream: _catalogStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _centerMessage(context, Icons.error_outline_rounded, "Couldn't load the price list", "Check your connection and try again.");
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.accent));
          }
          final catalog = snapshot.data!;
          _catalog = catalog;
          if (catalog.isEmpty) {
            return _centerMessage(context, Icons.sell_outlined, "No priced items yet", "Add packages or add-ons in Admin › Pricing.");
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final split = constraints.maxWidth >= _splitBreakpoint;
              final catalogPane = _buildCatalogPane(context, catalog, split: split);

              if (!split) {
                return Column(
                  children: [
                    Expanded(child: catalogPane),
                    _buildCartBar(context, catalog),
                  ],
                );
              }

              final panelWidth = constraints.maxWidth >= 1200 ? 400.0 : 360.0;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: catalogPane),
                  SizedBox(
                    width: panelWidth,
                    child: _CheckoutPanel(
                      cart: _cart,
                      catalogOf: () => _catalog,
                      onComplete: () => _completeSale(inSheet: false),
                      inSheet: false,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // ───────────────────────── catalog (left / full-width) ─────────────────────────

  Widget _buildCatalogPane(BuildContext context, List<PricingItemRecord> catalog, {required bool split}) {
    final categories = ['All', ...catalog.map((c) => c.category).toSet()];
    // If Admin removed the last item of the selected category, fall back.
    if (!categories.contains(_category)) _category = 'All';

    final q = _query.trim().toLowerCase();
    final visible = catalog.where((c) {
      final inCategory = _category == 'All' || c.category == _category;
      final matches = q.isEmpty || c.name.toLowerCase().contains(q) || c.category.toLowerCase().contains(q);
      return inCategory && matches;
    }).toList();

    final pad = split ? 24.0 : 16.0;
    final chips = _buildCategoryChips(context, catalog, categories, pad: split ? 0 : pad);
    final search = _buildSearchField(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, split ? 22 : 8, pad, 14),
          child: _buildHeader(context, split: split),
        ),
        if (split)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: Row(
              children: [
                Expanded(child: chips),
                const SizedBox(width: 16),
                SizedBox(width: 260, child: search),
              ],
            ),
          )
        else ...[
          Padding(padding: EdgeInsets.symmetric(horizontal: pad), child: search),
          const SizedBox(height: 10),
          chips,
        ],
        const SizedBox(height: 14),
        Expanded(
          child: visible.isEmpty
              ? _centerMessage(
                  context,
                  Icons.search_off_rounded,
                  q.isEmpty ? "Nothing in this category" : 'No items match "$_query"',
                  "Try a different search or category.",
                )
              : ListenableBuilder(
                  listenable: _cart,
                  builder: (context, _) => GridView.builder(
                    padding: EdgeInsets.fromLTRB(pad, 2, pad, split ? 24 : 12),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 230,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 238,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final item = visible[i];
                      return _CatalogTile(
                        item: item,
                        qty: _cart.qtyOf(item.id),
                        onAdd: () => _cart.add(item.id),
                        onRemove: () => _cart.remove(item.id),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, {required bool split}) {
    final closeShift = OutlinedButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const StaffShiftCloseoutScreen()),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.accent,
        side: const BorderSide(color: AppColors.accent),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: const Icon(Icons.receipt_long_rounded, size: 16),
      label: const Text("Close Shift", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
    );

    // Wrap (not Row) so the stats pill + button drop to a second line on
    // narrow widths instead of overflowing.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 10,
      spacing: 12,
      children: [
        if (split)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.accentTint(0.1), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.point_of_sale_rounded, color: AppColors.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Point of Sale", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppPalette.textPrimary(context))),
                  const SizedBox(height: 2),
                  Text("Tap an item to add it to the sale", style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
                ],
              ),
            ],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _TodayStats(),
            const SizedBox(width: 10),
            closeShift,
          ],
        ),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _query = v),
      style: TextStyle(fontSize: 13.5, color: AppPalette.textPrimary(context)),
      decoration: InputDecoration(
        isDense: true,
        hintText: "Search items",
        hintStyle: TextStyle(fontSize: 13.5, color: AppPalette.textMuted(context)),
        prefixIcon: Icon(Icons.search_rounded, size: 19, color: AppPalette.textMuted(context)),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 17),
                color: AppPalette.textMuted(context),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
        filled: true,
        fillColor: AppPalette.surface(context),
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildCategoryChips(BuildContext context, List<PricingItemRecord> catalog, List<String> categories, {required double pad}) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: pad),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final cat = categories[i];
          final count = cat == 'All' ? catalog.length : catalog.where((c) => c.category == cat).length;
          return _CategoryPill(
            label: cat,
            count: count,
            selected: _category == cat,
            onTap: () => setState(() => _category = cat),
          );
        },
      ),
    );
  }

  // ───────────────────────── phone cart bar ─────────────────────────

  Widget _buildCartBar(BuildContext context, List<PricingItemRecord> catalog) {
    return ListenableBuilder(
      listenable: _cart,
      builder: (context, _) {
        final lines = _cart.lines(catalog);
        final count = lines.fold<int>(0, (s, l) => s + l.quantity);
        final total = lines.fold<int>(0, (s, l) => s + l.total);

        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.bottomCenter,
          child: count == 0
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: Material(
                    color: AppColors.accent,
                    elevation: 6,
                    shadowColor: AppColors.accent.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _openCartSheet,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), shape: BoxShape.circle),
                              child: const Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('$count item${count == 1 ? '' : 's'}', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
                                  Text(_peso(total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3)),
                                ],
                              ),
                            ),
                            const Text("View cart", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                            const SizedBox(width: 2),
                            const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 22),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _centerMessage(BuildContext context, IconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.accentTint(0.08), shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.accent, size: 26),
            ),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
            const SizedBox(height: 4),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context))),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── cart state ─────────────────────────

class _CartLine {
  final PricingItemRecord item;
  final int quantity;
  const _CartLine(this.item, this.quantity);
  int get total => item.price * quantity;
}

/// Everything about the sale in progress. A [ChangeNotifier] so the inline
/// desktop panel, the catalog tiles, the phone cart bar and the phone cart
/// sheet all read one live state instead of passing setState around.
class _PosCart extends ChangeNotifier {
  final Map<String, int> qty = {}; // pricing item id -> quantity
  final TextEditingController reference = TextEditingController();
  final TextEditingController cashReceived = TextEditingController();
  String payment = StaffSettings.defaultPayment.value; // 'cash' | 'gcash'
  bool submitting = false;

  int qtyOf(String id) => qty[id] ?? 0;

  void add(String id) {
    qty[id] = qtyOf(id) + 1;
    notifyListeners();
  }

  void remove(String id) {
    final current = qtyOf(id);
    if (current <= 1) {
      qty.remove(id);
    } else {
      qty[id] = current - 1;
    }
    notifyListeners();
  }

  void setPayment(String method) {
    payment = method;
    notifyListeners();
  }

  void setCash(int amount) {
    cashReceived.text = '$amount';
    notifyListeners();
  }

  /// Called from the cash field's onChanged so change/"short by" updates live.
  void cashChanged() => notifyListeners();

  void setSubmitting(bool value) {
    submitting = value;
    notifyListeners();
  }

  void reset() {
    qty.clear();
    reference.clear();
    cashReceived.clear();
    payment = StaffSettings.defaultPayment.value;
    notifyListeners();
  }

  /// Cart lines resolved against the catalog. Items Admin deleted mid-sale
  /// are skipped (same as before).
  List<_CartLine> lines(List<PricingItemRecord> catalog) {
    final out = <_CartLine>[];
    for (final entry in qty.entries) {
      final match = catalog.where((c) => c.id == entry.key);
      if (match.isEmpty) continue;
      out.add(_CartLine(match.first, entry.value));
    }
    return out;
  }

  @override
  void dispose() {
    reference.dispose();
    cashReceived.dispose();
    super.dispose();
  }
}

// ───────────────────────── checkout panel ─────────────────────────

/// "Current Sale": cart lines, total, payment method, cash/change and the
/// Complete Sale button. Used inline as the desktop right pane
/// (`inSheet: false`) and inside the phone's bottom sheet (`inSheet: true`).
class _CheckoutPanel extends StatelessWidget {
  final _PosCart cart;
  final List<PricingItemRecord> Function() catalogOf;
  final VoidCallback onComplete;
  final bool inSheet;

  const _CheckoutPanel({required this.cart, required this.catalogOf, required this.onComplete, required this.inSheet});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) {
        final lines = cart.lines(catalogOf());
        final total = lines.fold<int>(0, (s, l) => s + l.total);
        final count = lines.fold<int>(0, (s, l) => s + l.quantity);

        if (inSheet) {
          return Container(
            color: AppPalette.cardBg(context),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _header(context, count, hasLines: lines.isNotEmpty, padding: const EdgeInsets.fromLTRB(20, 16, 8, 4)),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                      child: lines.isEmpty
                          ? _emptyState(context)
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final l in lines) ...[
                                  _CartLineTile(line: l, cart: cart),
                                  const SizedBox(height: 8),
                                ],
                                const SizedBox(height: 8),
                                _footer(context, total),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Desktop right pane: header + scrolling lines + pinned payment footer.
        return Container(
          decoration: BoxDecoration(
            color: AppPalette.surface(context),
            border: Border(left: BorderSide(color: AppPalette.divider(context))),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context, count, hasLines: lines.isNotEmpty, padding: const EdgeInsets.fromLTRB(20, 22, 12, 10)),
                  Expanded(
                    child: lines.isEmpty
                        ? Center(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: _emptyState(context)))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                            itemCount: lines.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, i) => _CartLineTile(line: lines[i], cart: cart),
                          ),
                  ),
                  if (lines.isNotEmpty)
                    // Capped so on a short window the lines list keeps some
                    // room and the footer scrolls instead of overflowing.
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.7),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppPalette.cardBg(context),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, -4))],
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                          child: _footer(context, total),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, int count, {required bool hasLines, required EdgeInsets padding}) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          const Icon(Icons.shopping_bag_rounded, color: AppColors.accent, size: 20),
          const SizedBox(width: 8),
          Text("Current Sale", style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: AppPalette.textPrimary(context))),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(999)),
              child: Text('$count', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ],
          const Spacer(),
          if (hasLines)
            TextButton.icon(
              onPressed: () => _confirmClear(context),
              style: TextButton.styleFrom(foregroundColor: AppPalette.textMuted(context), padding: const EdgeInsets.symmetric(horizontal: 10)),
              icon: const Icon(Icons.delete_sweep_outlined, size: 17),
              label: const Text("Clear", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          if (inSheet)
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, size: 20),
              color: AppPalette.textMuted(context),
              tooltip: "Close",
            ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.accentTint(0.08), shape: BoxShape.circle),
          child: const Icon(Icons.shopping_bag_outlined, color: AppColors.accent, size: 28),
        ),
        const SizedBox(height: 14),
        Text("No items yet", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
        const SizedBox(height: 4),
        Text("Tap any item to add it to this sale.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context))),
        if (inSheet) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.accent),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text("Back to items", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Clear this sale?"),
        content: const Text("All items will be removed from the cart."),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Keep")),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Clear", style: TextStyle(color: _kDanger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok == true) cart.reset();
  }

  Widget _footer(BuildContext context, int total) {
    final isCash = cart.payment == 'cash';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Total", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppPalette.textSecondary(context))),
            Text(_peso(total), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: AppColors.accent)),
          ],
        ),
        const SizedBox(height: 16),
        _sectionLabel(context, "PAYMENT"),
        Row(
          children: [
            Expanded(child: _payChoice(context, 'cash', "Cash", Icons.payments_outlined)),
            const SizedBox(width: 10),
            Expanded(child: _payChoice(context, 'gcash', "GCash", Icons.qr_code_2_rounded)),
          ],
        ),
        if (isCash) ...[
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('pos-cash'),
            controller: cart.cashReceived,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => cart.cashChanged(),
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context)),
            decoration: InputDecoration(
              isDense: true,
              prefixText: '₱ ',
              labelText: "Cash received",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final amount in _quickCashAmounts(total))
                _QuickAmountChip(
                  label: amount == total ? "Exact" : _peso(amount),
                  selected: int.tryParse(cart.cashReceived.text.trim()) == amount,
                  onTap: () => cart.setCash(amount),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _changeRow(context, total),
        ],
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('pos-ref'),
          controller: cart.reference,
          style: TextStyle(fontSize: 13, color: AppPalette.textPrimary(context)),
          decoration: InputDecoration(
            isDense: true,
            labelText: "Reference (optional)",
            hintText: cart.payment == 'gcash' ? "GCash ref no., booking ref, customer name…" : "Booking ref, customer name…",
            hintStyle: const TextStyle(fontSize: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: cart.submitting ? null : onComplete,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.5),
            disabledForegroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: cart.submitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_outline_rounded, size: 19),
                    const SizedBox(width: 8),
                    Text("Complete Sale · ${_peso(total)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppPalette.textMuted(context))),
    );
  }

  Widget _payChoice(BuildContext context, String value, String label, IconData icon) {
    final selected = cart.payment == value;
    return Material(
      color: selected ? AppColors.accent : AppPalette.surface(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? AppColors.accent : AppPalette.divider(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => cart.setPayment(value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
          child: Column(
            children: [
              Icon(icon, size: 20, color: selected ? Colors.white : AppPalette.textMuted(context)),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: selected ? Colors.white : AppPalette.textPrimary(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Always rendered (hint / change / short-by) so the form below it never
  /// shifts while the cashier types the amount.
  Widget _changeRow(BuildContext context, int total) {
    final cash = PosCash.compare(total, int.tryParse(cart.cashReceived.text.trim()));
    String label;
    String value;
    Color color;
    Color bg;
    if (cash.status == CashStatus.none) {
      label = "Change";
      value = "—";
      color = AppPalette.textMuted(context);
      bg = AppPalette.surface(context);
    } else if (cash.status == CashStatus.change) {
      label = "Change";
      value = _peso(cash.amount);
      color = AppColors.accent;
      bg = AppColors.accentTint(0.08);
    } else {
      label = "Short by";
      value = _peso(cash.amount);
      color = _kDanger;
      bg = _kDanger.withValues(alpha: 0.08);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
          Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  /// Exact amount plus the next few round bills, e.g. total ₱2,999 →
  /// Exact, ₱3,000, ₱4,000. Saves the cashier typing on a busy counter.
  List<int> _quickCashAmounts(int total) {
    int ceilTo(int step) => ((total + step - 1) ~/ step) * step;
    final options = <int>{total, ceilTo(100), ceilTo(500), ceilTo(1000), ceilTo(1000) + 1000};
    final sorted = options.where((v) => v >= total).toList()..sort();
    return sorted.take(4).toList();
  }
}

// ───────────────────────── small widgets ─────────────────────────

class _CategoryPill extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryPill({required this.label, required this.count, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accent : AppPalette.surface(context),
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppPalette.textPrimary(context))),
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? Colors.white.withValues(alpha: 0.22) : AppPalette.divider(context),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('$count', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: selected ? Colors.white : AppPalette.textSecondary(context))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAmountChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _QuickAmountChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accent : AppColors.accentTint(0.08),
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: selected ? Colors.white : AppColors.accent)),
        ),
      ),
    );
  }
}

/// Loads Admin's `imageUrl`: either a normal URL or a `data:` URI (photos
/// Admin uploads are stored that way, which Image.network can't open on
/// phones). Shows [fallback] when there is no image or it fails to load.
Widget _itemImage(String url, {required double width, required double height, required Widget fallback}) {
  if (url.isEmpty) return fallback;
  if (url.startsWith('data:')) {
    final comma = url.indexOf(',');
    if (comma < 0) return fallback;
    try {
      final bytes = base64Decode(url.substring(comma + 1));
      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback,
      );
    } catch (_) {
      return fallback;
    }
  }
  return Image.network(
    url,
    width: width,
    height: height,
    fit: BoxFit.cover,
    errorBuilder: (_, __, ___) => fallback,
  );
}

/// Small square item thumbnail, falling back to a category icon badge when
/// there's no image (or it fails to load).
class _ItemThumb extends StatelessWidget {
  final PricingItemRecord item;
  final double size;

  const _ItemThumb({required this.item, required this.size});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.3);
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.accentTint(0.1), borderRadius: radius),
      child: Icon(_categoryIcon(item.category), size: size * 0.5, color: AppColors.accent),
    );
    return ClipRRect(
      borderRadius: radius,
      child: _itemImage(item.imageUrl, width: size, height: size, fallback: fallback),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool filled;

  const _StepButton({required this.icon, required this.onTap, required this.size, required this.filled});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: filled ? AppColors.accent : Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Icon(icon, size: 18, color: filled ? Colors.white : AppColors.accent),
        ),
      ),
    );
  }
}

/// − qty + control. [expand] stretches it to fill the width (catalog tile);
/// otherwise it hugs its content (cart line).
class _QtyStepper extends StatelessWidget {
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final bool expand;
  final double height;

  const _QtyStepper({required this.qty, required this.onAdd, required this.onRemove, this.expand = false, this.height = 34});

  @override
  Widget build(BuildContext context) {
    final button = height - 4;
    final count = Text('$qty', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context)));
    return Container(
      height: height,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: AppColors.accentTint(0.08), borderRadius: BorderRadius.circular(height)),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          _StepButton(icon: qty <= 1 ? Icons.delete_outline_rounded : Icons.remove_rounded, onTap: onRemove, size: button, filled: false),
          if (expand) Expanded(child: Center(child: count)) else SizedBox(width: 32, child: Center(child: count)),
          _StepButton(icon: Icons.add_rounded, onTap: onAdd, size: button, filled: true),
        ],
      ),
    );
  }
}

class _CatalogTile extends StatelessWidget {
  final PricingItemRecord item;
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _CatalogTile({required this.item, required this.qty, required this.onAdd, required this.onRemove});

  static const double _bannerHeight = 84;

  @override
  Widget build(BuildContext context) {
    final selected = qty > 0;
    final bannerFallback = Container(
      width: double.infinity,
      height: _bannerHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.accentTint(0.16), AppColors.accentTint(0.06)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(_categoryIcon(item.category), size: 34, color: AppColors.accent.withValues(alpha: 0.7)),
    );
    return Material(
      color: selected ? Color.alphaBlend(AppColors.accentTint(0.05), AppPalette.cardBg(context)) : AppPalette.cardBg(context),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? AppColors.accent : AppPalette.divider(context), width: selected ? 1.6 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      // The whole card adds one — fast on a busy counter.
      child: InkWell(
        onTap: onAdd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: _bannerHeight,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _itemImage(item.imageUrl, width: double.infinity, height: _bannerHeight, fallback: bannerFallback),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        item.category,
                        maxLines: 1,
                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: AppColors.stone900),
                      ),
                    ),
                  ),
                  if (selected)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(999)),
                        child: Text('$qty', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, height: 1.25, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
                    ),
                    if (item.unit.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(item.unit, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
                      ),
                    const Spacer(),
                    Text(_peso(item.price), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.accent)),
                    const SizedBox(height: 8),
                    if (selected)
                      // Swallows taps on the stepper's gaps so they don't add an item.
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {},
                        child: _QtyStepper(qty: qty, onAdd: onAdd, onRemove: onRemove, expand: true),
                      )
                    else
                      Container(
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: AppColors.accentTint(0.08), borderRadius: BorderRadius.circular(12)),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded, size: 17, color: AppColors.accent),
                            SizedBox(width: 4),
                            Text("Add", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.accent)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  final _CartLine line;
  final _PosCart cart;

  const _CartLineTile({required this.line, required this.cart});

  @override
  Widget build(BuildContext context) {
    final item = line.item;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.divider(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ItemThumb(item: item, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, height: 1.25, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                    ),
                    const SizedBox(width: 10),
                    Text(_peso(line.total), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text('${_peso(item.price)} each', style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
                    ),
                    _QtyStepper(qty: line.quantity, onAdd: () => cart.add(item.id), onRemove: () => cart.remove(item.id), height: 32),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Today ₱X · N sales" pill next to the POS title — a quick running total
/// so staff don't need to leave the screen to sanity-check the shift.
class _TodayStats extends StatefulWidget {
  const _TodayStats();

  @override
  State<_TodayStats> createState() => _TodayStatsState();
}

class _TodayStatsState extends State<_TodayStats> {
  late final Stream<List<PosTransactionRecord>> _stream = PosRepository.watchAllTransactions();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PosTransactionRecord>>(
      stream: _stream,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <PosTransactionRecord>[];
        final now = DateTime.now();
        final today = all.where((t) => t.createdAt.year == now.year && t.createdAt.month == now.month && t.createdAt.day == now.day).toList();
        final total = today.fold<int>(0, (sum, t) => sum + t.total);
        final n = today.length;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: AppColors.accentTint(0.08), borderRadius: BorderRadius.circular(14)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.trending_up_rounded, size: 16, color: AppColors.accent),
              const SizedBox(width: 8),
              Text("Today", style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context))),
              const SizedBox(width: 6),
              Text(_peso(total), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.accent)),
              const SizedBox(width: 8),
              Text('· $n sale${n == 1 ? '' : 's'}', style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
            ],
          ),
        );
      },
    );
  }
}

/// On-screen receipt shown right after a sale completes — no physical
/// printer integration (out of scope), but staff can screenshot this or
/// show it to the customer directly.
class _ReceiptDialog extends StatelessWidget {
  final List<PosLineItem> items;
  final int total;
  final String paymentMethod;
  final int? amountReceived;
  final String reference;

  const _ReceiptDialog({
    required this.items,
    required this.total,
    required this.paymentMethod,
    this.amountReceived,
    this.reference = '',
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppPalette.cardBg(context),
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.accentTint(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, color: AppColors.accent, size: 32),
                ),
              ),
              const SizedBox(height: 14),
              Text("Sale complete", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppPalette.textSecondary(context))),
              const SizedBox(height: 4),
              Text(_peso(total), textAlign: TextAlign.center, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: AppColors.accent)),
              const SizedBox(height: 2),
              Text(DateFormat('MMM d, y · h:mm a').format(DateTime.now()), textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
              const SizedBox(height: 18),
              Divider(height: 1, color: AppPalette.divider(context)),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final i in items)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text('${i.quantity}× ${i.name}', style: TextStyle(fontSize: 12.5, color: AppPalette.textPrimary(context))),
                              ),
                              const SizedBox(width: 10),
                              Text(_peso(i.lineTotal), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: AppPalette.divider(context)),
              const SizedBox(height: 12),
              _row(context, "Paid via", paymentMethod == 'gcash' ? 'GCash' : 'Cash'),
              if (amountReceived != null) ...[
                const SizedBox(height: 6),
                _row(context, "Cash received", _peso(amountReceived!)),
                const SizedBox(height: 6),
                _row(context, "Change", _peso(amountReceived! - total), bold: true),
              ],
              if (reference.isNotEmpty) ...[
                const SizedBox(height: 6),
                _row(context, "Reference", reference),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text("Done", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context))),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 12.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: bold ? AppColors.accent : AppPalette.textPrimary(context)),
          ),
        ),
      ],
    );
  }
}