import 'dart:ui' show lerpDouble;
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../screens/info_pages.dart';
import '../screens/my_bookings_screen.dart';
import '../services/auth_service.dart';
import 'app_bottom_nav.dart' show kAppTabs;
import 'profile_avatar.dart';

/// Slide menu for the mobile layout.
///
/// Opening it pushes the whole screen to the right and shrinks it, which
/// reveals the menu behind it (with a second card peeking out from behind
/// the page). Open it with [SlideMenuState.open], by swiping in from the
/// left edge, or from the bottom nav's grid button; close it by tapping the
/// page, swiping it back, or choosing an item. The Android back button
/// closes it first.
///
/// Descendants reach it with [SlideMenu.maybeOf].
class SlideMenu extends StatefulWidget {
  final Widget child;
  final int currentIndex;

  const SlideMenu({super.key, required this.child, required this.currentIndex});

  /// The nearest slide menu, or null when the layout has none (desktop).
  static SlideMenuState? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_SlideMenuScope>()?.state;

  @override
  State<SlideMenu> createState() => SlideMenuState();
}

class _SlideMenuScope extends InheritedWidget {
  final SlideMenuState state;
  const _SlideMenuScope({required this.state, required super.child});

  @override
  bool updateShouldNotify(_SlideMenuScope old) => false;
}

class SlideMenuState extends State<SlideMenu> with SingleTickerProviderStateMixin {
  static const double _slideFraction = 0.68;

  late final AnimationController _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 360));
  double _maxSlide = 260;
  String? _name;

  bool get isOpen => _ctrl.value > 0.01;

  void open() {
    HapticFeedback.lightImpact();
    _ctrl.animateTo(1, curve: Curves.easeOutCubic);
  }

  Future<void> close() => _ctrl.animateTo(0, curve: Curves.easeOutCubic);

  void toggle() => isOpen ? close() : open();

  @override
  void initState() {
    super.initState();
    AuthService.instance.me().then((u) {
      if (mounted) setState(() => _name = u?.fullName);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _displayName {
    var n = (_name ?? '').trim();
    if (n.contains('@')) n = n.split('@').first;
    return n;
  }

  String get _initials {
    final parts = _displayName.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _ctrl.value += (d.primaryDelta ?? 0) / _maxSlide;
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() > 365) {
      v > 0 ? _ctrl.animateTo(1, curve: Curves.easeOutCubic) : _ctrl.animateTo(0, curve: Curves.easeOutCubic);
    } else {
      _ctrl.value > 0.5 ? _ctrl.animateTo(1, curve: Curves.easeOutCubic) : _ctrl.animateTo(0, curve: Curves.easeOutCubic);
    }
  }

  /// Closes the menu, then runs [action] (navigation), so the page is back
  /// at full size before it is swapped out.
  Future<void> _closeThen(VoidCallback action) async {
    await close();
    if (mounted) action();
  }

  void _goToTab(int index) {
    if (index == widget.currentIndex) {
      close();
      return;
    }
    _closeThen(() => Navigator.of(context).pushReplacementNamed(kAppTabs[index].route));
  }

  @override
  Widget build(BuildContext context) {
    return _SlideMenuScope(
      state: this,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          _maxSlide = w * _slideFraction;
          return AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final t = _ctrl.value;
              return PopScope(
                canPop: t < 0.01,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) close();
                },
                child: Stack(
                  children: [
                    _buildMenu(context, t),
                    if (t > 0) _buildGhostCard(w, t),
                    _buildPage(w, t),
                    // Left-edge strip: swipe in from the edge to open.
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 18,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragUpdate: _onDragUpdate,
                        onHorizontalDragEnd: _onDragEnd,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // --- The page (pushed aside) -------------------------------------------

  Widget _buildPage(double w, double t) {
    final radius = lerpDouble(0, 30, t)! * 2;
    final shape = ContinuousRectangleBorder(borderRadius: BorderRadius.circular(radius));
    return Transform.translate(
      offset: Offset(_maxSlide * t, 0),
      child: Transform.scale(
        scale: 1 - 0.12 * t,
        alignment: Alignment.centerLeft,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: shape,
            shadows: [BoxShadow(color: Colors.black.withValues(alpha: 0.35 * t), blurRadius: 40, offset: const Offset(-4, 12))],
          ),
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: shape),
            child: Stack(
              children: [
                widget.child,
                // While open the page is only a "tap to close" target.
                if (t > 0)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: close,
                      onHorizontalDragUpdate: _onDragUpdate,
                      onHorizontalDragEnd: _onDragEnd,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A second, smaller card sitting behind the page and peeking out on the
  /// right, which gives the open state its stacked look.
  Widget _buildGhostCard(double w, double t) {
    final radius = lerpDouble(0, 30, t)! * 2;
    return Transform.translate(
      offset: Offset(_maxSlide * t + (0.12 * w + 18) * t, 0),
      child: Transform.scale(
        scale: 1 - 0.24 * t,
        alignment: Alignment.centerLeft,
        child: SizedBox.expand(
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: ContinuousRectangleBorder(borderRadius: BorderRadius.circular(radius)),
              color: Colors.white.withValues(alpha: 0.16 * t),
            ),
          ),
        ),
      ),
    );
  }

  // --- The menu (revealed behind) ----------------------------------------

  Widget _buildMenu(BuildContext context, double t) {
    return Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF8A2429), Color(0xFF2A0D0F)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -120,
              bottom: -100,
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [const Color(0xFFE0B24C).withValues(alpha: 0.28), const Color(0xFFE0B24C).withValues(alpha: 0)]),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: _maxSlide + 20,
                  child: IgnorePointer(
                    ignoring: t < 0.6,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 20, 0, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fade(t, 0.05, _buildProfile()),
                          const SizedBox(height: 26),
                          for (var i = 0; i < kAppTabs.length; i++)
                            _fade(
                              t,
                              0.12 + i * 0.05,
                              _menuItem(kAppTabs[i].icon, kAppTabs[i].label, i == widget.currentIndex, () => _goToTab(i)),
                            ),
                          _fade(
                            t,
                            0.12 + kAppTabs.length * 0.05,
                            _menuItem(CupertinoIcons.ticket_fill, "My Bookings", false,
                                () => _closeThen(() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyBookingsScreen())))),
                          ),
                          const SizedBox(height: 22),
                          _fade(t, 0.5, _buildFooterLinks(context)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Fades + slides a menu element in as the menu opens, starting at
  /// [start] (0–1 of the open animation).
  Widget _fade(double t, double start, Widget child) {
    final p = Curves.easeOutCubic.transform(((t - start) / (1 - start)).clamp(0.0, 1.0));
    return Opacity(opacity: p, child: Transform.translate(offset: Offset(-26 * (1 - p), 0), child: child));
  }

  Widget _buildProfile() {
    final initials = _initials;
    return GestureDetector(
      onTap: () => _goToTab(6),
      child: Row(
        children: [
          ProfileAvatar(
            size: 54,
            color: Colors.white.withValues(alpha: 0.18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.2),
            fallback: initials.isEmpty
                ? const Icon(CupertinoIcons.person_fill, size: 24, color: Colors.white)
                : Text(initials, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayName.isEmpty ? "Welcome" : _displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: Colors.white),
                ),
                const SizedBox(height: 2),
                const Text("View profile", style: TextStyle(fontSize: 13, color: Colors.white60)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, bool active, VoidCallback onTap) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: active ? Colors.white : Colors.white70),
          const SizedBox(width: 14),
          Text(
            label,
            style: TextStyle(fontSize: 20, fontWeight: active ? FontWeight.w700 : FontWeight.w500, letterSpacing: -0.3, color: active ? Colors.white : Colors.white70),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: active
              ? DecoratedBox(decoration: ShapeDecoration(shape: const StadiumBorder(), color: Colors.white.withValues(alpha: 0.16)), child: row)
              : row,
        ),
      ),
    );
  }

  Widget _buildFooterLinks(BuildContext context) {
    Widget link(String label, VoidCallback onTap) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Text(label, style: const TextStyle(fontSize: 14, color: Colors.white54)),
          ),
        );
    void push(Widget page) => _closeThen(() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 40, height: 0.5, color: Colors.white24),
        const SizedBox(height: 10),
        link("FAQs", () => push(const FaqScreen())),
        link("Cancellation Policy", () => push(const PolicyScreen(title: "Cancellation Policy", sections: kCancellationPolicySections))),
        link("Terms of Service", () => push(const PolicyScreen(title: "Terms of Service", sections: kTermsOfServiceSections))),
        link("Privacy Policy", () => push(const PolicyScreen(title: "Privacy Policy", sections: kPrivacyPolicySections, lastUpdated: kPrivacyPolicyLastUpdated))),
      ],
    );
  }
}