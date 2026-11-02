import 'package:flutter/material.dart';
import '../../shared/editorial_kit.dart';
import 'staff_gate.dart';

/// Staff landing page — same editorial look as the customer landing page
/// (cream canvas, hairline rules, big lowercase wordmark, black pills,
/// numbered dark / maroon sections), but framed around the day-to-day of
/// a shift: walk-in bookings, point of sale, rentals, calendar, messages
/// and closing out the shift.
///
/// Shared building blocks live in `lib/shared/editorial_kit.dart`.
class StaffLandingScreen extends StatefulWidget {
  const StaffLandingScreen({super.key});

  @override
  State<StaffLandingScreen> createState() => _StaffLandingScreenState();
}

class _StaffLandingScreenState extends State<StaffLandingScreen> {
  final GlobalKey _toolsKey = GlobalKey();
  final GlobalKey _shiftKey = GlobalKey();

  void _login() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StaffGate()));
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
                    roleLabel: 'Staff',
                    links: [
                      EdNavItem('Your tools', () => _scrollTo(_toolsKey)),
                      EdNavItem('Your shift', () => _scrollTo(_shiftKey)),
                    ],
                    onSignIn: _login,
                  ),
                  const EdRule(),
                  EdReveal(
                    child: EdHero(
                      isWide: isWide,
                      eyebrow: 'BEHIND EVERY\nGREAT BOOKING',
                      headline: 'SERVE THE MOMENT.\nCLOSE THE DAY.',
                      body: 'Walk-in bookings, point of sale, camera rentals and messages \u2014 '
                          'everything you need for today\u2019s shift in one place.',
                      primaryLabel: 'Sign In',
                      onPrimary: _login,
                      secondaryLabel: 'See your tools',
                      onSecondary: () => _scrollTo(_toolsKey),
                    ),
                  ),
                  const EdRule(),
                  EdReveal(
                    child: EdShowcase(
                      isWide: isWide,
                      caption: 'SERVE',
                      subcaption: 'EVERY GUEST.',
                      cardTitle: 'TODAY\u2019S QUEUE \u00b7 SAMPLE',
                      rows: const [
                        ('Bookings today', '5'),
                        ('Walk-ins', '2'),
                        ('Rentals due back', '1'),
                      ],
                      tileLabel: 'TAP TO START',
                      tileValue: 'New walk-in',
                      tileIcon: Icons.point_of_sale_outlined,
                    ),
                  ),
                  const EdRule(),
                  Container(
                    key: _toolsKey,
                    child: EdReveal(
                      child: EdNumberedList(
                        isWide: isWide,
                        label: 'YOUR TOOLS',
                        title: 'EVERYTHING\nFOR THE SHIFT.',
                        items: const [
                          EdRowItem(Icons.event_note_outlined, 'Bookings & walk-ins',
                              'See today\u2019s bookings and book a walk-in guest on the spot.'),
                          EdRowItem(Icons.point_of_sale_outlined, 'Point of sale',
                              'Ring up add-ons and rentals and take payment at the booth.'),
                          EdRowItem(Icons.camera_alt_outlined, 'Camera rentals',
                              'Check units out and in, and keep track of what is due back.'),
                          EdRowItem(Icons.calendar_month_outlined, 'Calendar',
                              'Know which events are coming up before they arrive.'),
                          EdRowItem(Icons.chat_bubble_outline, 'Messages & announcements',
                              'Reply to customers and stay in the loop on team news.'),
                        ],
                      ),
                    ),
                  ),
                  const EdRule(),
                  Container(
                    key: _shiftKey,
                    child: EdReveal(
                      child: EdSteps(
                        isWide: isWide,
                        label: 'YOUR SHIFT',
                        title: 'OPEN. SERVE.\nCLOSE.',
                        steps: const [
                          ('Open', 'Sign in, read the announcements and check today\u2019s bookings.'),
                          ('Serve', 'Handle walk-ins, sales, rentals and customer messages.'),
                          ('Close', 'Do your shift close-out so the numbers match at the end of the day.'),
                        ],
                      ),
                    ),
                  ),
                  const EdRule(),
                  EdReveal(
                    child: EdCta(
                      isWide: isWide,
                      headline: 'READY TO\nSTART YOUR SHIFT?',
                      body: 'Sign in with your staff account to open the dashboard.',
                      label: 'Sign In',
                      onTap: _login,
                    ),
                  ),
                  EdFooter(isWide: isWide, roleLabel: 'Staff'),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
