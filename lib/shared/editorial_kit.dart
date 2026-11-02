import 'package:flutter/material.dart';

/// Shared building blocks for the editorial Memoriae landing pages
/// (Admin + Staff). Same look as the customer landing page: cream
/// background, hairline rules, huge lowercase wordmark, tracked uppercase
/// labels, black pill buttons, and numbered dark / maroon sections.
///
/// Colors are declared here (same hex values as every app's AppColors) so
/// this file does not depend on any one app's theme.
class Ed {
  Ed._();

  static const Color accent = Color(0xFF6E1B1E);
  static const Color cream = Color(0xFFFBF4E8);
  static const Color gold = Color(0xFFE0B24C);
  static const Color grey = Color(0xFFF4F4F4);
  static const Color ink = Color(0xFF1A1A1A);
  static const Color stone500 = Color(0xFF78716C);
  static const Color stone400 = Color(0xFFA8A29E);
  static const Color border = Color(0xFFD1D1D1);

  static double pad(bool isWide) => isWide ? 40 : 18;
}

// ---------------------------------------------------------------------------
// Small primitives
// ---------------------------------------------------------------------------

class EdRule extends StatelessWidget {
  const EdRule({super.key, this.color = Ed.border});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(height: 1, color: color);
}

/// Fade + slide-up the first time the child scrolls into view.
class EdReveal extends StatefulWidget {
  const EdReveal({super.key, required this.child, this.offset = 30});
  final Widget child;
  final double offset;

  @override
  State<EdReveal> createState() => _EdRevealState();
}

class _EdRevealState extends State<EdReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final Animation<double> _fade = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  ScrollPosition? _position;
  bool _triggered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Scrollable.maybeOf(context)?.position;
    if (next != _position) {
      _position?.removeListener(_check);
      _position = next;
      _position?.addListener(_check);
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  void _check() {
    if (_triggered || !mounted) return;
    final ro = context.findRenderObject();
    if (ro is! RenderBox || !ro.attached) return;
    final top = ro.localToGlobal(Offset.zero).dy;
    if (top < MediaQuery.sizeOf(context).height * 0.88) {
      _triggered = true;
      _position?.removeListener(_check);
      _c.forward();
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _fade.value,
        child: Transform.translate(offset: Offset(0, widget.offset * (1 - _fade.value)), child: child),
      ),
    );
  }
}

class EdPillButton extends StatefulWidget {
  const EdPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.outlined = false,
    this.compact = false,
    this.onDark = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;
  final bool outlined;
  final bool compact;
  final bool onDark;

  @override
  State<EdPillButton> createState() => _EdPillButtonState();
}

class _EdPillButtonState extends State<EdPillButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    Color line;
    if (widget.onDark) {
      bg = widget.filled ? Ed.cream : Colors.transparent;
      fg = widget.filled ? Ed.ink : Ed.cream;
      line = Ed.cream;
    } else if (widget.filled) {
      bg = _hover ? Ed.accent : Ed.ink;
      fg = Ed.cream;
      line = bg;
    } else {
      bg = Colors.transparent;
      fg = Ed.ink;
      line = Ed.border;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 16 : 20, vertical: widget.compact ? 9 : 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: (widget.outlined || widget.onDark) ? Border.all(color: line) : null,
          ),
          child: Text(
            widget.label,
            style: TextStyle(fontSize: widget.compact ? 12 : 13, fontWeight: FontWeight.w700, color: fg),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class EdNavItem {
  const EdNavItem(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;
}

class EdHeader extends StatelessWidget {
  const EdHeader({
    super.key,
    required this.isWide,
    required this.roleLabel,
    required this.links,
    required this.onSignIn,
  });

  final bool isWide;
  final String roleLabel;
  final List<EdNavItem> links;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: Ed.pad(isWide), vertical: 16),
      child: Row(
        children: [
          Container(
            width: 31,
            height: 31,
            decoration: BoxDecoration(color: Ed.accent, borderRadius: BorderRadius.circular(7)),
            child: const Icon(Icons.camera_alt_outlined, size: 16, color: Ed.cream),
          ),
          const SizedBox(width: 10),
          const Text(
            'memoriae',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: Ed.ink),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(border: Border.all(color: Ed.border), borderRadius: BorderRadius.circular(999)),
            child: Text(
              roleLabel.toUpperCase(),
              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: Ed.accent),
            ),
          ),
          const Spacer(),
          if (isWide) ...[
            for (final l in links)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: InkWell(
                  onTap: l.onTap,
                  child: Text(l.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Ed.ink)),
                ),
              ),
            const SizedBox(width: 16),
          ],
          EdPillButton(label: 'Sign In', onTap: onSignIn, filled: true, compact: true),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

class EdHero extends StatelessWidget {
  const EdHero({
    super.key,
    required this.isWide,
    required this.eyebrow,
    required this.headline,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  final bool isWide;
  final String eyebrow; // two lines separated by \n
  final String headline; // two lines separated by \n
  final String body;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(body, style: const TextStyle(fontSize: 14, height: 1.7, color: Ed.stone500)),
        const SizedBox(height: 24),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            EdPillButton(label: primaryLabel, onTap: onPrimary, filled: true),
            EdPillButton(label: secondaryLabel, onTap: onSecondary, outlined: true),
          ],
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(Ed.pad(isWide), isWide ? 54 : 28, Ed.pad(isWide), isWide ? 70 : 44),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  eyebrow,
                  style: const TextStyle(fontSize: 11, height: 1.25, fontWeight: FontWeight.w700, letterSpacing: 1.8, color: Ed.stone500),
                ),
              ),
              Text(
                'CALAUAN · LAGUNA',
                style: TextStyle(fontSize: isWide ? 11 : 9, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Ed.stone400),
              ),
            ],
          ),
          const SizedBox(height: 42),
          Text(
            'memoriae',
            maxLines: 1,
            overflow: TextOverflow.visible,
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: isWide ? 154 : 76,
              height: .78,
              letterSpacing: isWide ? -8 : -4,
              fontWeight: FontWeight.w500,
              color: Ed.ink,
            ),
          ),
          const SizedBox(height: 22),
          Container(height: 1, color: Ed.ink),
          const SizedBox(height: 28),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 7,
                  child: Text(
                    headline,
                    style: const TextStyle(fontSize: 59, height: .90, fontWeight: FontWeight.w800, letterSpacing: -2.5, color: Ed.ink),
                  ),
                ),
                const SizedBox(width: 70),
                Expanded(flex: 3, child: copy),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: const TextStyle(fontSize: 38, height: .92, fontWeight: FontWeight.w800, letterSpacing: -1.4, color: Ed.ink),
                ),
                const SizedBox(height: 26),
                copy,
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dark numbered showcase panel (sample dashboard card)
// ---------------------------------------------------------------------------

class EdShowcase extends StatelessWidget {
  const EdShowcase({
    super.key,
    required this.isWide,
    required this.caption,
    required this.subcaption,
    required this.cardTitle,
    required this.rows,
    required this.tileLabel,
    required this.tileValue,
    required this.tileIcon,
  });

  final bool isWide;
  final String caption;
  final String subcaption;
  final String cardTitle;
  final List<(String, String)> rows; // label, value
  final String tileLabel;
  final String tileValue;
  final IconData tileIcon;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Ed.cream, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(cardTitle, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.6, color: Ed.accent)),
          const SizedBox(height: 14),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Container(height: 1, color: Ed.border, margin: const EdgeInsets.symmetric(vertical: 11)),
            Row(
              children: [
                Expanded(child: Text(rows[i].$1, style: const TextStyle(fontSize: 13, color: Ed.stone500))),
                Text(rows[i].$2, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Ed.ink)),
              ],
            ),
          ],
        ],
      ),
    );

    final tile = Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: Ed.accent, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(tileIcon, size: 34, color: Ed.cream),
          const SizedBox(height: 26),
          Text(tileLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.6, color: Ed.cream)),
          const SizedBox(height: 6),
          Text(tileValue, style: const TextStyle(fontSize: 34, height: 1, fontWeight: FontWeight.w800, letterSpacing: -1, color: Ed.cream)),
        ],
      ),
    );

    return Container(
      color: Ed.ink,
      padding: EdgeInsets.fromLTRB(Ed.pad(isWide), 26, Ed.pad(isWide), isWide ? 56 : 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('01', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Ed.cream)),
          const SizedBox(height: 22),
          Center(
            child: Column(
              children: [
                Text(caption, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.6, color: Ed.cream)),
                const SizedBox(height: 10),
                Text(subcaption, style: const TextStyle(fontSize: 12, letterSpacing: 1.4, color: Ed.gold)),
              ],
            ),
          ),
          const SizedBox(height: 30),
          if (isWide)
            // IntrinsicHeight is required: `stretch` inside a scroll view
            // has unbounded height and would otherwise throw.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 6, child: card),
                  const SizedBox(width: 18),
                  Expanded(flex: 4, child: tile),
                ],
              ),
            )
          else ...[
            card,
            const SizedBox(height: 14),
            tile,
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Numbered list section ("what you handle")
// ---------------------------------------------------------------------------

class EdRowItem {
  const EdRowItem(this.icon, this.title, this.text);
  final IconData icon;
  final String title;
  final String text;
}

class EdNumberedList extends StatelessWidget {
  const EdNumberedList({super.key, required this.isWide, required this.label, required this.title, required this.items});

  final bool isWide;
  final String label;
  final String title;
  final List<EdRowItem> items;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.8, color: Ed.stone500)),
        const SizedBox(height: 14),
        Text(
          title,
          style: TextStyle(fontSize: isWide ? 44 : 30, height: .95, fontWeight: FontWeight.w800, letterSpacing: isWide ? -1.8 : -1.1, color: Ed.ink),
        ),
      ],
    );

    final list = Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const EdRule(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 34,
                  child: Text('0${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Ed.accent)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(items[i].title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: Ed.ink)),
                      const SizedBox(height: 5),
                      Text(items[i].text, style: const TextStyle(fontSize: 13.5, height: 1.6, color: Ed.stone500)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(items[i].icon, size: 22, color: Ed.ink),
              ],
            ),
          ),
        ],
      ],
    );

    return Container(
      color: Ed.grey,
      padding: EdgeInsets.fromLTRB(Ed.pad(isWide), isWide ? 70 : 40, Ed.pad(isWide), isWide ? 60 : 28),
      child: isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: heading),
                const SizedBox(width: 70),
                Expanded(flex: 6, child: list),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [heading, const SizedBox(height: 26), list],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Maroon "how a day goes" steps
// ---------------------------------------------------------------------------

class EdSteps extends StatelessWidget {
  const EdSteps({super.key, required this.isWide, required this.label, required this.title, required this.steps});

  final bool isWide;
  final String label;
  final String title;
  final List<(String, String)> steps; // title, text

  @override
  Widget build(BuildContext context) {
    Widget step(int i) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 1, color: Ed.cream.withValues(alpha: 0.35), margin: const EdgeInsets.only(bottom: 14)),
            Text('0${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Ed.gold)),
            const SizedBox(height: 10),
            Text(steps[i].$1, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: Ed.cream)),
            const SizedBox(height: 8),
            Text(steps[i].$2, style: TextStyle(fontSize: 13.5, height: 1.6, color: Ed.cream.withValues(alpha: 0.78))),
          ],
        );

    return Container(
      color: Ed.accent,
      padding: EdgeInsets.fromLTRB(Ed.pad(isWide), isWide ? 70 : 44, Ed.pad(isWide), isWide ? 70 : 44),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.8, color: Ed.cream.withValues(alpha: 0.7))),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(fontSize: isWide ? 44 : 30, height: .95, fontWeight: FontWeight.w800, letterSpacing: isWide ? -1.8 : -1.1, color: Ed.cream),
          ),
          SizedBox(height: isWide ? 44 : 30),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < steps.length; i++) ...[
                  if (i > 0) const SizedBox(width: 36),
                  Expanded(child: step(i)),
                ],
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < steps.length; i++) ...[
                  if (i > 0) const SizedBox(height: 28),
                  step(i),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Closing CTA + footer
// ---------------------------------------------------------------------------

class EdCta extends StatelessWidget {
  const EdCta({super.key, required this.isWide, required this.headline, required this.body, required this.label, required this.onTap});

  final bool isWide;
  final String headline;
  final String body;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(Ed.pad(isWide), isWide ? 80 : 48, Ed.pad(isWide), isWide ? 80 : 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: TextStyle(fontSize: isWide ? 64 : 38, height: .92, fontWeight: FontWeight.w800, letterSpacing: isWide ? -2.6 : -1.4, color: Ed.ink),
          ),
          const SizedBox(height: 18),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(body, style: const TextStyle(fontSize: 14, height: 1.7, color: Ed.stone500)),
          ),
          const SizedBox(height: 26),
          EdPillButton(label: label, onTap: onTap, filled: true),
        ],
      ),
    );
  }
}

class EdFooter extends StatelessWidget {
  const EdFooter({super.key, required this.isWide, required this.roleLabel});
  final bool isWide;
  final String roleLabel;

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    return Container(
      color: Ed.ink,
      padding: EdgeInsets.symmetric(horizontal: Ed.pad(isWide), vertical: 28),
      child: Flex(
        direction: isWide ? Axis.horizontal : Axis.vertical,
        crossAxisAlignment: isWide ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          const Text('memoriae', style: TextStyle(fontFamily: 'Georgia', fontSize: 26, letterSpacing: -1.2, color: Ed.cream)),
          if (isWide) const Spacer() else const SizedBox(height: 10),
          Text(
            '© $year Memoriae · $roleLabel · Calauan, Laguna',
            style: TextStyle(fontSize: 11, letterSpacing: 0.6, color: Ed.cream.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}
