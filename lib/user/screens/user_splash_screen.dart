import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Memoriae splash screen.
///
/// Pure animation widget: logo fades/scales in, tagline slides up, and a thin
/// progress line fills at the bottom. It does no navigation or loading itself —
/// `_WelcomeGate` (in user_app.dart) shows it while the session check runs and
/// keeps it on screen for at least [minDuration] so it never just flashes by.
class UserSplashScreen extends StatefulWidget {
  const UserSplashScreen({super.key});

  /// Minimum time the splash stays visible.
  static const Duration minDuration = Duration(milliseconds: 2200);

  @override
  State<UserSplashScreen> createState() => _UserSplashScreenState();
}

class _UserSplashScreenState extends State<UserSplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _tagFade;
  late final Animation<Offset> _tagSlide;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: UserSplashScreen.minDuration)..forward();

    _logoFade = CurvedAnimation(parent: _c, curve: const Interval(0.0, 0.40, curve: Curves.easeOut));
    _logoScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _c, curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack)),
    );
    _tagFade = CurvedAnimation(parent: _c, curve: const Interval(0.35, 0.70, curve: Curves.easeOut));
    _tagSlide = Tween<Offset>(begin: const Offset(0, 0.6), end: Offset.zero).animate(
      CurvedAnimation(parent: _c, curve: const Interval(0.35, 0.70, curve: Curves.easeOutCubic)),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final logoSize = (width * 0.72).clamp(200.0, 340.0);

    return Scaffold(
      // Same cream as the logo artwork, so the logo blends in with no visible box.
      backgroundColor: AppColors.brandCream,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FadeTransition(
                      opacity: _logoFade,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: Image.asset(
                          'assets/images/memoriae_logo.webp',
                          width: logoSize,
                          height: logoSize,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FadeTransition(
                      opacity: _tagFade,
                      child: SlideTransition(
                        position: _tagSlide,
                        child: const Text(
                          'CAPTURE THE MOMENT',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 3,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Thin progress line
            Padding(
              padding: const EdgeInsets.only(bottom: 48),
              child: SizedBox(
                width: 120,
                height: 3,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: _c.value,
                      backgroundColor: AppColors.accentTint(0.15),
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
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
}