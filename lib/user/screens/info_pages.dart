import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/circle_back_button.dart';

/// Reusable chrome for a simple, scrollable informational page — a plain
/// AppBar with a back button plus whatever content is passed in. Used by
/// the FAQ, Cancellation Policy, and Terms of Service screens rather than
/// giving each one its own Scaffold boilerplate.
class InfoPageScreen extends StatelessWidget {
  const InfoPageScreen({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        leading: const CircleBackButton.appBar(),
        leadingWidth: CircleBackButton.appBarLeadingWidth,
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: Text(title, style: TextStyle(color: AppPalette.textPrimary(context), fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
    );
  }
}

/// One question/answer pair, rendered as an expandable tile.
class FaqEntry {
  final String question;
  final String answer;
  const FaqEntry(this.question, this.answer);
}

const List<FaqEntry> kFaqEntries = [
  FaqEntry(
    "How do I book a session?",
    "Pick a date and package on the Book tab. The moment you start checkout, that date is held for you for 15 minutes while you finish — nobody else can take it during that window.",
  ),
  FaqEntry(
    "How long is my date actually held for me?",
    "15 minutes from when you begin checkout. You'll see a live countdown at the top of the booking screen. If payment isn't submitted before it runs out, the hold is released and the date opens back up to other customers.",
  ),
  FaqEntry(
    "What payment methods do you accept?",
    "GCash. After choosing your package, you can reserve your date with a downpayment (the remaining balance is paid on the event day) or pay in full. Send the payment and upload a screenshot of your receipt as proof — that's what turns your hold into an actual booking request.",
  ),
  FaqEntry(
    "What happens after I submit my receipt?",
    "Staff reviews it and either confirms or rejects your booking. You can track the status any time from My Bookings, and you'll be notified of the outcome.",
  ),
  FaqEntry(
    "Can I change my date or package after starting checkout?",
    "Yes — as long as your 15-minute hold is still active, you can change the date, package, or add-ons freely without losing your spot or restarting the countdown. Once a booking is confirmed, message us if you need to make a change.",
  ),
  FaqEntry(
    "Do you rent out cameras separately from booth packages?",
    "Yes — check the Rent tab for available equipment and rental terms.",
  ),
  FaqEntry(
    "How do I leave a review?",
    "Once your booking is marked completed, a \"Leave a Review\" option appears on it in My Bookings.",
  ),
  FaqEntry(
    "I have a question that's not answered here.",
    "Message us directly from the Contact link below or the Messages tab — a real staff member will get back to you there.",
  ),
];

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return InfoPageScreen(
      title: "FAQs",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in kFaqEntries) _FaqTile(entry: entry),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.entry});
  final FaqEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.divider(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(entry.question, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
          iconColor: AppColors.accent,
          collapsedIconColor: AppPalette.textMuted(context),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.answer, style: TextStyle(fontSize: 12.5, height: 1.55, color: AppPalette.textSecondary(context))),
          ],
        ),
      ),
    );
  }
}

/// One heading + body block within a policy page.
class PolicySection {
  final String heading;
  final String body;
  const PolicySection(this.heading, this.body);
}

/// STARTER DRAFT — written to match how this app's booking flow actually
/// works (the 15-minute hold, GCash + manual receipt review, no in-app
/// refunds), but every bracketed [placeholder] needs filling in with the
/// business's real numbers before this goes live. Not legal advice.
const List<PolicySection> kCancellationPolicySections = [
  PolicySection(
    "Before payment (still just a hold)",
    "If you start checkout but don't submit a payment receipt, your date is only held for 15 minutes. Letting the countdown run out costs nothing — the date is simply released. There is nothing to cancel at this stage.",
  ),
  PolicySection(
    "After you've submitted a receipt, before staff confirms",
    "Message us right away if you need to withdraw a request that's still awaiting approval. Since payment was made directly via GCash rather than through the app, any refund at this stage is handled manually — reach out as soon as possible.",
  ),
  PolicySection(
    "After your booking is confirmed",
    "Cancellations made at least [X] days before your event date are eligible for a [full / partial] refund. Cancellations made within [X] days of the event are [non-refundable / subject to a cancellation fee of ₱X]. To cancel a confirmed booking, message us with your booking reference.",
  ),
  PolicySection(
    "No-shows",
    "If the booth team arrives for a confirmed booking and the event is not accessible or is cancelled without notice, no refund will be issued.",
  ),
  PolicySection(
    "Rescheduling",
    "Need a different date instead of cancelling entirely? Message us — we're generally able to move a confirmed booking to another available date at no extra cost, subject to availability.",
  ),
];

/// STARTER DRAFT — generic boilerplate sections. This is not legal advice;
/// have this reviewed (ideally by a lawyer) before treating it as your
/// actual binding Terms of Service.
const List<PolicySection> kTermsOfServiceSections = [
  PolicySection(
    "Acceptance of terms",
    "By booking a session or rental through this app, you agree to these terms. If you don't agree with any part of them, please don't proceed with a booking and contact us with your questions instead.",
  ),
  PolicySection(
    "Bookings and payment",
    "A booking request is only confirmed once staff has reviewed and approved your submitted payment receipt. Submitting a receipt is not itself a confirmation — check My Bookings for the current status of your request.",
  ),
  PolicySection(
    "Use of photos",
    "Photos and videos captured during your session may be used for [business name]'s marketing and portfolio purposes (e.g. social media, website) unless you opt out in writing before your event. Your personal booking details (name, contact info) are never shared publicly.",
  ),
  PolicySection(
    "Liability",
    "[Business name] is not liable for delays, technical issues, or circumstances outside of our reasonable control that affect a session. Our maximum liability for any booking is limited to the amount paid for that booking.",
  ),
  PolicySection(
    "Equipment rentals",
    "Rented equipment remains the property of [business name] at all times. The renter is responsible for its condition and timely return; damage or late return may incur additional charges as described at the time of rental.",
  ),
  PolicySection(
    "Changes to these terms",
    "These terms may be updated from time to time. Continued use of the app after changes are posted means you accept the updated terms.",
  ),
  PolicySection(
    "Contact",
    "Questions about these terms? Reach us through the Contact link or the Messages tab in the app.",
  ),
];

/// Bump this whenever the Terms, Cancellation Policy or Privacy Policy
/// change in a way customers should re-accept. It's saved on each account
/// at registration (`termsVersion`) next to the time they agreed
/// (`agreedToTermsAt`), so there's a record of exactly what they accepted.
const String kPoliciesVersion = '2026-10-06';

/// Shown as "Last updated" on the Privacy Policy page.
const String kPrivacyPolicyLastUpdated = 'October 6, 2026';

/// STARTER DRAFT — written from what this app actually collects and which
/// services it uses (Firebase, Google Maps, EmailJS, Google Gemini), and
/// based on the Data Privacy Act of 2012 (RA 10173). Every [bracketed]
/// placeholder must be filled in, the retention period and contact email
/// must be real, and it should be reviewed by a lawyer before going live.
/// Not legal advice.
const List<PolicySection> kPrivacyPolicySections = [
  PolicySection(
    "Who we are",
    "Memoriae Photobooth ([registered business name], Calauan, Laguna) runs this app. This policy explains what personal information we collect, why we collect it, who can see it, and what your rights are under the Data Privacy Act of 2012 (Republic Act No. 10173).",
  ),
  PolicySection(
    "What we collect",
    "• Account details: your name, email address, contact number and birthdate. Your password is handled by Firebase Authentication — we can't see it.\n"
    "• Optional preferences: preferred payment method, contact preferences, billing address and special-assistance notes, only if you fill them in.\n"
    "• Bookings: the package, date, time, number of guests, event location (including map coordinates) and the payment receipt screenshot you upload.\n"
    "• Refunds: the GCash name and number, only if you save them under Profile → Payment Methods.\n"
    "• Rentals: which equipment you rented and when, plus any late or damage fees.\n"
    "• Messages and reviews you send us, and the questions you type into the chatbot.\n"
    "• Your phone's notification token, so we can send booking updates.",
  ),
  PolicySection(
    "Why we use it",
    "To process and confirm your bookings, check your payments, send refunds, contact you about your booking, send booking updates and announcements, prevent fraud and abuse (for example, blocking an account), and keep records for accounting. We only use your information for these purposes.",
  ),
  PolicySection(
    "Who can see it",
    "Memoriae staff and admins can see your account details, bookings, receipts and messages so they can do their work. Other customers can't see your personal information — they only see that a date or a camera is unavailable. If you leave a review, it may be shown in the app with your name, the package and your rating.",
  ),
  PolicySection(
    "Services we use",
    "We use Google Firebase (login, database and notifications), Google Maps (the event-location picker), EmailJS (to email your verification code) and, when it is turned on, Google Gemini (to answer chatbot questions). Only your recent chat messages and our public prices and hours are sent to Gemini — not your name, email or bookings — so please don't type sensitive details into the chatbot. These providers handle data on our behalf. We don't sell your personal information.",
  ),
  PolicySection(
    "How long we keep it",
    "[Booking and payment records are kept for [X years] for accounting and dispute purposes. Other information is kept while your account is active.] You can ask us to delete your account and any information we're not required to keep.",
  ),
  PolicySection(
    "How we protect it",
    "We use reasonable organizational and technical measures to protect your information, such as password-protected staff and admin accounts. No system is completely secure, so we can't guarantee absolute security.",
  ),
  PolicySection(
    "Your rights",
    "Under the Data Privacy Act you have the right to be informed about how your data is used, to access a copy of it, to correct it, to object to its use, to ask for it to be deleted or blocked, to be compensated for damages caused by misuse, and to receive your data in a usable format. If you believe your rights were violated, you may also file a complaint with the National Privacy Commission (privacy.gov.ph). To make a request, message us in the app or email [privacy contact email].",
  ),
  PolicySection(
    "Age",
    "This app is for people aged 18 and over.",
  ),
  PolicySection(
    "Changes to this policy",
    "We may update this policy from time to time. The \"Last updated\" date above shows the latest version.",
  ),
  PolicySection(
    "Contact",
    "Questions about your privacy? Message us in the app or email [privacy contact email].",
  ),
];

class PolicyScreen extends StatelessWidget {
  const PolicyScreen({super.key, required this.title, required this.sections, this.lastUpdated});

  final String title;
  final List<PolicySection> sections;
  final String? lastUpdated;

  @override
  Widget build(BuildContext context) {
    return InfoPageScreen(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lastUpdated != null) ...[
            Text("Last updated: $lastUpdated", style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
            const SizedBox(height: 16),
          ],
          for (final section in sections) ...[
            Text(section.heading, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
            const SizedBox(height: 6),
            Text(section.body, style: TextStyle(fontSize: 12.5, height: 1.6, color: AppPalette.textSecondary(context))),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}