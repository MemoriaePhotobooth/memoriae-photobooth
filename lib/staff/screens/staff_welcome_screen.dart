import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'staff_gate.dart';

/// Landing page shown before sign-in. Same editorial template as the User
/// app's welcome screen — huge bold headline, ghost watermark word, gold
/// pitch card, floating status card, numbered process section, closing
/// CTA band — restyled with staff-relevant copy. Built with our own
/// maroon/gold/cream palette and Roboto type throughout.
class StaffWelcomeScreen extends StatefulWidget {
  const StaffWelcomeScreen({super.key});

  @override
  State<StaffWelcomeScreen> createState() => _StaffWelcomeScreenState();
}

class _StaffWelcomeScreenState extends State<StaffWelcomeScreen> {
  final GlobalKey _howItWorksKey = GlobalKey();

  void _signIn() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const StaffGate()));
  }

  void _scrollToHowItWorks() {
    final ctx = _howItWorksKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceGrey,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NavBar(isWide: isWide, onHowItWorks: _scrollToHowItWorks, onSignIn: _signIn),
                  _Hero(isWide: isWide, onSignIn: _signIn, onHowItWorks: _scrollToHowItWorks),
                  Container(key: _howItWorksKey, child: _ProcessSection(isWide: isWide)),
                  _ClosingBand(onSignIn: _signIn),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.isWide, required this.onHowItWorks, required this.onSignIn});

  final bool isWide;
  final VoidCallback onHowItWorks;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isWide ? 48 : 20, vertical: 20),
      child: Row(
        children: [
          const Text(
            'memoriae',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: -0.3, color: AppColors.stone900),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
            child: const Text(
              'STAFF',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accent, letterSpacing: 0.6),
            ),
          ),
          const Spacer(),
          if (isWide) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
              child: Row(
                children: [
                  _NavItem('Bookings', onSignIn),
                  const SizedBox(width: 8),
                  _NavItem('Rentals', onSignIn),
                  const SizedBox(width: 8),
                  _NavItem('How it works', onHowItWorks),
                ],
              ),
            ),
            const SizedBox(width: 16),
          ],
          _PillButton(label: 'Sign In', onTap: onSignIn, dark: true, dense: true),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.stone500)),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.isWide, required this.onSignIn, required this.onHowItWorks});

  final bool isWide;
  final VoidCallback onSignIn;
  final VoidCallback onHowItWorks;

  @override
  Widget build(BuildContext context) {
    final headlineSize = isWide ? 72.0 : 40.0;

    final eyebrow = Text(
      'YOUR SHIFT, ORGANIZED',
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.stone500),
      textAlign: isWide ? TextAlign.right : TextAlign.left,
    );

    final headline = Text(
      'Run the floor,\nkeep it\nmoving.',
      style: TextStyle(
        fontSize: headlineSize,
        height: 1.02,
        fontWeight: FontWeight.w900,
        letterSpacing: -1.5,
        color: AppColors.stone900,
      ),
      textAlign: isWide ? TextAlign.right : TextAlign.left,
    );

    final subtext = Text(
      'Bookings, camera rentals, the day\u2019s schedule and guest feedback — everything you need for '
      'a smooth shift, in one place.',
      style: const TextStyle(fontSize: 13.5, height: 1.6, color: AppColors.stone500),
      textAlign: isWide ? TextAlign.right : TextAlign.left,
    );

    final pitchCard = Container(
      width: isWide ? 240 : double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.highlight, borderRadius: BorderRadius.circular(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('memoriae©', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.stone900)),
          const SizedBox(height: 14),
          const Text(
            'Everything you need to manage bookings and rentals on-site.',
            style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.stone900),
          ),
          const SizedBox(height: 14),
          const Text(
            'Built for the people\nrunning the event.',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, height: 1.4, color: AppColors.stone900),
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: onSignIn,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Details', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.stone900)),
                SizedBox(width: 6),
                Icon(Icons.arrow_forward, size: 14, color: AppColors.stone900),
              ],
            ),
          ),
        ],
      ),
    );

    final ctaRow = Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _PillButton(label: 'Sign In', onTap: onSignIn, dark: true, withArrow: true),
        _PillButton(label: 'How it works', onTap: onHowItWorks, dark: false, bordered: true),
      ],
    );

    final footerRow = Padding(
      padding: const EdgeInsets.only(top: 28),
      child: isWide
          ? const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EstBlock(),
                Spacer(),
                _FeatureCard(width: 260),
              ],
            )
          : const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EstBlock(),
                SizedBox(height: 20),
                _FeatureCard(width: double.infinity),
              ],
            ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isWide ? 48 : 20, vertical: isWide ? 24 : 12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: isWide ? 40 : -10,
            top: isWide ? 96 : 168,
            child: IgnorePointer(
              child: Text(
                'memoriae',
                style: TextStyle(
                  fontSize: isWide ? 220 : 90,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -6,
                  color: AppColors.stone900.withValues(alpha: 0.05),
                ),
              ),
            ),
          ),
          if (isWide) const _MetaRow(),
          Padding(
            padding: EdgeInsets.only(top: isWide ? 56 : 0),
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      pitchCard,
                      const Spacer(),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            eyebrow,
                            const SizedBox(height: 14),
                            headline,
                            const SizedBox(height: 16),
                            SizedBox(width: 420, child: subtext),
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      eyebrow,
                      const SizedBox(height: 10),
                      headline,
                      const SizedBox(height: 12),
                      subtext,
                      const SizedBox(height: 24),
                      pitchCard,
                    ],
                  ),
          ),
          Padding(
            padding: EdgeInsets.only(top: isWide ? 500 : 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ctaRow,
                footerRow,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetaLabel(eyebrow: 'TEAM', line: 'Memoriae / Staff Operations'),
        Spacer(),
        _MetaLabel(eyebrow: 'ACCESS', line: 'Granted by your admin', alignEnd: true),
      ],
    );
  }
}

class _MetaLabel extends StatelessWidget {
  const _MetaLabel({required this.eyebrow, required this.line, this.alignEnd = false});

  final String eyebrow;
  final String line;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(eyebrow, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.stone400)),
        const SizedBox(height: 3),
        Text(line, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.stone900)),
      ],
    );
  }
}

class _EstBlock extends StatelessWidget {
  const _EstBlock();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          text: const TextSpan(
            children: [
              TextSpan(text: 'Est.\n', style: TextStyle(fontSize: 11, color: AppColors.stone500)),
              TextSpan(text: '2024', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.stone900)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text('// memoriae staff', style: TextStyle(fontSize: 11, color: AppColors.stone500)),
        ),
      ],
    );
  }
}

/// Floating "status card" — a rounded white card with a small colored dot
/// + label header, a badge, a short numbered feature list, and a subtle
/// corner dot-grid. Structurally similar to mockup-card landing sections,
/// rebuilt entirely with Memoriae's maroon/gold palette and Roboto type.
class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.width});

  final double width;

  static const _items = ['Manage bookings', 'Track camera rentals', 'Update your calendar', 'Log guest feedback'];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.card,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'memoriae // staff',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.stone500),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.highlight, borderRadius: BorderRadius.circular(999)),
                    child: const Text(
                      'ON SHIFT',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.stone900, letterSpacing: 0.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (int i = 0; i < _items.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Text(
                        (i + 1).toString().padLeft(2, '0'),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.accent),
                      ),
                      const SizedBox(width: 10),
                      Text(_items[i], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.stone900)),
                    ],
                  ),
                ),
            ],
          ),
          const Positioned(right: -4, bottom: -4, child: _DotGrid()),
        ],
      ),
    );
  }
}

class _DotGrid extends StatelessWidget {
  const _DotGrid();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: 40,
        child: Wrap(
          spacing: 5,
          runSpacing: 5,
          children: List.generate(
            16,
            (i) => Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(color: AppColors.stone400.withValues(alpha: 0.4), shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProcessSection extends StatelessWidget {
  const _ProcessSection({required this.isWide});

  final bool isWide;

  static const _steps = [
    (
      'Check-in',
      'Greet the guest or client, confirm booking details, and get the day started on time.',
    ),
    (
      'Set Up',
      'Prep the booth, or hand off rented camera gear with a quick walkthrough.',
    ),
    (
      'Assist',
      'Help guests through the session and keep the line moving smoothly.',
    ),
    (
      'Wrap Up',
      'Log feedback, return gear to inventory, and close out the shift.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(isWide ? 48 : 20, 80, isWide ? 48 : 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '02 — HOW IT WORKS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.stone500),
          ),
          const SizedBox(height: 12),
          Text(
            'How it\nworks.',
            style: TextStyle(
              fontSize: isWide ? 56 : 36,
              height: 1.02,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              color: AppColors.stone900,
            ),
          ),
          const SizedBox(height: 40),
          for (int i = 0; i < _steps.length; i++) ...[
            _ProcessRow(
              index: i + 1,
              title: _steps[i].$1,
              description: _steps[i].$2,
              isWide: isWide,
            ),
            if (i != _steps.length - 1) const Divider(color: AppColors.stone200, height: 1),
          ],
        ],
      ),
    );
  }
}

class _ProcessRow extends StatelessWidget {
  const _ProcessRow({required this.index, required this.title, required this.description, required this.isWide});

  final int index;
  final String title;
  final String description;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final indexLabel = index.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(indexLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.stone400)),
          const SizedBox(width: 20),
          SizedBox(
            width: isWide ? 160 : 100,
            child: Text(
              title,
              style: TextStyle(fontSize: isWide ? 26 : 20, fontWeight: FontWeight.w900, color: AppColors.stone900),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Text(description, style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.stone500)),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.north_east, size: 18, color: AppColors.stone400),
        ],
      ),
    );
  }
}

class _ClosingBand extends StatelessWidget {
  const _ClosingBand({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.highlight,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 16,
        children: [
          const Text(
            'Ready to start\nyour shift?',
            style: TextStyle(fontSize: 28, height: 1.1, fontWeight: FontWeight.w900, color: AppColors.stone900),
          ),
          _PillButton(label: 'Sign In', onTap: onSignIn, dark: true, withArrow: true),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.onTap,
    this.dark = false,
    this.dense = false,
    this.withArrow = false,
    this.bordered = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool dark;
  final bool dense;
  final bool withArrow;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: dark ? AppColors.stone900 : Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: dense ? 18 : 24, vertical: dense ? 10 : 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: bordered ? Border.all(color: AppColors.border) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: dense ? 12 : 14,
                  fontWeight: FontWeight.w700,
                  color: dark ? Colors.white : AppColors.stone900,
                ),
              ),
              if (withArrow) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_forward, size: 14, color: AppColors.stone900),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
