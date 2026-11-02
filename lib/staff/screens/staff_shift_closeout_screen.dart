import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/pos_transaction_record.dart';
import '../models/shift_closing_record.dart';
import '../services/auth_service.dart';
import '../services/pos_repository.dart';
import '../services/shift_closing_repository.dart';
import '../../shared/text_draft.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

String _peso(int amount) => '₱${NumberFormat('#,##0').format(amount)}';

/// End-of-shift cash count: shows the sales this staff member rang up
/// since their last close-out (or since midnight if they haven't closed
/// one yet today), asks them to count the actual drawer, and shows the
/// variance before saving. Once saved, a closing can't be edited — see
/// `ShiftClosingRepository`.
///
/// Redesigned as sectioned cards (Sales summary / Cash count / Notes)
/// with a live variance banner that changes color the moment the counted
/// amount stops matching the expected total, and a results screen shaped
/// like the POS receipt dialog instead of a generic system alert.
class StaffShiftCloseoutScreen extends StatefulWidget {
  const StaffShiftCloseoutScreen({super.key});

  @override
  State<StaffShiftCloseoutScreen> createState() => _StaffShiftCloseoutScreenState();
}

class _StaffShiftCloseoutScreenState extends State<StaffShiftCloseoutScreen> {
  final _openingFloatController = TextEditingController(text: '0');
  final _countedCashController = TextEditingController();
  final _notesController = TextEditingController();
  late final TextDraft _draft;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Notes only: cash counts are money entries and are always typed fresh.
    _draft = TextDraft('shift_closeout_notes_v1', {'notes': _notesController});
    _draft.restore(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _openingFloatController.dispose();
    _countedCashController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  DateTime _periodStartFor(List<ShiftClosingRecord> allClosings, String staffId) {
    final mine = allClosings.where((c) => c.staffId == staffId).toList();
    if (mine.isEmpty) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day);
    }
    // watchRecent() is already newest-first, so the first match is the
    // most recent close-out this staff member submitted.
    return mine.first.closedAt;
  }

  Future<void> _submit(int expectedCash, int cashSales, int gcashSales, int salesCount, DateTime periodStart) async {
    if (_submitting) return;
    final openingFloat = int.tryParse(_openingFloatController.text.trim()) ?? 0;
    final countedCash = int.tryParse(_countedCashController.text.trim());
    if (countedCash == null) {
      setState(() => _error = "Enter how much cash you counted in the drawer.");
      return;
    }
    if (countedCash < 0) {
      setState(() => _error = "That can't be negative.");
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final staffId = AuthService.instance.currentUid ?? '';
      final staffEmail = AuthService.instance.currentEmail ?? '';
      if (staffId.isEmpty) throw Exception("Your session expired. Please sign in again.");
      final closedAt = DateTime.now();
      await ShiftClosingRepository.createClosing(
        staffId: staffId,
        staffEmail: staffEmail,
        periodStart: periodStart,
        closedAt: closedAt,
        salesCount: salesCount,
        cashSales: cashSales,
        gcashSales: gcashSales,
        openingFloat: openingFloat,
        expectedCash: expectedCash,
        countedCash: countedCash,
        notes: _notesController.text.trim(),
      ).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      final variance = countedCash - expectedCash;
      await showDialog<void>(
        context: context,
        builder: (_) => _ClosingResultDialog(countedCash: countedCash, expectedCash: expectedCash, variance: variance),
      );
      await _draft.clear();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  InputDecoration _decor(BuildContext context, {String? label, String? hint, String? prefixText}) {
    OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));
    return InputDecoration(
      isDense: true,
      labelText: label,
      hintText: hint,
      prefixText: prefixText,
      labelStyle: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context)),
      hintStyle: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context)),
      filled: true,
      fillColor: AppPalette.surface(context),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      border: b(Colors.transparent),
      enabledBorder: b(Colors.transparent),
      focusedBorder: b(AppColors.accent, 1.4),
    );
  }

  Widget _section(BuildContext context, {required IconData icon, required String title, String? subtitle, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.soft,
        border: Border.all(color: AppPalette.divider(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.accentTint(0.10), borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, size: 16, color: AppColors.accent),
              ),
              const SizedBox(width: 10),
              Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Padding(padding: const EdgeInsets.only(left: 40), child: Text(subtitle, style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)))),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.surface(context),
      appBar: AppBar(
        backgroundColor: AppPalette.surface(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: const Text("Close Shift", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
      ),
      body: StreamBuilder<List<PosTransactionRecord>>(
        stream: PosRepository.watchAllTransactions(),
        builder: (context, posSnap) {
          return StreamBuilder<List<ShiftClosingRecord>>(
            stream: ShiftClosingRepository.watchRecent(),
            builder: (context, closingSnap) {
              if (posSnap.hasError || closingSnap.hasError) {
                return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text("Couldn't load shift data. Check your connection and try again.", textAlign: TextAlign.center, style: TextStyle(color: AppPalette.textMuted(context)))));
              }
              if (!posSnap.hasData || !closingSnap.hasData) {
                return const Center(child: CircularProgressIndicator(color: AppColors.accent));
              }
              final staffId = AuthService.instance.currentUid ?? '';
              final periodStart = _periodStartFor(closingSnap.data!, staffId);
              final mySales = posSnap.data!.where((s) => s.staffId == staffId && s.createdAt.isAfter(periodStart)).toList();

              final cashSales = mySales.where((s) => s.paymentMethod == 'cash').fold<int>(0, (sum, s) => sum + s.total);
              final gcashSales = mySales.where((s) => s.paymentMethod == 'gcash').fold<int>(0, (sum, s) => sum + s.total);
              final openingFloat = int.tryParse(_openingFloatController.text.trim()) ?? 0;
              final expectedCash = openingFloat + cashSales;
              final countedCash = int.tryParse(_countedCashController.text.trim());
              final variance = countedCash != null ? countedCash - expectedCash : null;
              final varianceColor = variance == null
                  ? AppPalette.textMuted(context)
                  : (variance == 0 ? const Color(0xFF2E7D32) : (variance > 0 ? const Color(0xFF1565C0) : const Color(0xFFC62828)));

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [AppColors.accent, Color.lerp(AppColors.accent, Colors.black, 0.25)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    margin: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), shape: BoxShape.circle),
                          child: const Icon(Icons.point_of_sale_rounded, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${mySales.length} sale${mySales.length == 1 ? '' : 's'} this shift', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                              const SizedBox(height: 2),
                              Text('Since ${DateFormat('MMM d, h:mm a').format(periodStart)}', style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.78))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _section(
                    context,
                    icon: Icons.receipt_long_outlined,
                    title: "Sales summary",
                    child: Column(
                      children: [
                        _summaryRow(context, Icons.payments_outlined, "Cash sales", _peso(cashSales)),
                        const SizedBox(height: 10),
                        _summaryRow(context, Icons.qr_code_2_rounded, "GCash sales", _peso(gcashSales)),
                      ],
                    ),
                  ),
                  _section(
                    context,
                    icon: Icons.savings_outlined,
                    title: "Opening float",
                    subtitle: "Change fund already in the drawer at the start of this shift.",
                    child: TextField(
                      controller: _openingFloatController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context)),
                      decoration: _decor(context, label: "Amount", prefixText: '₱ '),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(color: AppColors.accentTint(0.08), borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Expected cash in drawer", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context))),
                        Text(_peso(expectedCash), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.accent)),
                      ],
                    ),
                  ),
                  _section(
                    context,
                    icon: Icons.calculate_outlined,
                    title: "Cash you counted",
                    subtitle: "Count the drawer and enter the total.",
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _countedCashController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
                          onChanged: (_) => setState(() {}),
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context)),
                          decoration: _decor(context, label: "Amount counted", prefixText: '₱ '),
                        ),
                        if (variance != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(color: varianceColor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
                            child: Row(
                              children: [
                                Icon(variance == 0 ? Icons.check_circle_rounded : (variance > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded), size: 18, color: varianceColor),
                                const SizedBox(width: 8),
                                Text(
                                  variance == 0 ? "Balanced" : (variance > 0 ? "Over by ${_peso(variance)}" : "Short by ${_peso(-variance)}"),
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: varianceColor),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _section(
                    context,
                    icon: Icons.notes_outlined,
                    title: "Notes",
                    subtitle: "Optional — e.g. reason for a shortage/overage.",
                    child: TextField(
                      controller: _notesController,
                      maxLines: 3,
                      inputFormatters: [LengthLimitingTextInputFormatter(300)],
                      style: TextStyle(fontSize: 13, color: AppPalette.textPrimary(context)),
                      decoration: _decor(context, hint: "Add a note…"),
                    ),
                  ),
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: AppColors.accentTint(0.08), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline, size: 16, color: AppColors.accent),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.accent, fontSize: 12.5))),
                        ],
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : () => _submit(expectedCash, cashSales, gcashSales, mySales.length, periodStart),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _submitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text("Submit Close-out", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
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

  Widget _summaryRow(BuildContext context, IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppPalette.textMuted(context)),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, color: AppPalette.textSecondary(context)))),
        Text(value, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
      ],
    );
  }
}

/// Result screen shown right after a shift is closed — styled like the
/// POS "Sale complete" receipt (big icon, big number, clean card) instead
/// of a generic system alert dialog.
class _ClosingResultDialog extends StatelessWidget {
  final int countedCash;
  final int expectedCash;
  final int variance;

  const _ClosingResultDialog({required this.countedCash, required this.expectedCash, required this.variance});

  Widget _row(BuildContext context, String label, String value, {bool bold = false, Color? color}) {
    final style = TextStyle(fontSize: bold ? 14 : 12.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color ?? AppPalette.textPrimary(context));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style.copyWith(fontWeight: FontWeight.w500, color: bold ? style.color : AppPalette.textSecondary(context))),
          Text(value, style: style),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final balanced = variance == 0;
    final over = variance > 0;
    final color = balanced ? const Color(0xFF2E7D32) : (over ? const Color(0xFF1565C0) : const Color(0xFFC62828));

    return Dialog(
      backgroundColor: AppPalette.cardBg(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Icon(balanced ? Icons.check_rounded : Icons.info_outline_rounded, size: 32, color: color),
              ),
              const SizedBox(height: 14),
              Text(balanced ? "Shift closed — balanced" : "Shift closed", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context)), textAlign: TextAlign.center),
              const SizedBox(height: 2),
              Text(
                balanced ? "₱0" : (over ? "+${_peso(variance)}" : "-${_peso(-variance)}"),
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: color),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    _row(context, "Expected", _peso(expectedCash)),
                    _row(context, "Counted", _peso(countedCash)),
                    Divider(height: 18, color: AppPalette.divider(context)),
                    _row(context, "Variance", balanced ? "₱0" : (over ? "+${_peso(variance)}" : "-${_peso(-variance)}"), bold: true, color: color),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Done", style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}