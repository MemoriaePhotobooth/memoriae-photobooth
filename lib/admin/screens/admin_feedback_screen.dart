import '../../shared/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/feedback_record.dart';
import '../services/feedback_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/pagination_bar.dart';

/// List of customer feedback left after their booking. Admin can remove
/// a review (e.g. spam or inappropriate content).
class AdminFeedbackScreen extends StatefulWidget {
  const AdminFeedbackScreen({super.key});

  @override
  State<AdminFeedbackScreen> createState() => _AdminFeedbackScreenState();
}

class _AdminFeedbackScreenState extends State<AdminFeedbackScreen> {
  // Star-rating filter + date sort for the feedback list.
  String _ratingFilter = 'all';
  bool _newestFirst = true;
  int _page = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<FeedbackRecord> _applyFilters(List<FeedbackRecord> feedback) {
    final q = _searchQuery.trim().toLowerCase();
    final list = (_ratingFilter == 'all'
            ? feedback
            : feedback.where((f) => f.rating == int.parse(_ratingFilter)).toList())
        .where((f) =>
            q.isEmpty ||
            f.customerName.toLowerCase().contains(q) ||
            f.comment.toLowerCase().contains(q) ||
            f.packageName.toLowerCase().contains(q))
        .toList();
    list.sort((a, b) {
      final cmp = a.createdAt.compareTo(b.createdAt);
      return _newestFirst ? -cmp : cmp;
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FeedbackRecord>>(
      stream: FeedbackRepository.watchAllFeedback(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accent));
        }
        final feedback = snapshot.data!;
        if (feedback.isEmpty) {
          return Center(child: Text("No feedback yet.", style: TextStyle(color: AppPalette.textMuted(context))));
        }

        final avg = feedback.map((f) => f.rating).reduce((a, b) => a + b) / feedback.length;
        final filtered = _applyFilters(feedback);
        _page = PageWindow.clamp(_page, filtered.length);
        final pageItems = PageWindow.slice(filtered, _page);

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _summaryCard(context, feedback, avg),
            const SizedBox(height: 16),
            _FeedbackFilterBar(
              allFeedback: feedback,
              searchController: _searchController,
              onSearchChanged: (q) => setState(() {
                _searchQuery = q;
                _page = 0;
              }),
              ratingFilter: _ratingFilter,
              onRatingChanged: (r) => setState(() {
                _ratingFilter = r;
                _page = 0;
              }),
              newestFirst: _newestFirst,
              onToggleSort: () => setState(() => _newestFirst = !_newestFirst),
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text("No reviews match this filter.", style: TextStyle(color: AppPalette.textMuted(context))),
                ),
              )
            else ...[
              ...pageItems.map((f) => _feedbackCard(context, f)),
              PaginationBar(
                page: _page,
                pageCount: PageWindow.pageCount(filtered.length),
                onPageChanged: (p) => setState(() => _page = p),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _summaryCard(BuildContext context, List<FeedbackRecord> feedback, double avg) {
    final counts = {for (var r = 5; r >= 1; r--) r: feedback.where((f) => f.rating == r).length};
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.divider(context)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            children: [
              Text(avg.toStringAsFixed(1), style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: AppColors.accent)),
              const SizedBox(height: 2),
              _stars(avg.round(), size: 14),
              const SizedBox(height: 4),
              Text('${feedback.length} review${feedback.length == 1 ? '' : 's'}', style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final r in const [5, 4, 3, 2, 1])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Text('$r', style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
                        const SizedBox(width: 4),
                        const Icon(Icons.star_rounded, size: 12, color: Color(0xFFF2A600)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: feedback.isEmpty ? 0 : (counts[r] ?? 0) / feedback.length,
                              minHeight: 6,
                              backgroundColor: AppPalette.divider(context),
                              valueColor: const AlwaysStoppedAnimation(Color(0xFFF2A600)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 18,
                          child: Text('${counts[r] ?? 0}', style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stars(int rating, {double size = 16}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) => Icon(
            i < rating ? Icons.star_rounded : Icons.star_border_rounded,
            size: size,
            color: const Color(0xFFF2A600),
          )),
    );
  }

  Widget _pill(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppPalette.divider(context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: AppPalette.textMuted(context)),
      ),
    );
  }

  Widget _feedbackCard(BuildContext context, FeedbackRecord f) {
    final muted = AppPalette.textMuted(context);
    final primary = AppPalette.textPrimary(context);
    final initial = f.customerName.trim().isNotEmpty ? f.customerName.trim()[0].toUpperCase() : '?';

    return Opacity(
      opacity: f.hidden ? 0.6 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(18, 16, 16, 12),
        decoration: BoxDecoration(
          color: AppPalette.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppPalette.divider(context)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: avatar, name + package, stars and date.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.accent, AppColors.accent.withValues(alpha: 0.65)],
                    ),
                  ),
                  child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              f.customerName,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: primary),
                            ),
                          ),
                          if (f.hidden) ...[const SizedBox(width: 8), _pill(context, 'HIDDEN')],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.photo_camera_outlined, size: 12, color: muted),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              f.packageName,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: muted),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _stars(f.rating, size: 14),
                    const SizedBox(height: 4),
                    Text(DateFormat('MMM d, yyyy').format(f.createdAt), style: TextStyle(fontSize: 10.5, color: muted)),
                  ],
                ),
              ],
            ),

            // Comment, shown as a quote.
            if (f.comment.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: AppPalette.surface(context),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.format_quote_rounded, size: 20, color: AppColors.accent.withValues(alpha: 0.5)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        f.comment,
                        style: TextStyle(fontSize: 13, height: 1.45, color: AppPalette.textSecondary(context)),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Admin reply, if any.
            if (f.adminReply.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                decoration: BoxDecoration(
                  color: AppColors.accentTint(0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border(left: BorderSide(color: AppColors.accent.withValues(alpha: 0.6), width: 3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.reply_rounded, size: 16, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.adminReplyAt == null
                                ? 'Your reply'
                                : 'Your reply · ${DateFormat('MMM d, yyyy').format(f.adminReplyAt!)}',
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.accent),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            f.adminReply,
                            style: TextStyle(fontSize: 12.5, height: 1.4, color: AppPalette.textPrimary(context)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Edit reply',
                      icon: Icon(Icons.edit_outlined, size: 16, color: muted),
                      onPressed: () => _replyDialog(context, f),
                    ),
                  ],
                ),
              ),
            ],

            // Actions, grouped at the bottom.
            const SizedBox(height: 6),
            Row(
              children: [
                if (f.adminReply.isEmpty)
                  TextButton.icon(
                    onPressed: () => _replyDialog(context, f),
                    style: TextButton.styleFrom(foregroundColor: AppColors.accent, padding: const EdgeInsets.symmetric(horizontal: 8)),
                    icon: const Icon(Icons.reply_rounded, size: 16),
                    label: const Text('Reply', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _toggleHidden(context, f),
                  style: TextButton.styleFrom(foregroundColor: muted, padding: const EdgeInsets.symmetric(horizontal: 8)),
                  icon: Icon(f.hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 16),
                  label: Text(f.hidden ? 'Show' : 'Hide', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Remove review',
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                  onPressed: () => _confirmDelete(context, f),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleHidden(BuildContext context, FeedbackRecord f) async {
    final hide = !f.hidden;
    try {
      await FeedbackRepository.setHidden(f.id, hide);
      TopToast.show(null, hide ? 'Review hidden from customers.' : 'Review is visible again.');
    } catch (_) {
      TopToast.show(null, "Couldn't update the review. Check your connection and admin permissions.", kind: TopToastKind.error);
    }
  }

  void _replyDialog(BuildContext context, FeedbackRecord f) {
    final controller = TextEditingController(text: f.adminReply);
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Reply to ${f.customerName}'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 5,
            minLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(hintText: 'Thank them, or address their concern…', border: OutlineInputBorder()),
          ),
          actions: [
            if (f.adminReply.isNotEmpty)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                onPressed: () {
                  FeedbackRepository.setReply(f.id, '');
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Remove reply'),
              ),
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white),
              onPressed: () {
                if (controller.text.trim().isEmpty) return;
                FeedbackRepository.setReply(f.id, controller.text);
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Save reply'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, FeedbackRecord f) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove feedback?'),
          content: Text('This will remove the review from "${f.customerName}".'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              onPressed: () {
                FeedbackRepository.deleteFeedback(f.id);
                Navigator.of(context).pop();
              },
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
  }
}

/// Star-rating filter chips (with live counts) + a newest/oldest sort
/// toggle for the feedback list.
class _FeedbackFilterBar extends StatelessWidget {
  final List<FeedbackRecord> allFeedback;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String ratingFilter;
  final ValueChanged<String> onRatingChanged;
  final bool newestFirst;
  final VoidCallback onToggleSort;

  const _FeedbackFilterBar({
    required this.allFeedback,
    required this.searchController,
    required this.onSearchChanged,
    required this.ratingFilter,
    required this.onRatingChanged,
    required this.newestFirst,
    required this.onToggleSort,
  });

  static const _ratings = [
    ('all', 'All'),
    ('5', '5★'),
    ('4', '4★'),
    ('3', '3★'),
    ('2', '2★'),
    ('1', '1★'),
  ];

  int _countFor(String value) {
    if (value == 'all') return allFeedback.length;
    return allFeedback.where((f) => f.rating == int.parse(value)).length;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: searchController,
          onChanged: onSearchChanged,
          style: TextStyle(fontSize: 13, color: AppPalette.textPrimary(context)),
          decoration: InputDecoration(
            isDense: true,
            hintText: "Search by customer or comment",
            hintStyle: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
            prefixIcon: Icon(Icons.search, size: 18, color: AppPalette.textMuted(context)),
            suffixIcon: searchController.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      searchController.clear();
                      onSearchChanged('');
                    },
                  ),
            filled: true,
            fillColor: AppPalette.surface(context),
            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 10),
        Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _ratings.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final (value, label) = _ratings[i];
                final selected = ratingFilter == value;
                final count = _countFor(value);
                return ChoiceChip(
                  label: Text(count == 0 ? label : '$label ($count)'),
                  selected: selected,
                  onSelected: (_) => onRatingChanged(value),
                  labelStyle: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppPalette.textPrimary(context),
                  ),
                  selectedColor: AppColors.accent,
                  backgroundColor: AppPalette.surface(context),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999), side: BorderSide.none),
                  showCheckmark: false,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 10),
        Tooltip(
          message: newestFirst ? "Newest first" : "Oldest first",
          child: OutlinedButton.icon(
            onPressed: onToggleSort,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppPalette.textPrimary(context),
              side: BorderSide(color: AppPalette.divider(context)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: Icon(newestFirst ? Icons.arrow_downward : Icons.arrow_upward, size: 15),
            label: const Text("Date", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
        ),
      ],
    );
  }
}