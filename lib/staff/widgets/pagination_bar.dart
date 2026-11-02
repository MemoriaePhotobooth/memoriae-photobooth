import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// A small "Page 2 of 5" bar with Prev/Next buttons, meant to sit under a
/// non-scrolling slice of a longer list. Always shown — even with a single
/// page it reads "Page 1 of 1" with both arrows greyed out — so the
/// pagination is visible before the list fills up. Purely a display + tap-callback
/// widget — whoever uses this owns the actual paging (see [PageWindow]).
class PaginationBar extends StatelessWidget {
  final int page; // 0-based
  final int pageCount;
  final ValueChanged<int> onPageChanged;

  const PaginationBar({super.key, required this.page, required this.pageCount, required this.onPageChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: page > 0 ? () => onPageChanged(page - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
            color: AppColors.accent,
          ),
          Text(
            'Page ${page + 1} of $pageCount',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppPalette.textMuted(context)),
          ),
          IconButton(
            onPressed: page < pageCount - 1 ? () => onPageChanged(page + 1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
            color: AppColors.accent,
          ),
        ],
      ),
    );
  }
}

/// Slices [items] into pages of [pageSize] and clamps [page] back into
/// range whenever the underlying list shrinks (e.g. a booking gets
/// deleted while sitting on the last page) — call [clamp] with the
/// latest length before reading [pageCount]/[slice].
class PageWindow {
  static const int defaultPageSize = 15;

  static int pageCount(int itemCount, {int pageSize = defaultPageSize}) =>
      itemCount == 0 ? 1 : ((itemCount - 1) ~/ pageSize) + 1;

  static int clamp(int page, int itemCount, {int pageSize = defaultPageSize}) {
    final maxPage = pageCount(itemCount, pageSize: pageSize) - 1;
    if (page < 0) return 0;
    if (page > maxPage) return maxPage;
    return page;
  }

  static List<T> slice<T>(List<T> items, int page, {int pageSize = defaultPageSize}) {
    final start = page * pageSize;
    if (start >= items.length) return const [];
    final end = (start + pageSize).clamp(0, items.length);
    return items.sublist(start, end);
  }
}