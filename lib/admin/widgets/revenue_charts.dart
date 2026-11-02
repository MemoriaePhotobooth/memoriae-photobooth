import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/booking_record.dart';
import '../models/pos_transaction_record.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

String _peso(int amount) => '₱${NumberFormat('#,##0').format(amount)}';

/// Compact peso label for above a bar — "₱850", "₱2.5k", "₱1.2M".
String _shortPeso(int v) {
  if (v >= 1000000) return '₱${(v / 1000000).toStringAsFixed(v % 1000000 == 0 ? 0 : 1)}M';
  if (v >= 1000) return '₱${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
  return '₱$v';
}

enum RevenueSource { online, pos }

/// One payment that counts toward revenue — either an online booking or a
/// counter (POS) sale — reduced to "when, how much, from where".
class RevenueEntry {
  final DateTime when;
  final int amount;
  final RevenueSource source;

  /// 'cash' | 'gcash' for POS sales; empty for online bookings (the
  /// customer pays those by uploading a receipt, so the method isn't
  /// tracked).
  final String method;

  const RevenueEntry({required this.when, required this.amount, required this.source, this.method = ''});

  /// Builds the single list every report/chart reads from, so the Total
  /// Revenue number and every chart can never disagree.
  ///
  /// Online bookings count when confirmed/completed (plus any money kept from
  /// a cancelled one), dated by when the
  /// booking was made (that's when the receipt came in). Walk-in bookings
  /// staff created (`bookedByStaff`) are left out: they're paid at the
  /// counter and already appear as their own linked POS sale, so counting
  /// both would double the money.
  static List<RevenueEntry> fromRecords(List<BookingRecord> bookings, List<PosTransactionRecord> sales) {
    final entries = <RevenueEntry>[];
    for (final b in bookings) {
      if (b.bookedByStaff) continue;
      // A cancelled booking still earns whatever the business kept (a
      // forfeited downpayment or cancellation fee); refunded money doesn't.
      if (b.status == 'cancelled') {
        if (b.retainedAmount > 0) {
          entries.add(RevenueEntry(when: b.createdAt ?? b.date, amount: b.retainedAmount, source: RevenueSource.online));
        }
        continue;
      }
      if (b.status != 'confirmed' && b.status != 'completed') continue;
      entries.add(RevenueEntry(when: b.createdAt ?? b.date, amount: b.paidAmount, source: RevenueSource.online));
    }
    for (final s in sales) {
      entries.add(RevenueEntry(when: s.createdAt, amount: s.total, source: RevenueSource.pos, method: s.paymentMethod));
    }
    return entries;
  }
}

/// One bar in a [RevenueBarChart].
class RevenueBucket {
  final String label;
  final bool showLabel;
  final int amount;
  final String tooltip;

  const RevenueBucket({required this.label, required this.showLabel, required this.amount, required this.tooltip});
}

/// Turns [RevenueEntry]s into the bars for each report period.
class RevenueBuckets {
  RevenueBuckets._();

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static String _hourShort(int h) {
    if (h == 0) return '12a';
    if (h < 12) return '${h}a';
    if (h == 12) return '12p';
    return '${h - 12}p';
  }

  /// 24 bars, one per hour of [day].
  static List<RevenueBucket> hourly(List<RevenueEntry> entries, DateTime day) {
    final sums = List<int>.filled(24, 0);
    for (final e in entries) {
      if (_sameDay(e.when, day)) sums[e.when.hour] += e.amount;
    }
    return [
      for (var h = 0; h < 24; h++)
        RevenueBucket(
          label: _hourShort(h),
          showLabel: h % 4 == 0,
          amount: sums[h],
          tooltip: '${DateFormat('h a').format(DateTime(2000, 1, 1, h))}: ${_peso(sums[h])}',
        ),
    ];
  }

  /// [count] bars, one per day starting at [firstDay].
  static List<RevenueBucket> daily(
    List<RevenueEntry> entries,
    DateTime firstDay,
    int count, {
    required String Function(DateTime day) label,
    required bool Function(int index, DateTime day) showLabel,
  }) {
    final start = DateTime.utc(firstDay.year, firstDay.month, firstDay.day);
    final sums = List<int>.filled(count, 0);
    for (final e in entries) {
      final i = DateTime.utc(e.when.year, e.when.month, e.when.day).difference(start).inDays;
      if (i >= 0 && i < count) sums[i] += e.amount;
    }
    return List.generate(count, (i) {
      final day = DateTime(firstDay.year, firstDay.month, firstDay.day + i);
      return RevenueBucket(
        label: label(day),
        showLabel: showLabel(i, day),
        amount: sums[i],
        tooltip: '${DateFormat('EEE, MMM d').format(day)}: ${_peso(sums[i])}',
      );
    });
  }

  /// One bar per month, from the earliest entry up to this month (at most
  /// the last [maxMonths]).
  static List<RevenueBucket> monthly(List<RevenueEntry> entries, {int maxMonths = 12}) {
    if (entries.isEmpty) return const [];
    final now = DateTime.now();
    final nowMonth = DateTime(now.year, now.month);
    var earliest = entries.first.when;
    for (final e in entries) {
      if (e.when.isBefore(earliest)) earliest = e.when;
    }
    var first = DateTime(earliest.year, earliest.month);
    var span = (nowMonth.year - first.year) * 12 + nowMonth.month - first.month + 1;
    if (span < 1) span = 1;
    if (span > maxMonths) {
      span = maxMonths;
      first = DateTime(nowMonth.year, nowMonth.month - (maxMonths - 1));
    }
    final sums = List<int>.filled(span, 0);
    for (final e in entries) {
      final i = (e.when.year - first.year) * 12 + e.when.month - first.month;
      if (i >= 0 && i < span) sums[i] += e.amount;
    }
    return List.generate(span, (i) {
      final m = DateTime(first.year, first.month + i);
      return RevenueBucket(
        label: DateFormat('MMM').format(m),
        showLabel: true,
        amount: sums[i],
        tooltip: '${DateFormat('MMMM y').format(m)}: ${_peso(sums[i])}',
      );
    });
  }
}

/// Simple vertical bar chart — no chart package needed. The tallest bar is
/// drawn in the full accent colour, the rest softer, and hovering/long-
/// pressing a bar shows its exact amount.
class RevenueBarChart extends StatelessWidget {
  final List<RevenueBucket> buckets;
  final double height;

  const RevenueBarChart({super.key, required this.buckets, this.height = 170});

  @override
  Widget build(BuildContext context) {
    final maxAmount = buckets.fold<int>(0, (m, b) => math.max(m, b.amount));
    if (buckets.isEmpty || maxAmount == 0) {
      return SizedBox(
        height: height,
        child: Center(child: Text("No revenue recorded in this period.", style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context)))),
      );
    }

    const labelH = 14.0;
    const valueH = 14.0;
    final barArea = height - labelH - valueH - 8;
    final dense = buckets.length > 12;
    final peakIndex = buckets.indexWhere((b) => b.amount == maxAmount);

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < buckets.length; i++)
            Expanded(
              child: Tooltip(
                message: buckets[i].tooltip,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: dense ? 1 : 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: valueH,
                        child: (!dense && buckets[i].amount > 0) || (dense && i == peakIndex)
                            ? FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _shortPeso(buckets[i].amount),
                                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppPalette.textMuted(context)),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 3),
                      Container(
                        height: buckets[i].amount == 0 ? 2.0 : math.max(3.0, buckets[i].amount / maxAmount * barArea),
                        decoration: BoxDecoration(
                          color: buckets[i].amount == 0
                              ? AppPalette.divider(context)
                              : (i == peakIndex ? AppColors.accent : AppColors.accentTint(0.5)),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                      const SizedBox(height: 5),
                      SizedBox(
                        height: labelH,
                        child: buckets[i].showLabel
                            ? OverflowBox(
                                maxWidth: 48,
                                child: Text(buckets[i].label, maxLines: 1, style: TextStyle(fontSize: 9.5, color: AppPalette.textMuted(context))),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SplitSegment {
  final String label;
  final int amount;
  final Color color;

  const SplitSegment({required this.label, required this.amount, required this.color});
}

/// A titled card with a single stacked bar plus a legend (amount and
/// percentage per segment) — used for "online vs counter" and "cash vs
/// GCash".
class RevenueSplitCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<SplitSegment> segments;

  const RevenueSplitCard({super.key, required this.title, this.subtitle, required this.segments});

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<int>(0, (s, e) => s + e.amount);
    final visible = segments.where((s) => s.amount > 0).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.divider(context).withValues(alpha: 0.5)),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: TextStyle(fontSize: 10.5, color: AppPalette.textMuted(context))),
          ],
          const SizedBox(height: 14),
          if (total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text("Nothing to show for this period.", style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    for (final s in visible) Expanded(flex: s.amount, child: Container(color: s.color)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            for (final s in segments)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(width: 9, height: 9, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s.label, style: TextStyle(fontSize: 12, color: AppPalette.textPrimary(context)))),
                    Text(_peso(s.amount), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${(s.amount / total * 100).round()}%',
                        textAlign: TextAlign.end,
                        style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// White rounded card wrapper for a chart with a title, a big total, and
/// an optional trailing widget (e.g. a "View report" button).
class RevenueChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final int total;
  final Widget chart;
  final Widget? trailing;

  const RevenueChartCard({super.key, required this.title, required this.subtitle, required this.total, required this.chart, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.divider(context).withValues(alpha: 0.5)),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 10.5, color: AppPalette.textMuted(context))),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
          Text(_peso(total), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5, color: AppColors.accent)),
          const SizedBox(height: 14),
          chart,
        ],
      ),
    );
  }
}