import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/feedback_record.dart';
import '../services/feedback_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/pagination_bar.dart';

/// Read-only list of customer feedback left after their booking. Shows
/// which reviews an admin has hidden from customers and any reply the
/// admin wrote; moderating and replying stay on the Admin side.
class StaffFeedbackScreen extends StatefulWidget {
  const StaffFeedbackScreen({super.key});

  @override
  State<StaffFeedbackScreen> createState() => _StaffFeedbackScreenState();
}

class _StaffFeedbackScreenState extends State<StaffFeedbackScreen> {
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(18)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            children: [
              Text(avg.toStringAsFixed(1), style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
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

  Widget _feedbackCard(BuildContext context, FeedbackRecord f) {
    return Opacity(
      opacity: f.hidden ? 0.65 : 1,
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.divider(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.accentTint(0.12),
                child: Text(
                  f.customerName.isNotEmpty ? f.customerName[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(f.customerName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                        ),
                        if (f.hidden) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Hidden from customers by an admin',
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: AppPalette.divider(context), borderRadius: BorderRadius.circular(999)),
                              child: Text('Hidden', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppPalette.textMuted(context))),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(f.packageName, style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _stars(f.rating, size: 13),
                  const SizedBox(height: 3),
                  Text(DateFormat('MMM d, yyyy').format(f.createdAt), style: TextStyle(fontSize: 10, color: AppPalette.textMuted(context))),
                ],
              ),
            ],
          ),
          if (f.comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppPalette.surface(context),
                borderRadius: BorderRadius.circular(10),
                border: const Border(left: BorderSide(color: AppColors.accent, width: 3)),
              ),
              child: Text(
                f.comment,
                style: TextStyle(fontSize: 13, color: AppPalette.textSecondary(context), fontStyle: FontStyle.italic, height: 1.4),
              ),
            ),
          ],
          if (f.adminReply.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: AppColors.accentTint(0.08),
                borderRadius: BorderRadius.circular(10),
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
                          f.adminReplyAt == null ? 'Admin reply' : 'Admin reply · ${DateFormat('MMM d, yyyy').format(f.adminReplyAt!)}',
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppColors.accent),
                        ),
                        const SizedBox(height: 3),
                        Text(f.adminReply, style: TextStyle(fontSize: 12.5, height: 1.4, color: AppPalette.textPrimary(context))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
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