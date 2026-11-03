import '../../shared/centered_body.dart';
import 'package:flutter/material.dart';

import '../services/booking_hours.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import 'info_pages.dart';
import '../widgets/circle_back_button.dart';

/// Profile → Help & Support.
///
/// One place for everything a customer might reach for when something
/// isn't clear: quick answers to the most common problems, the full FAQ,
/// the policies, and a direct line to staff through the in-app Messages
/// thread (the same one the Staff and Admin apps reply from).
class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Quick answers for the problems people actually hit. The long form
  /// lives in the FAQ; these are the one-paragraph versions.
  static const List<FaqEntry> _quick = [
    FaqEntry(
      'My slot expired before I paid',
      'Slots are held for 15 minutes while you check out. If the timer ran out, the date is released — just pick it again and start over. If someone else booked it meanwhile, choose another date.',
    ),
    FaqEntry(
      'I sent my GCash payment but nothing happened',
      'Upload the receipt screenshot before the hold ends. Staff review it manually, so approval is not instant. You will get a notification when it is approved. If it has been a while, message us with your invoice number.',
    ),
    FaqEntry(
      'Where is my ticket / QR code?',
      'Open Profile → Tickets. A pass becomes active once staff approve your booking. Show the QR code (or your invoice number) when you arrive.',
    ),
    FaqEntry(
      'How do I get a refund?',
      'Refunds are sent manually to your GCash. Save your GCash number under Profile → Payment Methods so we know where to send it, then message us if you need to cancel.',
    ),
    FaqEntry(
      'I want to change my date or package',
      'Message our team with your invoice number and the change you want. Changes depend on availability and our cancellation policy.',
    ),
  ];

  bool _matches(FaqEntry e) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return e.question.toLowerCase().contains(q) || e.answer.toLowerCase().contains(q);
  }

  void _openMessages() {
    final nav = Navigator.of(context);
    nav.pop(); // leave Help & Support
    nav.pushReplacementNamed('/messages'); // swap the Profile tab for Messages
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.trim().isNotEmpty;
    final quick = _quick.where(_matches).toList();
    final faq = kFaqEntries.where(_matches).toList();

    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        leading: const CircleBackButton.appBar(),
        leadingWidth: CircleBackButton.appBarLeadingWidth,
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: Text('Help & Support', style: TextStyle(color: AppPalette.textPrimary(context), fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      body: CenteredBody(child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Search
            TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search help (e.g. refund, receipt, ticket)',
                hintStyle: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
                prefixIcon: Icon(Icons.search, size: 20, color: AppPalette.textMuted(context)),
                suffixIcon: searching
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      )
                    : null,
                filled: true,
                fillColor: AppPalette.surface(context),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),

            if (!searching) ...[
              _contactCard(context),
              const SizedBox(height: 22),
            ],

            if (quick.isNotEmpty) ...[
              _sectionLabel(context, searching ? 'QUICK ANSWERS' : 'COMMON PROBLEMS'),
              _group(context, [for (final e in quick) _Qa(entry: e)]),
              const SizedBox(height: 22),
            ],

            if (searching && faq.isNotEmpty) ...[
              _sectionLabel(context, 'FROM THE FAQ'),
              _group(context, [for (final e in faq) _Qa(entry: e)]),
              const SizedBox(height: 22),
            ],

            if (searching && quick.isEmpty && faq.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(Icons.search_off, size: 38, color: AppPalette.textMuted(context)),
                    const SizedBox(height: 10),
                    Text('No answers found', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                    const SizedBox(height: 6),
                    Text('Try another word, or message our team.',
                        style: TextStyle(fontSize: 13, color: AppPalette.textSecondary(context))),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _openMessages,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      child: const Text('Message our team'),
                    ),
                  ],
                ),
              ),

            if (!searching) ...[
              _sectionLabel(context, 'MORE'),
              _group(context, [
                _linkRow(context, Icons.quiz_outlined, 'All FAQs', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FaqScreen()))),
                _linkRow(
                  context,
                  Icons.event_busy_outlined,
                  'Cancellation Policy',
                  () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const PolicyScreen(title: 'Cancellation Policy', sections: kCancellationPolicySections))),
                ),
                _linkRow(
                  context,
                  Icons.description_outlined,
                  'Terms of Service',
                  () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const PolicyScreen(title: 'Terms of Service', sections: kTermsOfServiceSections))),
                ),
                _linkRow(
                  context,
                  Icons.privacy_tip_outlined,
                  'Privacy Policy',
                  () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const PolicyScreen(title: 'Privacy Policy', sections: kPrivacyPolicySections, lastUpdated: kPrivacyPolicyLastUpdated))),
                  last: true,
                ),
              ]),
              const SizedBox(height: 22),
              Center(
                child: Text(
                  'Memoriae · Calauan, Laguna\nBookings open from ${_hourLabel(BookingHours.reopensAtHour)} each day.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, height: 1.6, color: AppPalette.textMuted(context)),
                ),
              ),
            ],
          ],
        ),
      )),
    );
  }

  static String _hourLabel(int h) {
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:00 ${h < 12 ? 'AM' : 'PM'}';
  }

  Widget _contactCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Need a hand?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.brandCream, letterSpacing: -0.4)),
          const SizedBox(height: 6),
          Text(
            'Send our team a message and we will reply right in the app. Include your invoice number if it is about a booking.',
            style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.brandCream.withValues(alpha: 0.82)),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _openMessages,
            icon: const Icon(Icons.chat_bubble_outline, size: 16),
            label: const Text('Message our team', style: TextStyle(fontWeight: FontWeight.bold)),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandCream,
              foregroundColor: AppColors.stone900,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: AppPalette.textMuted(context))),
    );
  }

  Widget _group(BuildContext context, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _linkRow(BuildContext context, IconData icon, String label, VoidCallback onTap, {bool last = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: AppPalette.divider(context)))),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context)))),
              Icon(Icons.chevron_right, size: 18, color: AppPalette.textMuted(context)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Expandable question/answer row (own tile so it works inside the
/// grouped surface without the FAQ screen's card styling).
class _Qa extends StatelessWidget {
  const _Qa({required this.entry});
  final FaqEntry entry;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedAlignment: Alignment.centerLeft,
        iconColor: AppColors.accent,
        collapsedIconColor: AppPalette.textMuted(context),
        title: Text(entry.question, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
        children: [
          Text(entry.answer, style: TextStyle(fontSize: 12.5, height: 1.6, color: AppPalette.textSecondary(context))),
        ],
      ),
    );
  }
}