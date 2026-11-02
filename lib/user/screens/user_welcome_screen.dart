import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import '../widgets/app_toast.dart';

/// ===============================================================
/// MEMORIAE USER WELCOME SCREEN
/// ===============================================================
///
/// Single-file editorial landing screen.
/// Uses the existing Memoriae AppColors from:
///   ../theme/app_colors.dart
///
/// IMPORTANT:
/// - Do NOT define AppColors again in this file.
/// - Do NOT define AppColors.highlight; it does not exist in the
///   supplied Memoriae palette.
/// - This screen only uses the existing AppColors tokens.
///

class UserWelcomeScreen extends StatefulWidget {
  const UserWelcomeScreen({super.key});

  @override
  State<UserWelcomeScreen> createState() => _UserWelcomeScreenState();
}

class _UserWelcomeScreenState extends State<UserWelcomeScreen> {
  final GlobalKey _experienceKey = GlobalKey();
  final GlobalKey _pricingKey = GlobalKey();
  final GlobalKey _footerKey = GlobalKey();

  int _experienceIndex = 0;
  int _tierIndex = 0;

  static const List<(String, int, String)> _tiers = [
    ('Daily', 1200, '/ day'),
    ('Weekly', 6800, '/ week'),
    ('Monthly', 18000, '/ month'),
  ];

  void _enterHome() {
    Navigator.of(context).pushReplacementNamed('/');
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

  void _enterBook() {
    Navigator.of(context).pushReplacementNamed('/book');
  }

  void _enterRent() {
    Navigator.of(context).pushReplacementNamed('/rent');
  }

  void _scrollTo(GlobalKey key) {
    final targetContext = key.currentContext;
    if (targetContext == null) return;

    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brandCream,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isWide = constraints.maxWidth >= 900;

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    isWide: isWide,
                    onExperience: () => _scrollTo(_experienceKey),
                    onPricing: () => _scrollTo(_pricingKey),
                    onLocation: () => _scrollTo(_footerKey),
                    onBook: _enterHome,
                    onLogin: _enterLogin,
                    onRegister: _enterRegister,
                    onGuest: _enterGuest,
                  ),

                  const _Rule(),

                  _RevealOnScroll(
                    child: _EditorialHero(
                      isWide: isWide,
                      onBook: _enterHome,
                      onRent: _enterRent,
                    ),
                  ),

                  const _Rule(),

                  _RevealOnScroll(
                    child: _EditorialStatement(
                      isWide: isWide,
                    ),
                  ),

                  const _Rule(),

                  Container(
                    key: _experienceKey,
                    color: AppColors.surfaceGrey,
                    child: _RevealOnScroll(
                      child: _EditorialExperience(
                        isWide: isWide,
                        selected: _experienceIndex,
                        onSelect: (index) {
                          setState(() => _experienceIndex = index);
                        },
                      ),
                    ),
                  ),

                  const _Rule(),

                  _RevealOnScroll(
                    child: _EditorialValue(
                      isWide: isWide,
                    ),
                  ),

                  const _Rule(),

                  Container(
                    key: _pricingKey,
                    color: AppColors.accent,
                    child: _RevealOnScroll(
                      child: _EditorialPricing(
                        isWide: isWide,
                        tiers: _tiers,
                        tierIndex: _tierIndex,
                        onTierChanged: (index) {
                          setState(() => _tierIndex = index);
                        },
                      ),
                    ),
                  ),

                  const _Rule(),

                  Container(
                    color: AppColors.surfaceGrey,
                    child: _RevealOnScroll(
                      child: _EditorialProcess(
                        isWide: isWide,
                      ),
                    ),
                  ),

                  const _Rule(),

                  _RevealOnScroll(
                    child: _EditorialTestimonials(
                      isWide: isWide,
                    ),
                  ),

                  const _Rule(),

                  _RevealOnScroll(
                    child: _EditorialCTA(
                      isWide: isWide,
                      onBook: _enterBook,
                      onRent: _enterRent,
                    ),
                  ),

                  const _Rule(),

                  Container(
                    key: _footerKey,
                    child: _RevealOnScroll(
                      offset: 20,
                      child: _MemoriaeFooter(
                        onBook: _enterBook,
                        onRent: _enterRent,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// ===============================================================
/// LOCAL SHADOW TOKENS
/// ===============================================================

class _MemoriaeShadows {
  const _MemoriaeShadows._();

  static final List<BoxShadow> phone = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.12),
      blurRadius: 50,
      offset: const Offset(0, 20),
    ),
  ];

  static final List<BoxShadow> smallAccent = [
    BoxShadow(
      color: AppColors.accent.withValues(alpha: 0.20),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];
}

/// ===============================================================
/// SCROLL REVEAL
/// ===============================================================

class _RevealOnScroll extends StatefulWidget {
  const _RevealOnScroll({
    required this.child,
    this.offset = 30,
  }) : delay = Duration.zero;

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  State<_RevealOnScroll> createState() => _RevealOnScrollState();
}

class _RevealOnScrollState extends State<_RevealOnScroll>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  ScrollPosition? _position;
  bool _triggered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final newPosition = Scrollable.maybeOf(context)?.position;

    if (newPosition != _position) {
      _position?.removeListener(_checkVisibility);
      _position = newPosition;
      _position?.addListener(_checkVisibility);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkVisibility();
      });
    }
  }

  void _checkVisibility() {
    if (_triggered || !mounted) return;

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return;

    final screenHeight = MediaQuery.sizeOf(context).height;
    final top = renderObject.localToGlobal(Offset.zero).dy;

    if (top < screenHeight * 0.88) {
      _triggered = true;
      _position?.removeListener(_checkVisibility);

      if (widget.delay == Duration.zero) {
        _controller.forward();
      } else {
        Future.delayed(widget.delay, () {
          if (mounted) _controller.forward();
        });
      }
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_checkVisibility);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return Opacity(
          opacity: _fade.value,
          child: Transform.translate(
            offset: Offset(
              0,
              widget.offset * (1 - _fade.value),
            ),
            child: child,
          ),
        );
      },
    );
  }
}

/// ===============================================================
/// RULE
/// ===============================================================

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: AppColors.border,
    );
  }
}

/// ===============================================================
/// TOP AUTH BAR
/// ===============================================================

class _AuthDot extends StatelessWidget {
  const _AuthDot();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        width: 3,
        height: 3,
        decoration: const BoxDecoration(
          color: AppColors.stone400,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _AuthLink extends StatelessWidget {
  const _AuthLink({
    required this.label,
    required this.onTap,
    this.compact = false,
    this.emphasized = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool compact;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: compact ? 11 : 13,
            fontWeight: FontWeight.w700,
            color: emphasized ? AppColors.accent : AppColors.stone900,
          ),
        ),
      ),
    );
  }
}

/// ===============================================================
/// HEADER
/// ===============================================================

class _Header extends StatelessWidget {
  const _Header({
    required this.isWide,
    required this.onExperience,
    required this.onPricing,
    required this.onLocation,
    required this.onBook,
    required this.onLogin,
    required this.onRegister,
    required this.onGuest,
  });

  final bool isWide;
  final VoidCallback onExperience;
  final VoidCallback onPricing;
  final VoidCallback onLocation;
  final VoidCallback onBook;
  final VoidCallback onLogin;
  final VoidCallback onRegister;
  final VoidCallback onGuest;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 40 : 18,
        vertical: 16,
      ),
      child: Row(
        children: [
          const _BrandMark(),

          const Spacer(),

          if (isWide) ...[
            _NavLink(
              label: 'Experience',
              onTap: onExperience,
            ),
            _NavLink(
              label: 'Pricing',
              onTap: onPricing,
            ),
            _NavLink(
              label: 'Location',
              onTap: onLocation,
            ),
            const SizedBox(width: 18),
          ],

          _AuthLink(
            label: 'Log In',
            compact: !isWide,
            onTap: onLogin,
          ),
          const _AuthDot(),
          _AuthLink(
            label: 'Register',
            compact: !isWide,
            onTap: onRegister,
          ),
          const _AuthDot(),
          _AuthLink(
            label: 'Guest',
            compact: !isWide,
            emphasized: true,
            onTap: onGuest,
          ),

          SizedBox(width: isWide ? 16 : 10),

          _PillButton(
            label: 'Book Now',
            onTap: onBook,
            filled: true,
            compact: true,
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 31,
          height: 31,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(
            Icons.camera_alt_outlined,
            size: 16,
            color: AppColors.brandCream,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'memoriae',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: AppColors.stone900,
          ),
        ),
      ],
    );
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        onTap: onTap,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.stone900,
          ),
        ),
      ),
    );
  }
}

/// ===============================================================
/// HERO
/// ===============================================================

class _EditorialHero extends StatelessWidget {
  const _EditorialHero({
    required this.isWide,
    required this.onBook,
    required this.onRent,
  });

  final bool isWide;
  final VoidCallback onBook;
  final VoidCallback onRent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isWide ? 40 : 18,
        isWide ? 54 : 28,
        isWide ? 40 : 18,
        isWide ? 82 : 52,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Text(
                  'AN EXPERIENCE\nWORTH KEEPING',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.8,
                    color: AppColors.stone500,
                  ),
                ),
              ),
              Text(
                'CALAUAN · LAGUNA',
                style: TextStyle(
                  fontSize: isWide ? 11 : 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppColors.stone400,
                ),
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
              color: AppColors.stone900,
            ),
          ),

          const SizedBox(height: 22),

          Container(
            height: 1,
            color: AppColors.stone900,
          ),

          const SizedBox(height: 28),

          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Expanded(
                  flex: 7,
                  child: Text(
                    'BOOK THE MOMENT.\nKEEP THE MEMORY.',
                    style: TextStyle(
                      fontSize: 59,
                      height: .90,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -2.5,
                      color: AppColors.stone900,
                    ),
                  ),
                ),
                const SizedBox(width: 70),
                Expanded(
                  flex: 3,
                  child: _HeroCopy(
                    onBook: onBook,
                    onRent: onRent,
                  ),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'BOOK THE MOMENT.\nKEEP THE MEMORY.',
                  style: TextStyle(
                    fontSize: 38,
                    height: .92,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.4,
                    color: AppColors.stone900,
                  ),
                ),
                const SizedBox(height: 26),
                _HeroCopy(
                  onBook: onBook,
                  onRent: onRent,
                ),
              ],
            ),

          const SizedBox(height: 55),

          _HeroVisual(isWide: isWide),
        ],
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({
    required this.onBook,
    required this.onRent,
  });

  final VoidCallback onBook;
  final VoidCallback onRent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Photobooths, camera rentals, and unforgettable setups — '
          'designed to make booking feel effortless.',
          style: TextStyle(
            fontSize: 14,
            height: 1.7,
            color: AppColors.stone500,
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _PillButton(
              label: 'Book Now',
              onTap: onBook,
              filled: true,
            ),
            _PillButton(
              label: 'Explore Rentals',
              onTap: onRent,
              outlined: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroVisual extends StatefulWidget {
  const _HeroVisual({
    required this.isWide,
  });

  final bool isWide;

  @override
  State<_HeroVisual> createState() => _HeroVisualState();
}

class _HeroVisualState extends State<_HeroVisual>
    with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat();

  late final AnimationController _shutterController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  late final Animation<double> _shutterFlash = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 0.0, end: 0.85)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 30,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 0.85, end: 0.0)
          .chain(CurveTween(curve: Curves.easeIn)),
      weight: 70,
    ),
  ]).animate(_shutterController);

  late final Animation<double> _shutterScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 0.88)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 25,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 0.88, end: 1.0)
          .chain(CurveTween(curve: Curves.elasticOut)),
      weight: 75,
    ),
  ]).animate(_shutterController);

  void _takeSnapshot() {
    if (_shutterController.isAnimating) return;
    HapticFeedback.mediumImpact();
    _shutterController.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    _shutterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double phoneWidth = widget.isWide ? 175 : 122;
    final double redWidth = widget.isWide ? 255 : 158;
    final double redHeight = widget.isWide ? 355 : 235;

    return AspectRatio(
      aspectRatio: widget.isWide ? 2.08 : 1.10,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final double move =
                math.sin(_controller.value * math.pi * 2) * 7;

            return Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: AppColors.stone900,
                ),

                Positioned(
                  left: widget.isWide ? 38 : 20,
                  top: widget.isWide ? 32 : 23,
                  child: const Text(
                    '01',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandCream,
                    ),
                  ),
                ),

                Positioned(
                  left: widget.isWide ? 38 : 20,
                  bottom: widget.isWide ? 32 : 23,
                  child: const Text(
                    'THE MEMORIAE EXPERIENCE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: AppColors.brandCream,
                    ),
                  ),
                ),

                Positioned(
                  right: widget.isWide ? 66 : 22,
                  bottom: -move,
                  child: GestureDetector(
                    onTap: _takeSnapshot,
                    child: AnimatedBuilder(
                      animation: _shutterController,
                      builder: (context, shutterChild) {
                        return Transform.scale(
                          scale: _shutterScale.value,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              shutterChild!,
                              IgnorePointer(
                                child: Container(
                                  width: redWidth,
                                  height: redHeight,
                                  color: AppColors.brandCream.withValues(
                                    alpha: _shutterFlash.value,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      child: Container(
                        width: redWidth,
                        height: redHeight,
                        color: AppColors.accent,
                        child: Center(
                          child: Icon(
                            Icons.camera_alt_outlined,
                            size: widget.isWide ? 104 : 64,
                            color: AppColors.brandCream,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                Positioned(
                  right: widget.isWide ? 415 : 150,
                  top: 69 + move,
                  child: Text(
                    'CAPTURE',
                    style: TextStyle(
                      fontSize: widget.isWide ? 25 : 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandCream,
                    ),
                  ),
                ),

                Positioned(
                  right: widget.isWide ? 354 : 112,
                  top: 104 + move,
                  child: Text(
                    'WHAT MATTERS.',
                    style: TextStyle(
                      fontSize: widget.isWide ? 25 : 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accent,
                    ),
                  ),
                ),

                Positioned(
                  left: widget.isWide ? 175 : 28,
                  bottom: widget.isWide ? 52 : 30,
                  child: Transform.rotate(
                    angle: -0.07,
                    child: _MiniPhone(width: phoneWidth),
                  ),
                ),

                if (!widget.isWide)
                  Positioned(
                    right: 22,
                    bottom: -move + redHeight + 8,
                    child: AnimatedOpacity(
                      opacity: _shutterController.isAnimating ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: const Text(
                        'TAP TO CAPTURE',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: AppColors.stone400,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// ===============================================================
/// MINI PHONE
/// ===============================================================

class _MiniPhone extends StatelessWidget {
  const _MiniPhone({
    required this.width,
  });

  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.stone900,
        borderRadius: BorderRadius.circular(26),
        boxShadow: _MemoriaeShadows.phone,
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.brandCream,
          borderRadius: BorderRadius.circular(19),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '9:41',
                  style: TextStyle(
                    fontSize: 7,
                    color: AppColors.stone500,
                  ),
                ),
                Text(
                  '●●●',
                  style: TextStyle(
                    fontSize: 7,
                    color: AppColors.stone500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              color: AppColors.accent,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MEMORIAE',
                    style: TextStyle(
                      fontSize: 6,
                      letterSpacing: 1,
                      color: AppColors.brandCream,
                    ),
                  ),
                  SizedBox(height: 7),
                  Text(
                    'Golden Hour',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandCream,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'SAT · 3:00 PM',
                    style: TextStyle(
                      fontSize: 6.5,
                      color: AppColors.brandCream,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Recent booking',
                style: TextStyle(
                  fontSize: 7.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.stone900,
                ),
              ),
            ),
            const SizedBox(height: 7),
            Container(
              height: 29,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              color: AppColors.surfaceGrey,
              child: const Row(
                children: [
                  Icon(
                    Icons.camera_alt_outlined,
                    size: 11,
                    color: AppColors.accent,
                  ),
                  SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Camera Rental',
                      style: TextStyle(
                        fontSize: 7,
                        color: AppColors.stone900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===============================================================
/// STATEMENT
/// ===============================================================

class _EditorialStatement extends StatelessWidget {
  const _EditorialStatement({
    required this.isWide,
  });

  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 40 : 18,
        vertical: isWide ? 108 : 64,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MEMORIES',
            style: TextStyle(
              fontSize: isWide ? 120 : 55,
              height: .80,
              letterSpacing: isWide ? -6 : -3,
              fontWeight: FontWeight.w800,
              color: AppColors.accent,
            ),
          ),
          Text(
            'ARE THE\nPRODUCT.',
            style: TextStyle(
              fontSize: isWide ? 120 : 55,
              height: .80,
              letterSpacing: isWide ? -6 : -3,
              fontWeight: FontWeight.w800,
              color: AppColors.stone900,
            ),
          ),
          const SizedBox(height: 40),
          Container(
            height: 1,
            color: AppColors.border,
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                width: 55,
                child: Text(
                  '01',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Everything we build is centered around one thing: '
                  'making it easier to create moments worth remembering.',
                  style: TextStyle(
                    fontSize: isWide ? 19 : 15,
                    height: 1.65,
                    color: AppColors.stone500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ===============================================================
/// EXPERIENCE
/// ===============================================================

class _EditorialExperience extends StatelessWidget {
  const _EditorialExperience({
    required this.isWide,
    required this.selected,
    required this.onSelect,
  });

  final bool isWide;
  final int selected;
  final ValueChanged<int> onSelect;

  static const List<(String, String, String)> _items = [
    (
      '01',
      'BOOK',
      'Choose your date, package, and setup in minutes.',
    ),
    (
      '02',
      'CAPTURE',
      'Our equipment and crew arrive ready for the moment.',
    ),
    (
      '03',
      'REMEMBER',
      'You leave with memories, not logistical headaches.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 40 : 18,
        vertical: isWide ? 98 : 55,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'THE EXPERIENCE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: AppColors.stone500,
            ),
          ),
          const SizedBox(height: 17),
          Text(
            'Simple by design.\nMemorable by nature.',
            style: TextStyle(
              fontSize: isWide ? 62 : 38,
              height: .95,
              letterSpacing: -1.5,
              fontWeight: FontWeight.w800,
              color: AppColors.stone900,
            ),
          ),
          const SizedBox(height: 55),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  flex: 5,
                  child: _ExperienceVisual(),
                ),
                const SizedBox(width: 70),
                Expanded(
                  flex: 4,
                  child: _ExperienceList(
                    selected: selected,
                    onSelect: onSelect,
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                const _ExperienceVisual(),
                const SizedBox(height: 35),
                _ExperienceList(
                  selected: selected,
                  onSelect: onSelect,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ExperienceVisual extends StatefulWidget {
  const _ExperienceVisual();

  @override
  State<_ExperienceVisual> createState() => _ExperienceVisualState();
}

class _ExperienceVisualState extends State<_ExperienceVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double angle =
            math.sin(_controller.value * math.pi * 2) * .02;

        return SizedBox(
          height: 520,
          child: Stack(
            children: [
              Container(
                color: AppColors.stone900,
              ),
              const Positioned(
                left: 30,
                top: 30,
                child: Text(
                  'MEMORIAE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: AppColors.brandCream,
                  ),
                ),
              ),
              const Positioned(
                left: 30,
                bottom: 30,
                child: Text(
                  'MAKE IT\nCOUNT.',
                  style: TextStyle(
                    fontSize: 46,
                    height: .88,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandCream,
                  ),
                ),
              ),
              Positioned(
                top: 68,
                right: 44,
                child: Transform.rotate(
                  angle: angle,
                  child: Container(
                    width: 182,
                    height: 312,
                    color: AppColors.accent,
                    child: const Center(
                      child: Icon(
                        Icons.camera_alt_outlined,
                        size: 76,
                        color: AppColors.brandCream,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExperienceList extends StatelessWidget {
  const _ExperienceList({
    required this.selected,
    required this.onSelect,
  });

  final int selected;
  final ValueChanged<int> onSelect;

  static const List<(String, String, String)> _items = [
    (
      '01',
      'BOOK',
      'Choose your date, package, and setup in minutes.',
    ),
    (
      '02',
      'CAPTURE',
      'Our equipment and crew arrive ready for the moment.',
    ),
    (
      '03',
      'REMEMBER',
      'You leave with memories, not logistical headaches.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < _items.length; i++)
          _ExperienceRow(
            number: _items[i].$1,
            title: _items[i].$2,
            description: _items[i].$3,
            active: selected == i,
            isLast: i == _items.length - 1,
            onTap: () => onSelect(i),
          ),
      ],
    );
  }
}

class _ExperienceRow extends StatelessWidget {
  const _ExperienceRow({
    required this.number,
    required this.title,
    required this.description,
    required this.active,
    required this.isLast,
    required this.onTap,
  });

  final String number;
  final String title;
  final String description;
  final bool active;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 23),
        decoration: BoxDecoration(
          border: Border(
            top: const BorderSide(
              color: AppColors.border,
            ),
            bottom: isLast
                ? const BorderSide(
                    color: AppColors.border,
                  )
                : BorderSide.none,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 50,
              child: Text(
                number,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.w800,
                      color: AppColors.stone900,
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: active
                        ? Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              description,
                              style: const TextStyle(
                                fontSize: 13.5,
                                height: 1.6,
                                color: AppColors.stone500,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            AnimatedRotation(
              turns: active ? .125 : 0,
              duration: const Duration(milliseconds: 250),
              child: const Icon(
                Icons.add,
                color: AppColors.stone900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===============================================================
/// VALUE
/// ===============================================================

class _EditorialValue extends StatelessWidget {
  const _EditorialValue({
    required this.isWide,
  });

  final bool isWide;

  static const List<(String, String, String)> _values = [
    (
      '01',
      'Instant',
      'Book directly without waiting for a reply.',
    ),
    (
      '02',
      'Transparent',
      'See the full price before you confirm.',
    ),
    (
      '03',
      'Flexible',
      'Rent for the day, week, or month.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 40 : 18,
        vertical: isWide ? 95 : 55,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WHY MEMORIAE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: AppColors.stone500,
            ),
          ),
          const SizedBox(height: 17),
          Text(
            'Less arranging.\nMore remembering.',
            style: TextStyle(
              fontSize: isWide ? 65 : 40,
              height: .93,
              letterSpacing: -1.6,
              fontWeight: FontWeight.w800,
              color: AppColors.stone900,
            ),
          ),
          const SizedBox(height: 55),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final value in _values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 35),
                      child: _ValueItem(value: value),
                    ),
                  ),
              ],
            )
          else
            Column(
              children: [
                for (final value in _values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: _ValueItem(value: value),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ValueItem extends StatelessWidget {
  const _ValueItem({
    required this.value,
  });

  final (String, String, String) value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 1,
          color: AppColors.stone900,
        ),
        const SizedBox(height: 17),
        Text(
          value.$1,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(height: 29),
        Text(
          value.$2,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: AppColors.stone900,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          value.$3,
          style: const TextStyle(
            fontSize: 13,
            height: 1.6,
            color: AppColors.stone500,
          ),
        ),
      ],
    );
  }
}

/// ===============================================================
/// PRICING
/// ===============================================================

class _EditorialPricing extends StatelessWidget {
  const _EditorialPricing({
    required this.isWide,
    required this.tiers,
    required this.tierIndex,
    required this.onTierChanged,
  });

  final bool isWide;
  final List<(String, int, String)> tiers;
  final int tierIndex;
  final ValueChanged<int> onTierChanged;

  @override
  Widget build(BuildContext context) {
    final tier = tiers[tierIndex];

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 40 : 18,
        vertical: isWide ? 100 : 55,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PRICING',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: AppColors.brandCream,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Choose your\nkind of moment.',
            style: TextStyle(
              fontSize: isWide ? 76 : 47,
              height: .90,
              letterSpacing: -2,
              fontWeight: FontWeight.w800,
              color: AppColors.brandCream,
            ),
          ),
          const SizedBox(height: 55),
          Container(
            padding: EdgeInsets.all(isWide ? 40 : 24),
            color: AppColors.brandCream,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (int i = 0; i < tiers.length; i++)
                      GestureDetector(
                        onTap: () => onTierChanged(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: i == tierIndex
                                ? AppColors.accent
                                : AppColors.brandCream,
                            border: Border.all(
                              color: AppColors.accent,
                            ),
                          ),
                          child: Text(
                            tiers[i].$1,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: i == tierIndex
                                  ? AppColors.brandCream
                                  : AppColors.accent,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 55),
                Text(
                  '₱${tier.$2}',
                  style: TextStyle(
                    fontSize: isWide ? 94 : 60,
                    height: .84,
                    letterSpacing: -4,
                    fontWeight: FontWeight.w800,
                    color: AppColors.stone900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tier.$3,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.stone500,
                  ),
                ),
                const SizedBox(height: 30),
                Container(
                  height: 1,
                  color: AppColors.border,
                ),
                const SizedBox(height: 24),
                const _PricingLine(
                  text: 'DSLR body + 2 lenses',
                ),
                const _PricingLine(
                  text: 'Tripod & memory cards',
                ),
                const _PricingLine(
                  text: 'Insurance included',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PricingLine extends StatelessWidget {
  const _PricingLine({
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(
            Icons.check,
            size: 16,
            color: AppColors.accent,
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.stone500,
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================================================
/// PROCESS
/// ===============================================================

class _EditorialProcess extends StatelessWidget {
  const _EditorialProcess({
    required this.isWide,
  });

  final bool isWide;

  static const List<(String, String, String)> _steps = [
    (
      '01',
      'SELECT',
      'Choose your date and package.',
    ),
    (
      '02',
      'CONFIRM',
      'Pay securely and receive instant confirmation.',
    ),
    (
      '03',
      'CAPTURE',
      'Pick up your gear or let our crew set up.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 40 : 18,
        vertical: isWide ? 100 : 55,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'THE PROCESS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: AppColors.stone500,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Three steps.\nNo friction.',
            style: TextStyle(
              fontSize: isWide ? 68 : 43,
              height: .92,
              letterSpacing: -2,
              fontWeight: FontWeight.w800,
              color: AppColors.stone900,
            ),
          ),
          const SizedBox(height: 55),
          for (final step in _steps)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: AppColors.border,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 55,
                    child: Text(
                      step.$1,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.$2,
                          style: TextStyle(
                            fontSize: isWide ? 32 : 25,
                            fontWeight: FontWeight.w800,
                            color: AppColors.stone900,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          step.$3,
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.55,
                            color: AppColors.stone500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Container(
            height: 1,
            color: AppColors.border,
          ),
          const SizedBox(height: 45),
          if (isWide)
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'FROM BOOKING\nTO MEMORY.',
                    style: TextStyle(
                      fontSize: 44,
                      height: .90,
                      fontWeight: FontWeight.w800,
                      color: AppColors.stone900,
                    ),
                  ),
                ),
                SizedBox(width: 50),
                Expanded(
                  child: _BookingConfirmation(),
                ),
              ],
            )
          else
            const _BookingConfirmation(),
        ],
      ),
    );
  }
}

class _BookingConfirmation extends StatelessWidget {
  const _BookingConfirmation();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(25),
      color: AppColors.brandCream,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 35,
            color: AppColors.accent,
          ),
          SizedBox(height: 15),
          Text(
            'BOOKING CONFIRMED',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
              color: AppColors.stone500,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Golden Hour Package',
            style: TextStyle(
              fontSize: 24,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w700,
              color: AppColors.stone900,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Saturday · 3:00 PM',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.stone500,
            ),
          ),
          SizedBox(height: 20),
          Divider(
            height: 1,
            color: AppColors.border,
          ),
          SizedBox(height: 18),
          Text(
            'Your crew arrives 30 minutes early for setup.',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppColors.stone500,
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================================================
/// TESTIMONIALS
/// ===============================================================

class _EditorialTestimonials extends StatelessWidget {
  const _EditorialTestimonials({
    required this.isWide,
  });

  final bool isWide;

  static const List<(String, String, String)> _reviews = [
    (
      '“Booked our photobooth two days before the event and the crew still showed up early.”',
      'Tom Cat',
      'Debut · Calauan',
    ),
    (
      '“The weekly rate actually saved me money versus renting day by day elsewhere.”',
      'Jerry Mouse',
      'Freelance photographer',
    ),
    (
      '“What I saw at checkout is what I paid on the day.”',
      'SpongeBob SquarePants',
      'Wedding coordinator',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 40 : 18,
        vertical: isWide ? 100 : 55,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TESTIMONIALS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: AppColors.stone500,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'The moments\nspeak for themselves.',
            style: TextStyle(
              fontSize: isWide ? 67 : 42,
              height: .92,
              letterSpacing: -1.5,
              fontWeight: FontWeight.w800,
              color: AppColors.stone900,
            ),
          ),
          const SizedBox(height: 55),
          for (int i = 0; i < _reviews.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: _TestimonialBlock(
                review: _reviews[i],
                accent: i == 1,
              ),
            ),
        ],
      ),
    );
  }
}

class _TestimonialBlock extends StatelessWidget {
  const _TestimonialBlock({
    required this.review,
    required this.accent,
  });

  final (String, String, String) review;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 25,
        vertical: 30,
      ),
      color: accent ? AppColors.accent : AppColors.surfaceGrey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            review.$1,
            style: TextStyle(
              fontSize: 27,
              height: 1.15,
              fontFamily: 'Georgia',
              fontStyle: FontStyle.italic,
              color: accent
                  ? AppColors.brandCream
                  : AppColors.stone900,
            ),
          ),
          const SizedBox(height: 25),
          Text(
            review.$2.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: accent
                  ? AppColors.brandCream
                  : AppColors.accent,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            review.$3,
            style: TextStyle(
              fontSize: 11,
              color: accent
                  ? AppColors.brandCream
                  : AppColors.stone500,
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================================================
/// CTA
/// ===============================================================

class _EditorialCTA extends StatelessWidget {
  const _EditorialCTA({
    required this.isWide,
    required this.onBook,
    required this.onRent,
  });

  final bool isWide;
  final VoidCallback onBook;
  final VoidCallback onRent;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.stone900,
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 40 : 18,
        vertical: isWide ? 110 : 65,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'READY WHEN\nYOU ARE.',
            style: TextStyle(
              fontSize: isWide ? 100 : 58,
              height: .83,
              letterSpacing: -4,
              fontWeight: FontWeight.w800,
              color: AppColors.brandCream,
            ),
          ),
          const SizedBox(height: 35),
          Container(
            height: 1,
            color: AppColors.stone400,
          ),
          const SizedBox(height: 25),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Expanded(
                  child: Text(
                    'Your next memory starts with a booking.',
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.5,
                      color: AppColors.stone400,
                    ),
                  ),
                ),
                Row(
                  children: [
                    _PillButton(
                      label: 'Book Now',
                      onTap: onBook,
                      filled: true,
                      darkOnDark: true,
                    ),
                    const SizedBox(width: 10),
                    _PillButton(
                      label: 'Rent Gear',
                      onTap: onRent,
                      outlined: true,
                      darkOnDark: true,
                    ),
                  ],
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your next memory starts with a booking.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: AppColors.stone400,
                  ),
                ),
                const SizedBox(height: 25),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _PillButton(
                      label: 'Book Now',
                      onTap: onBook,
                      filled: true,
                      darkOnDark: true,
                    ),
                    _PillButton(
                      label: 'Rent Gear',
                      onTap: onRent,
                      outlined: true,
                      darkOnDark: true,
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// ===============================================================
/// FOOTER
/// ===============================================================

class _MemoriaeFooter extends StatelessWidget {
  const _MemoriaeFooter({
    required this.onBook,
    required this.onRent,
  });

  final VoidCallback onBook;
  final VoidCallback onRent;

  void _showComingSoon(BuildContext context, String label) {
    AppToast.show(context, '$label — coming soon.', duration: const Duration(seconds: 2));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.stone900,
      padding: const EdgeInsets.fromLTRB(
        40,
        70,
        40,
        35,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool isWide = constraints.maxWidth >= 800;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Text(
                    'memoriae',
                    style: TextStyle(
                      fontSize: isWide ? 120 : 70,
                      height: .80,
                      letterSpacing: -5,
                      fontFamily: 'Georgia',
                      fontWeight: FontWeight.w500,
                      color: AppColors.brandCream.withValues(
                        alpha: .08,
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 0,
                    bottom: 0,
                    child: Text(
                      'MEMORIAE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: AppColors.brandCream,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 55),
              Container(
                height: 1,
                color: AppColors.stone500,
              ),
              const SizedBox(height: 35),
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      flex: 2,
                      child: _FooterIntro(),
                    ),
                    const SizedBox(width: 70),
                    Expanded(
                      child: _FooterColumn(
                        title: 'SERVICES',
                        children: [
                          _FooterLink(
                            label: 'Photobooth',
                            onTap: onBook,
                          ),
                          _FooterLink(
                            label: 'Camera Rentals',
                            onTap: onRent,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _FooterColumn(
                        title: 'COMPANY',
                        children: [
                          _FooterLink(
                            label: 'About',
                            onTap: () => _showComingSoon(context, 'About'),
                          ),
                          _FooterLink(
                            label: 'Location',
                            onTap: () => _showComingSoon(
                              context,
                              'CALAUAN · LAGUNA',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _FooterColumn(
                        title: 'SUPPORT',
                        children: [
                          _FooterLink(
                            label: 'Help Center',
                            onTap: () =>
                                _showComingSoon(context, 'Help Center'),
                          ),
                          _FooterLink(
                            label: 'Contact',
                            onTap: () => _showComingSoon(context, 'Contact'),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FooterIntro(),
                    const SizedBox(height: 40),
                    _FooterColumn(
                      title: 'SERVICES',
                      children: [
                        _FooterLink(
                          label: 'Photobooth',
                          onTap: onBook,
                        ),
                        _FooterLink(
                          label: 'Camera Rentals',
                          onTap: onRent,
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    _FooterColumn(
                      title: 'COMPANY',
                      children: [
                        _FooterLink(
                          label: 'About',
                          onTap: () => _showComingSoon(context, 'About'),
                        ),
                        _FooterLink(
                          label: 'Location',
                          onTap: () => _showComingSoon(
                            context,
                            'CALAUAN · LAGUNA',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    _FooterColumn(
                      title: 'SUPPORT',
                      children: [
                        _FooterLink(
                          label: 'Help Center',
                          onTap: () =>
                              _showComingSoon(context, 'Help Center'),
                        ),
                        _FooterLink(
                          label: 'Contact',
                          onTap: () => _showComingSoon(context, 'Contact'),
                        ),
                      ],
                    ),
                  ],
                ),
              const SizedBox(height: 60),
              Container(
                height: 1,
                color: AppColors.stone500,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '© ${DateTime.now().year} Memoriae',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.stone400,
                      ),
                    ),
                  ),
                  const Text(
                    'CALAUAN · LAGUNA',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: AppColors.stone400,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FooterIntro extends StatelessWidget {
  const _FooterIntro();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Capture what matters.\nKeep it forever.',
          style: TextStyle(
            fontSize: 24,
            height: 1.1,
            fontFamily: 'Georgia',
            color: AppColors.brandCream,
          ),
        ),
        SizedBox(height: 14),
        SizedBox(
          width: 300,
          child: Text(
            'Photobooths and camera rentals made simple for '
            'the moments that matter.',
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: AppColors.stone400,
            ),
          ),
        ),
      ],
    );
  }
}

class _FooterColumn extends StatelessWidget {
  const _FooterColumn({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: AppColors.brandCream,
          ),
        ),
        const SizedBox(height: 18),
        ...children,
      ],
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: InkWell(
        onTap: onTap,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.stone400,
          ),
        ),
      ),
    );
  }
}

/// ===============================================================
/// BUTTON
/// ===============================================================

class _PillButton extends StatefulWidget {
  const _PillButton({
    required this.label,
    required this.onTap,
    this.filled = false,
    this.outlined = false,
    this.compact = false,
    this.darkOnDark = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;
  final bool outlined;
  final bool compact;
  final bool darkOnDark;

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    Color background;
    Color textColor;
    Color borderColor;

    if (widget.darkOnDark) {
      background = widget.filled
          ? AppColors.brandCream
          : Colors.transparent;

      textColor = widget.filled
          ? AppColors.stone900
          : AppColors.brandCream;

      borderColor = AppColors.brandCream;
    } else if (widget.filled) {
      background = _hovered
          ? AppColors.accent
          : AppColors.stone900;

      textColor = AppColors.brandCream;
      borderColor = background;
    } else {
      background = Colors.transparent;
      textColor = AppColors.stone900;
      borderColor = AppColors.border;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hovered = true);
      },
      onExit: (_) {
        setState(() => _hovered = false);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 16 : 20,
            vertical: widget.compact ? 9 : 12,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            border: widget.outlined || widget.darkOnDark
                ? Border.all(
                    color: borderColor,
                  )
                : null,
            boxShadow: _hovered && widget.filled
                ? _MemoriaeShadows.smallAccent
                : const [],
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: widget.compact ? 12 : 13,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}