import 'package:flutter/material.dart';
import '../../shared/editorial_kit.dart';
import 'admin_gate.dart';

/// Admin landing page — same editorial look as the customer landing page
/// (cream canvas, hairline rules, big lowercase wordmark, black pills,
/// numbered dark / maroon sections), but framed around what the owner
/// actually does: approve bookings, manage staff and pricing, keep
/// rentals in check, and watch revenue.
///
/// Shared building blocks live in `lib/shared/editorial_kit.dart`.
class AdminWelcomeScreen extends StatefulWidget {
  const AdminWelcomeScreen({super.key});

  @override
  State<AdminWelcomeScreen> createState() => _AdminWelcomeScreenState();
}

class _AdminWelcomeScreenState extends State<AdminWelcomeScreen> {
  final GlobalKey _manageKey = GlobalKey();
  final GlobalKey _dayKey = GlobalKey();

  void _signIn() {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (context, animation, secondary) => const AdminGate(),
        transitionsBuilder: (context, animation, secondary, child) =>
            FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic), child: child),
      ),
    );
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 550), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ed.cream,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EdHeader(
                    isWide: isWide,
                    roleLabel: 'Admin',
                    links: [
                      EdNavItem('What you manage', () => _scrollTo(_manageKey)),
                      EdNavItem('Your day', () => _scrollTo(_dayKey)),
                    ],
                    onSignIn: _signIn,
                  ),
                  const EdRule(),
                  EdReveal(
                    child: EdHero(
                      isWide: isWide,
                      eyebrow: 'THE OWNER\u2019S VIEW\nOF EVERY MEMORY',
                      headline: 'RUN THE BUSINESS.\nSEE EVERY NUMBER.',
                      body: 'Approve bookings, manage your staff and pricing, track camera rentals, '
                          'and watch revenue grow \u2014 all from one place.',
                      primaryLabel: 'Sign In',
                      onPrimary: _signIn,
                      secondaryLabel: 'What you manage',
                      onSecondary: () => _scrollTo(_manageKey),
                    ),
                  ),
                  const EdRule(),
                  EdReveal(
                    child: EdShowcase(
                      isWide: isWide,
                      caption: 'OVERSEE',
                      subcaption: 'THE WHOLE BUSINESS.',
                      cardTitle: 'TODAY AT A GLANCE \u00b7 SAMPLE',
                      rows: const [
                        ('Pending approval', '3 bookings'),
                        ('Staff on shift', '4'),
                        ('Cameras out', '2 of 6'),
                      ],
                      tileLabel: 'REVENUE THIS MONTH',
                      tileValue: '\u20b1128,400',
                      tileIcon: Icons.insights_outlined,
                    ),
                  ),
                  const EdRule(),
                  Container(
                    key: _manageKey,
                    child: EdReveal(
                      child: EdNumberedList(
                        isWide: isWide,
                        label: 'WHAT YOU MANAGE',
                        title: 'EVERYTHING\nBEHIND THE BOOTH.',
                        items: const [
                          EdRowItem(Icons.event_available_outlined, 'Bookings & approvals',
                              'Review every request, approve or reject it, and handle refunds and receipts.'),
                          EdRowItem(Icons.badge_outlined, 'Staff accounts',
                              'Add staff, control their access, and see what each person has been doing.'),
                          EdRowItem(Icons.sell_outlined, 'Pricing & packages',
                              'Keep packages, add-ons and downpayment settings up to date.'),
                          EdRowItem(Icons.camera_alt_outlined, 'Camera rentals',
                              'Know which units are out, who has them, and when they are due back.'),
                          EdRowItem(Icons.bar_chart_outlined, 'Revenue & reports',
                              'Charts, POS transactions and shift close-outs in one view.'),
                        ],
                      ),
                    ),
                  ),
                  const EdRule(),
                  Container(
                    key: _dayKey,
                    child: EdReveal(
                      child: EdSteps(
                        isWide: isWide,
                        label: 'YOUR DAY',
                        title: 'THREE STOPS.\nTHEN YOU\u2019RE DONE.',
                        steps: const [
                          ('Review', 'Check new booking requests and refunds waiting for your decision.'),
                          ('Adjust', 'Update prices, packages or staff access whenever something changes.'),
                          ('Track', 'Open the charts and shift close-outs to see how the day went.'),
                        ],
                      ),
                    ),
                  ),
                  const EdRule(),
                  EdReveal(
                    child: EdCta(
                      isWide: isWide,
                      headline: 'READY TO\nRUN THE DAY?',
                      body: 'Sign in with your admin account to open the dashboard.',
                      label: 'Sign In',
                      onTap: _signIn,
                    ),
                  ),
                  EdFooter(isWide: isWide, roleLabel: 'Admin'),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
