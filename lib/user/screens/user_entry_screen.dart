import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// Short, no-scroll entry screen shown after the splash to logged-out users.
///
/// Log In / Register / Continue as Guest — same behaviour as the buttons on
/// the long marketing page (`UserWelcomeScreen`), which is kept in the project
/// untouched so its sections can be reused for the web landing page later.
class UserEntryScreen extends StatefulWidget {
  const UserEntryScreen({super.key});

  @override
  State<UserEntryScreen> createState() => _UserEntryScreenState();
}

class _UserEntryScreenState extends State<UserEntryScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
    _fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _enterLogin() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (result == true && mounted) {
      Navigator.of(context).pushReplacementNamed('/');
    }
  }

  Future<void> _enterRegister() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
    if (result == true && mounted) {
      Navigator.of(context).pushReplacementNamed('/');
    }
  }

  void _enterGuest() {
    // Browsing without an account already works — AuthService.me() hands
    // back an anonymous "Guest User" until they register or log in.
    Navigator.of(context).pushReplacementNamed('/');
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final logoSize = (height * 0.17).clamp(90.0, 150.0);
    // On a wide window (desktop browser) the panel is a card in the middle of
    // the page instead of a sheet stuck to the bottom edge.
    final wide = MediaQuery.sizeOf(context).width >= 700;

    return Scaffold(
      backgroundColor: AppColors.forest900,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppGradients.page),
        child: SafeArea(
          bottom: false,
          child: Center(
            // Keeps the layout phone-sized on web / tablets.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(
                  position: _slide,
                  child: Column(
                    mainAxisAlignment: wide ? MainAxisAlignment.center : MainAxisAlignment.start,
                    children: [
                      if (!wide) const Spacer(flex: 2),
                      Container(
                        width: logoSize,
                        height: logoSize,
                        padding: EdgeInsets.all(logoSize * 0.14),
                        decoration: BoxDecoration(
                          color: AppColors.brandCream,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.28), blurRadius: 50)],
                        ),
                        child: Image.asset('assets/images/memoriae_logo.webp', fit: BoxFit.contain),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'MEMORIAE',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 6, color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'PHOTOBOOTH & CAMERA RENTAL',
                        style: TextStyle(fontSize: 10.5, letterSpacing: 3, color: Colors.white.withValues(alpha: 0.55)),
                      ),
                      if (wide) const SizedBox(height: 36) else const Spacer(flex: 2),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.fromLTRB(24, 26, 24, wide ? 22 : 16 + MediaQuery.paddingOf(context).bottom),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: wide ? BorderRadius.circular(32) : const BorderRadius.vertical(top: Radius.circular(32)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Capture the moment.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: AppColors.stone900),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Book a photobooth or rent a camera for your next event.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.stone500),
                            ),
                            const SizedBox(height: 22),
                            SizedBox(
                              height: 54,
                              child: FilledButton(
                                onPressed: _enterLogin,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  foregroundColor: AppColors.onAccent,
                                  shape: const StadiumBorder(),
                                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('Log in'),
                                    SizedBox(width: 8),
                                    Icon(Icons.arrow_forward_rounded, size: 18),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 54,
                              child: OutlinedButton(
                                onPressed: _enterRegister,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.stone900,
                                  side: const BorderSide(color: AppColors.border, width: 1.2),
                                  shape: const StadiumBorder(),
                                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                ),
                                child: const Text('Create account'),
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextButton(
                              onPressed: _enterGuest,
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.stone500,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              child: const Text('Browse as guest'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
