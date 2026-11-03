import '../../shared/centered_body.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// First-run tutorial for the customer app: four animated slides with Skip,
/// dot indicators, parallax on swipe, and Next / Get started.
///
/// Shown once after the splash (see `_WelcomeGate` in user_app.dart). It can
/// be replayed from Profile with `replay: true`, which does not change the
/// first-run flag.
class UserOnboardingScreen extends StatefulWidget {
  final bool replay;

  const UserOnboardingScreen({super.key, this.replay = false});

  static const _seenKey = 'user_onboarding_seen_v1';

  /// True if the customer already finished or skipped the tutorial.
  static Future<bool> hasSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_seenKey) ?? false;
    } catch (_) {
      // If storage fails, don't block the app with the tutorial every launch.
      return true;
    }
  }

  static Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_seenKey, true);
    } catch (_) {}
  }

  @override
  State<UserOnboardingScreen> createState() => _UserOnboardingScreenState();
}

class _Slide {
  final IconData mainIcon;
  final String title;
  final String body;
  final List<_Satellite> satellites;
  const _Slide({
    required this.mainIcon,
    required this.title,
    required this.body,
    required this.satellites,
  });
}

class _Satellite {
  final IconData icon;
  final Alignment alignment;
  final Color? color;
  final double phase;
  const _Satellite({required this.icon, required this.alignment, this.color, this.phase = 0});
}

const _slides = <_Slide>[
  _Slide(
    mainIcon: Icons.calendar_month_rounded,
    title: 'Book your photobooth',
    body: 'Pick a package, then choose your date and time. Your date is held for 15 minutes while you pay.',
    satellites: [
      _Satellite(icon: Icons.photo_camera_rounded, alignment: Alignment(0.9, -0.85), phase: 0),
      _Satellite(icon: Icons.schedule_rounded, alignment: Alignment(-0.95, 0.5), phase: 2),
      _Satellite(icon: Icons.check_circle_rounded, alignment: Alignment(0.85, 0.75), color: AppColors.highlight, phase: 4),
    ],
  ),
  _Slide(
    mainIcon: Icons.payments_rounded,
    title: 'Pay and confirm',
    body: 'Send your downpayment via GCash, then upload a screenshot of the receipt. That turns your hold into a booking request. The balance is paid on the event day.',
    satellites: [
      _Satellite(icon: Icons.qr_code_2_rounded, alignment: Alignment(-0.9, -0.8), phase: 1),
      _Satellite(icon: Icons.upload_file_rounded, alignment: Alignment(0.95, 0.1), phase: 3),
      _Satellite(icon: Icons.verified_rounded, alignment: Alignment(-0.7, 0.85), color: AppColors.highlight, phase: 5),
    ],
  ),
  _Slide(
    mainIcon: Icons.camera_alt_rounded,
    title: 'Rent a camera',
    body: 'Choose your rental length and pick up the camera at the shop. Return it on time to avoid overdue fees.',
    satellites: [
      _Satellite(icon: Icons.timer_outlined, alignment: Alignment(0.9, -0.8), phase: 0.5),
      _Satellite(icon: Icons.wb_sunny_rounded, alignment: Alignment(-0.95, 0.2), color: AppColors.highlight, phase: 2.5),
      _Satellite(icon: Icons.image_outlined, alignment: Alignment(0.6, 0.9), phase: 4.5),
    ],
  ),
  _Slide(
    mainIcon: Icons.notifications_active_rounded,
    title: 'Track everything',
    body: 'See your bookings, your rental countdown, and messages from the shop in one place.',
    satellites: [
      _Satellite(icon: Icons.receipt_long_rounded, alignment: Alignment(0.9, -0.8), phase: 0.5),
      _Satellite(icon: Icons.chat_bubble_rounded, alignment: Alignment(-0.95, 0.2), phase: 2.5),
      _Satellite(icon: Icons.event_available_rounded, alignment: Alignment(0.6, 0.9), color: AppColors.highlight, phase: 4.5),
    ],
  ),
];

class _UserOnboardingScreenState extends State<UserOnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;
  double _pageValue = 0;

  bool get _isLast => _page == _slides.length - 1;

  @override
  void initState() {
    super.initState();
    if (!widget.replay) UserOnboardingScreen.markSeen();
    _controller.addListener(() {
      setState(() => _pageValue = _controller.page ?? 0);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _back() {
    if (_page > 0) {
      _controller.previousPage(duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    }
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.surface(context),
      body: CenteredBody(child: SafeArea(
        child: Column(
          children: [
            // Skip sits top-right; the space is kept on the last slide so the
            // layout does not jump.
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 12, 0),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: _isLast ? 0 : 1,
                  child: IgnorePointer(
                    ignoring: _isLast,
                    child: _SkipButton(onTap: _finish),
                  ),
                ),
              ),
            ),

            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => _SlideView(
                  slide: _slides[i],
                  offset: _pageValue - i,
                  active: (_pageValue - i).abs() < 0.5,
                ),
              ),
            ),

            // Dot indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? AppColors.accent : AppColors.accentTint(0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                children: [
                  if (_page > 0) ...[
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: _back,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.accent,
                            side: BorderSide(color: AppColors.accentTint(0.35)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('Back', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _next,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.onAccent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(anim),
                              child: child,
                            ),
                          ),
                          child: Text(
                            _isLast ? 'Get started' : 'Next',
                            key: ValueKey(_isLast),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ), maxWidth: 560),
    );
  }
}

class _SlideView extends StatefulWidget {
  final _Slide slide;
  /// Page position relative to this slide: 0 when centered, ±1 when a full page away.
  final double offset;
  /// True when this slide is (nearly) the one on screen; replays the entrance.
  final bool active;

  const _SlideView({required this.slide, required this.offset, required this.active});

  @override
  State<_SlideView> createState() => _SlideViewState();
}

class _SlideViewState extends State<_SlideView> with TickerProviderStateMixin {
  late final AnimationController _enter;
  late final AnimationController _float;

  // Animations are created once here, not inside build(), so rebuilds don't
  // keep adding listeners to the entrance controller.
  late final Animation<double> _ringOuter;
  late final Animation<double> _ringInner;
  late final Animation<double> _tile;
  late final Animation<double> _titleAnim;
  late final Animation<double> _bodyAnim;
  late final Animation<double> _popAnim;
  late final Animation<Offset> _titleSlide;
  late final Animation<Offset> _bodySlide;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _float = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _ringOuter = _interval(0.0, 0.7, Curves.easeOutBack);
    _ringInner = _interval(0.05, 0.75, Curves.easeOutBack);
    _tile = _interval(0.15, 0.9, Curves.easeOutBack);
    _titleAnim = _interval(0.35, 0.8);
    _bodyAnim = _interval(0.5, 0.95);
    _popAnim = _interval(0.4, 1.0, Curves.easeOutBack);
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(_titleAnim);
    _bodySlide = Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(_bodyAnim);
    if (widget.active) _enter.forward();
  }

  @override
  void didUpdateWidget(covariant _SlideView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Replay the entrance each time the slide comes into view.
    if (widget.active && !oldWidget.active) _enter.forward(from: 0);
  }

  @override
  void dispose() {
    _enter.dispose();
    _float.dispose();
    super.dispose();
  }

  Animation<double> _interval(double begin, double end, [Curve curve = Curves.easeOutCubic]) =>
      CurvedAnimation(parent: _enter, curve: Interval(begin, end, curve: curve));

  @override
  Widget build(BuildContext context) {
    final parallax = widget.offset.clamp(-1.0, 1.0);
    final fade = (1 - parallax.abs() * 0.6).clamp(0.0, 1.0);

    return Transform.translate(
      offset: Offset(-parallax * 60, 0),
      child: Opacity(
        opacity: fade,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildIllustration(),
              const SizedBox(height: 44),
              FadeTransition(
                opacity: _titleAnim,
                child: SlideTransition(
                  position: _titleSlide,
                  child: Text(
                    widget.slide.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                      color: AppPalette.textPrimary(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FadeTransition(
                opacity: _bodyAnim,
                child: SlideTransition(
                  position: _bodySlide,
                  child: Text(
                    widget.slide.body,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: AppPalette.textMuted(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Layered illustration: soft rings, a gradient main tile that pops in, and
  /// small satellite badges that float around it.
  Widget _buildIllustration() {
    const size = 250.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft outer ring
          ScaleTransition(
            scale: _ringOuter,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentTint(0.05),
              ),
            ),
          ),
          // Inner ring
          ScaleTransition(
            scale: _ringInner,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentTint(0.09),
              ),
            ),
          ),
          // Main gradient tile
          ScaleTransition(
            scale: _tile,
            child: Transform.rotate(
              angle: -0.08,
              child: Container(
                width: 124,
                height: 124,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(34),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF8B2A2D), AppColors.accent],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.35),
                      blurRadius: 30,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Icon(widget.slide.mainIcon, size: 58, color: AppColors.onAccent),
              ),
            ),
          ),
          // Floating satellites
          for (final sat in widget.slide.satellites) _satellite(sat, size),
        ],
      ),
    );
  }

  Widget _satellite(_Satellite sat, double size) {
    final badgeColor = sat.color ?? AppColors.accent;
    return AnimatedBuilder(
      animation: Listenable.merge([_float, _enter]),
      builder: (context, child) {
        final dy = math.sin(_float.value * 2 * math.pi + sat.phase) * 7;
        final pop = _popAnim.value;
        return Align(
          alignment: sat.alignment,
          child: Transform.translate(
            offset: Offset(0, dy),
            child: Transform.scale(scale: pop.clamp(0.0, 1.2), child: child),
          ),
        );
      },
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppPalette.surface(context),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(sat.icon, size: 24, color: badgeColor),
      ),
    );
  }
}

/// Skip button as a light accent tint with an accent label, so it stays
/// visible but doesn't compete with the Next button.
class _SkipButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SkipButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accentTint(0.1),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          child: Text(
            'Skip',
            style: TextStyle(color: AppColors.accent, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
