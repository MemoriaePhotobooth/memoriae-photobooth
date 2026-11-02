import '../../shared/top_toast.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/camera_rental_record.dart';
import '../models/pricing_item_record.dart';
import '../services/pricing_repository.dart';
import '../services/camera_rental_repository.dart';
import '../services/rental_receipt_pdf.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/pagination_bar.dart';
import 'staff_new_rental_screen.dart';

const Color _overdueColor = Color(0xFFC62828);
const Color _activeColor = Color(0xFF2E7D32);
const Color _returnedColor = Color(0xFF9E9E9E);

/// Staff view of every camera rental — a customer renting a camera from
/// the "Rent" tab in the customer app shows up here the instant it's
/// created (live Firestore `cameraRentals` stream, shared with the Admin
/// and customer apps).
///
/// Redesigned around three clickable stat tiles (Active / Overdue /
/// Returned) that double as the status filter — same interaction as the
/// Bookings stat row — plus cards that make an overdue rental impossible
/// to miss (tinted red, bold countdown) instead of a plain bordered list.
class StaffCameraRentalsScreen extends StatefulWidget {
  const StaffCameraRentalsScreen({super.key});

  @override
  State<StaffCameraRentalsScreen> createState() => _StaffCameraRentalsScreenState();
}

class _StaffCameraRentalsScreenState extends State<StaffCameraRentalsScreen> {

  // ── Camera photos from the shared `pricing` collection ──────────────────
  StreamSubscription<List<PricingItemRecord>>? _pricingSub;
  final Map<String, String> _photoById = {};
  final Map<String, String> _photoByName = {};

  @override
  void initState() {
    super.initState();
    _pricingSub = PricingRepository.watchAllPricing().listen((items) {
      final byId = <String, String>{};
      final byName = <String, String>{};
      for (final p in items) {
        if (p.imageUrl.isEmpty) continue;
        byId[p.id] = p.imageUrl;
        byName[p.name.trim().toLowerCase()] = p.imageUrl;
      }
      if (!mounted) return;
      setState(() {
        _photoById..clear()..addAll(byId);
        _photoByName..clear()..addAll(byName);
      });
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _pricingSub?.cancel();
    super.dispose();
  }

  /// Photo of the camera a rental is for: matches `cameraId` first (survives
  /// a rename), then the camera name saved on the rental.
  String _photoFor(CameraRentalRecord r) =>
      _photoById[r.cameraId] ?? _photoByName[r.cameraName.trim().toLowerCase()] ?? '';
  String _statusFilter = 'all';
  bool _dueSoonestFirst = true;
  int _page = 0;
  static const int _pageSize = 10;

  List<CameraRentalRecord> _applyFilters(List<CameraRentalRecord> rentals) {
    final list = (_statusFilter == 'all' ? rentals : rentals.where((r) => r.status == _statusFilter).toList()).toList();
    list.sort((a, b) {
      final cmp = a.dueAt.compareTo(b.dueAt);
      return _dueSoonestFirst ? cmp : -cmp;
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CameraRentalRecord>>(
      stream: CameraRentalRepository.watchAllRentals(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accent));
        }
        final rentals = snapshot.data!;
        if (rentals.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.camera_alt_outlined, size: 40, color: AppPalette.textMuted(context)),
                const SizedBox(height: 10),
                Text("No camera rentals yet", style: TextStyle(fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
                const SizedBox(height: 2),
                Text("Start one when a customer walks in.", style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
                const SizedBox(height: 16),
                const _NewRentalButton(),
              ],
            ),
          );
        }

        final activeCount = rentals.where((r) => r.status == 'active').length;
        final overdueCount = rentals.where((r) => r.status == 'overdue').length;
        final returnedCount = rentals.where((r) => r.status == 'returned').length;
        final filtered = _applyFilters(rentals);
        _page = PageWindow.clamp(_page, filtered.length, pageSize: _pageSize);
        final pageItems = PageWindow.slice(filtered, _page, pageSize: _pageSize);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${activeCount + overdueCount} out right now',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppPalette.textSecondary(context)),
                    ),
                  ),
                  const _NewRentalButton(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: LayoutBuilder(builder: (context, c) {
                final tight = c.maxWidth < 460;
                final tiles = [
                  _StatTile(icon: Icons.camera_alt_rounded, color: AppColors.accent, value: '${rentals.length}', label: 'All', active: _statusFilter == 'all', onTap: () => setState(() { _statusFilter = 'all'; _page = 0; })),
                  _StatTile(icon: Icons.timelapse_rounded, color: _activeColor, value: '$activeCount', label: 'Active', active: _statusFilter == 'active', onTap: () => setState(() { _statusFilter = 'active'; _page = 0; })),
                  _StatTile(icon: Icons.warning_amber_rounded, color: _overdueColor, value: '$overdueCount', label: 'Overdue', active: _statusFilter == 'overdue', onTap: () => setState(() { _statusFilter = 'overdue'; _page = 0; })),
                  _StatTile(icon: Icons.check_circle_outline_rounded, color: _returnedColor, value: '$returnedCount', label: 'Returned', active: _statusFilter == 'returned', onTap: () => setState(() { _statusFilter = 'returned'; _page = 0; })),
                ];
                if (tight) {
                  return SizedBox(
                    height: 80,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: tiles.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, i) => SizedBox(width: 128, child: tiles[i]),
                    ),
                  );
                }
                return Row(children: [for (final t in tiles) ...[Expanded(child: t), if (t != tiles.last) const SizedBox(width: 12)]]);
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                children: [
                  Text("Sort", style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
                  const Spacer(),
                  Tooltip(
                    message: _dueSoonestFirst ? "Due soonest first" : "Due latest first",
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() { _dueSoonestFirst = !_dueSoonestFirst; _page = 0; }),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppPalette.textPrimary(context),
                        side: BorderSide(color: AppPalette.divider(context)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: Icon(_dueSoonestFirst ? Icons.arrow_upward : Icons.arrow_downward, size: 14),
                      label: const Text("Due date", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text("No rentals match this filter.", style: TextStyle(color: AppPalette.textMuted(context))))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: pageItems.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _RentalCard(rental: pageItems[i], imageUrl: _photoFor(pageItems[i])),
                    ),
            ),
            PaginationBar(
              page: _page,
              pageCount: PageWindow.pageCount(filtered.length, pageSize: _pageSize),
              onPageChanged: (p) => setState(() => _page = p),
            ),
          ],
        );
      },
    );
  }
}

/// Opens the walk-in rental form.
class _NewRentalButton extends StatelessWidget {
  const _NewRentalButton();

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StaffNewRentalScreen())),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('New rental', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
    );
  }
}

/// Clickable metric tile — same visual language as the Bookings stat
/// row, reused here so both sections feel like one product.
class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _StatTile({required this.icon, required this.color, required this.value, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppPalette.cardBg(context),
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppShadows.soft,
            border: Border.all(color: active ? color : AppPalette.divider(context), width: active ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// Camera photo for a rental card (handles `data:` URIs and http(s) URLs),
/// falling back to the camera icon when the camera has no photo.
class _CameraThumb extends StatelessWidget {
  final String imageUrl;
  final Color color;
  const _CameraThumb({required this.imageUrl, required this.color});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      alignment: Alignment.center,
      color: color.withValues(alpha: 0.14),
      child: Icon(Icons.camera_alt_rounded, size: 22, color: color),
    );
    Widget child = fallback;
    if (imageUrl.startsWith('data:')) {
      try {
        final bytes = base64Decode(imageUrl.substring(imageUrl.indexOf(',') + 1));
        child = Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, __, ___) => fallback);
      } catch (_) {}
    } else if (imageUrl.startsWith('http')) {
      child = Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(width: 56, height: 56, child: child),
    );
  }
}

class _RentalCard extends StatefulWidget {
  final CameraRentalRecord rental;
  final String imageUrl;
  const _RentalCard({required this.rental, this.imageUrl = ''});

  @override
  State<_RentalCard> createState() => _RentalCardState();
}

class _RentalCardState extends State<_RentalCard> {
  Timer? _ticker;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    // Acknowledge as soon as staff actually sees this card, clearing the
    // notification badge for it.
    if (!widget.rental.acknowledged) {
      CameraRentalRepository.acknowledge(widget.rental.id);
    }
    if (!widget.rental.isReturned) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Asks about the camera's condition (and any late fee) before checking
  /// it in, so the record is complete the moment it's marked returned —
  /// same flow as the Admin app.
  Future<void> _markReturned() async {
    final result = await _showChargesDialog(context, widget.rental, returning: true);
    if (result == null || !mounted) return;
    setState(() => _updating = true);
    try {
      await CameraRentalRepository.markReturned(
        widget.rental.id,
        overdueFee: result.overdueFee,
        damageFee: result.damageFee,
        damageNote: result.damageNote,
        depositRefunded: result.depositRefund,
      );
    } catch (e) {
      if (mounted) {
        TopToast.show(context, "Couldn't update: ${e.toString().replaceFirst('Exception: ', '')}", kind: TopToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _editCharges() async {
    final result = await _showChargesDialog(context, widget.rental, returning: false);
    if (result == null || !mounted) return;
    try {
      await CameraRentalRepository.updateCharges(
        widget.rental.id,
        overdueFee: result.overdueFee,
        damageFee: result.damageFee,
        damageNote: result.damageNote,
      );
    } catch (_) {
      if (mounted) {
        TopToast.show(context, "Couldn't save the fees. Please try again.", kind: TopToastKind.error);
      }
    }
  }

  Future<void> _printReceipt() async {
    try {
      await RentalReceiptPdf.printReceipt(widget.rental);
    } catch (_) {
      if (mounted) {
        TopToast.show(context, "Couldn't open the receipt. Please try again.", kind: TopToastKind.error);
      }
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'overdue':
        return _overdueColor;
      case 'returned':
        return _returnedColor;
      default:
        return _activeColor;
    }
  }

  String _statusLabel(String status) => status.isEmpty ? '' : status[0].toUpperCase() + status.substring(1);

  String _remainingLabel() {
    final r = widget.rental;
    if (r.isReturned) return 'Returned ${DateFormat('MMM d, h:mm a').format(r.returnedAt!)}';
    final diff = r.dueAt.difference(DateTime.now());
    if (diff.isNegative) {
      final overdueBy = diff.abs();
      if (overdueBy.inDays > 0) return 'Overdue by ${overdueBy.inDays}d ${overdueBy.inHours % 24}h ${overdueBy.inMinutes % 60}m';
      return 'Overdue by ${overdueBy.inHours}h ${overdueBy.inMinutes % 60}m';
    }
    if (diff.inDays > 0) return '${diff.inDays}d ${diff.inHours % 24}h ${diff.inMinutes % 60}m ${diff.inSeconds % 60}s remaining';
    return '${diff.inHours}h ${diff.inMinutes % 60}m ${diff.inSeconds % 60}s remaining';
  }

  /// 0 = just rented, 1 = due right now (or past). Used to draw the
  /// progress bar on an active rental, so staff can see at a glance how
  /// close it is to its due time without doing the math themselves.
  double _progress() {
    final r = widget.rental;
    final total = r.dueAt.difference(r.rentedAt).inSeconds;
    if (total <= 0) return 1;
    final elapsed = DateTime.now().difference(r.rentedAt).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  Widget _chargesPanel(BuildContext context, CameraRentalRecord r) {
    final settled = r.feesSettled;
    final tint = r.totalFees == 0
        ? AppPalette.surface(context)
        : (settled ? _activeColor.withValues(alpha: 0.10) : _overdueColor.withValues(alpha: 0.08));
    Widget line(String label, int amount) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            children: [
              Expanded(child: Text(label, style: TextStyle(fontSize: 11.5, color: AppPalette.textSecondary(context)))),
              Text('₱$amount', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
            ],
          ),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r.overdueFee > 0) line('Overdue fee${r.overdueHours > 0 ? ' (${r.overdueHours}h late)' : ''}', r.overdueFee),
          if (r.damageFee > 0) line('Damage fee', r.damageFee),
          if (r.damageNote.trim().isNotEmpty) ...[
            if (r.totalFees > 0) const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.report_gmailerrorred_rounded, size: 14, color: AppPalette.textMuted(context)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(r.damageNote, style: TextStyle(fontSize: 11.5, height: 1.35, color: AppPalette.textPrimary(context))),
                ),
              ],
            ),
          ],
          if (r.totalFees > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text('Total fees ₱${r.totalFees}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                ),
                SizedBox(
                  height: 28,
                  child: OutlinedButton(
                    onPressed: () => CameraRentalRepository.setFeesSettled(r.id, !settled),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: settled ? _activeColor : AppColors.accent,
                      side: BorderSide(color: settled ? _activeColor : AppColors.accent),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(settled ? 'Paid ✓' : 'Mark paid', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rental;
    final color = _statusColor(r.status);
    final overdue = r.status == 'overdue';
    final returned = r.isReturned;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: overdue ? _overdueColor.withValues(alpha: 0.06) : AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: overdue ? _overdueColor.withValues(alpha: 0.35) : AppPalette.divider(context), width: overdue ? 1.4 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CameraThumb(imageUrl: widget.imageUrl, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(r.cameraName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context)))),
                        if (!r.acknowledged)
                          Container(width: 7, height: 7, margin: const EdgeInsets.only(left: 6), decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
                      ],
                    ),
                    Text(r.renterLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text(_statusLabel(r.status), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!returned) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: _progress(),
                minHeight: 5,
                backgroundColor: AppPalette.surface(context),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _remainingLabel(),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: returned ? AppPalette.textMuted(context) : color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (!returned)
                ElevatedButton(
                  onPressed: _updating ? null : _markReturned,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                  ),
                  child: _updating
                      ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text("Mark Returned", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: AppPalette.divider(context)),
          const SizedBox(height: 8),
          Text(
            'Rented ${DateFormat('MMM d, h:mm a').format(r.rentedAt)}  ·  Due ${DateFormat('MMM d, h:mm a').format(r.dueAt)}',
            style: TextStyle(fontSize: 10.5, color: AppPalette.textMuted(context)),
          ),
          if (r.isWalkIn && r.walkInDetails.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(r.walkInDetails, style: TextStyle(fontSize: 10.5, height: 1.4, color: AppPalette.textSecondary(context))),
          ],
          if (r.hasCharges) ...[
            const SizedBox(height: 10),
            _chargesPanel(context, r),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (r.isWalkIn) ...[
                Expanded(
                  child: _ActionPill(
                    icon: Icons.print_outlined,
                    label: 'Receipt',
                    onTap: _printReceipt,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                flex: r.isWalkIn ? 2 : 1,
                child: _ActionPill(
                  icon: Icons.receipt_long_outlined,
                  label: r.hasCharges ? 'Edit fees & notes' : 'Add fee / damage note',
                  onTap: _editCharges,
                  highlight: r.hasCharges,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Rounded, full-height tap target used for the card's footer actions
/// (Receipt, Add fee / damage note) — replaces the tiny plain text buttons.
class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;
  const _ActionPill({required this.icon, required this.label, required this.onTap, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final fg = highlight ? AppColors.accent : AppPalette.textSecondary(context);
    return Material(
      color: highlight ? AppColors.accentTint(0.08) : AppPalette.surface(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: highlight ? AppColors.accent.withValues(alpha: 0.35) : AppPalette.divider(context)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: fg),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What staff entered in the fees / condition dialog.
class _ChargesResult {
  final int overdueFee;
  final int damageFee;
  final String damageNote;

  /// How much of the rental deposit goes back to the customer (0 when
  /// there was no deposit, or when fees ate all of it).
  final int depositRefund;
  const _ChargesResult(this.overdueFee, this.damageFee, this.damageNote, [this.depositRefund = 0]);
}

/// Dialog for recording an overdue fee and/or a damage note + fee. When
/// [returning] it's the confirm step of "Mark Returned": a late rental
/// pre-fills the suggested overdue fee (hourly rate × hours late) which
/// can be changed or waived by setting it to 0.
Future<_ChargesResult?> _showChargesDialog(BuildContext context, CameraRentalRecord r, {required bool returning}) {
  final suggested = r.suggestedOverdueFee;
  final overdueController = TextEditingController(
    text: r.overdueFee > 0 ? '${r.overdueFee}' : (returning && suggested > 0 ? '$suggested' : ''),
  );
  final damageFeeController = TextEditingController(text: r.damageFee > 0 ? '${r.damageFee}' : '');
  final noteController = TextEditingController(text: r.damageNote);

  int parse(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  return showDialog<_ChargesResult>(
    context: context,
    builder: (dialogContext) {
      InputDecoration deco(String label, {String? prefix, String? hint}) => InputDecoration(
            labelText: label,
            hintText: hint,
            prefixText: prefix,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          );
      return AlertDialog(
        title: Text(returning ? 'Check in ${r.cameraName}' : 'Fees & notes'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (r.overdueHours > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '${r.overdueHours}h past due'
                    '${suggested > 0 ? ' · suggested late fee ₱$suggested (₱${(r.dailyRate / 24).toStringAsFixed(0)}/hr)' : ''}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _overdueColor),
                  ),
                ),
              TextField(
                controller: overdueController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: deco('Overdue fee', prefix: '₱ ', hint: '0 = no fee'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                maxLines: 3,
                minLines: 2,
                maxLength: 300,
                decoration: deco('Damage / condition notes', hint: 'e.g. scratch on lens hood, missing battery'),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: damageFeeController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: deco('Damage fee', prefix: '₱ ', hint: '0 = no fee'),
              ),
              if (returning && r.deposit > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: ListenableBuilder(
                    listenable: Listenable.merge([overdueController, damageFeeController]),
                    builder: (_, __) {
                      final left = r.deposit - parse(overdueController) - parse(damageFeeController);
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (left >= 0 ? const Color(0xFF2E7D32) : _overdueColor).withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          left >= 0
                              ? 'Deposit held ₱${r.deposit} — give back ₱$left'
                              : 'Deposit held ₱${r.deposit} — fees are ₱${-left} more, collect the difference',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(dialogContext).pop(
              _ChargesResult(
                parse(overdueController),
                parse(damageFeeController),
                noteController.text,
                returning ? (r.deposit - parse(overdueController) - parse(damageFeeController)).clamp(0, r.deposit).toInt() : r.depositRefunded,
              ),
            ),
            child: Text(returning ? 'Confirm return' : 'Save'),
          ),
        ],
      );
    },
  );
}