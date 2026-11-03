import 'dart:typed_data';
import 'dart:ui' show ImageFilter;
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/booth_package.dart';
import '../models/feedback_record.dart';
import '../services/auth_service.dart';
import '../services/booking_repository.dart';
import '../services/feedback_repository.dart';
import '../services/pricing_repository.dart' show decodeDataUriImage, PricingRepository;
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/announcement_banner.dart';
import '../widgets/notification_bell.dart';
import '../widgets/profile_avatar.dart';
import 'info_pages.dart';
import 'my_bookings_screen.dart';

// ---------------------------------------------------------------------------
// iOS building blocks
// ---------------------------------------------------------------------------

/// iOS-style "continuous" (squircle) corners. [ContinuousRectangleBorder]
/// reads about half as round as a circular radius, hence the doubling.
ShapeBorder _squircle(double radius, {BorderSide side = BorderSide.none}) =>
    ContinuousRectangleBorder(borderRadius: BorderRadius.circular(radius * 2), side: side);

/// Tap feedback the way iOS does it: the control dims and shrinks slightly
/// while pressed (no Material ripple) and gives a light haptic on release.
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  const _Pressable({required this.child, required this.onTap, this.pressedScale = 0.97});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapUp: widget.onTap == null ? null : (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _down ? 0.7 : 1,
          duration: const Duration(milliseconds: 120),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Wraps a [BoothPackage] — live from Admin → Pricing when available, the
/// static [kPackages] port otherwise — with the cosmetic "Popular / Best
/// Value / Premium" caption the card shows. The caption is assigned by
/// position rather than baked into the data, so it still makes sense
/// whatever Admin has actually added.
class _FeaturedPackage {
  final BoothPackage pkg;
  final String tag;
  const _FeaturedPackage({required this.pkg, required this.tag});

  String get id => pkg.id;
  String get name => pkg.name;
  String get duration => pkg.duration;
  int get price => pkg.price;
  /// Description if Admin wrote one, otherwise the first feature.
  String get description => pkg.description.isNotEmpty ? pkg.description : (pkg.features.isNotEmpty ? pkg.features.first : '');
}

const List<String> _kTags = ["Popular", "Best Value", "Premium"];

List<_FeaturedPackage> _decoratePackages(List<BoothPackage> pkgs) {
  return [
    for (var i = 0; i < pkgs.length; i++)
      _FeaturedPackage(pkg: pkgs[i], tag: i < _kTags.length ? _kTags[i] : "Featured"),
  ];
}

/// Home tab, iOS style: App Store "Today"-like header (date caption + large
/// title), grouped-grey background, frosted bar that fades in on scroll,
/// squircle cards, SF-style icons and press feedback, large photo cards for
/// the packages, and Settings-style grouped lists further down.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _searchPackageId; // null = "All"
  DateTime? _searchDate;
  final int _guests = 1;
  String _query = '';
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  // Package carousel: its own controller so the page dots can follow it.
  final ScrollController _carousel = ScrollController();
  int _carouselIndex = 0;
  // The carousel loops forever: it starts far from offset 0 so the user can
  // keep swiping past the last package and land on the first one again.
  bool _carouselPositioned = false;
  bool _scrolled = false;

  // Decoded package photos, cached so typing in the search box doesn't
  // re-decode every base64 image on each keystroke.
  final Map<String, Uint8List?> _photoCache = {};

  // Current user, used to drive the greeting, the notification bell and the
  // "you're approved" banner below.
  String? _uid;
  String? _name;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final scrolled = _scroll.hasClients && _scroll.offset > 64;
      if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    });
    _carousel.addListener(() {
      if (!_carousel.hasClients) return;
      final idx = (_carousel.offset / _cardStep).round();
      if (idx != _carouselIndex) setState(() => _carouselIndex = idx);
    });
    AuthService.instance.me().then((u) {
      if (mounted) {
        setState(() {
          _uid = u?.uid;
          _name = u?.fullName;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scroll.dispose();
    _carousel.dispose();
    super.dispose();
  }

  Uint8List? _photo(String url) => _photoCache.putIfAbsent(url, () => decodeDataUriImage(url));

  String get _firstName {
    var n = (_name ?? '').trim();
    if (n.contains('@')) n = n.split('@').first;
    return n.isEmpty ? '' : n.split(RegExp(r'\s+')).first;
  }

  String get _initials {
    var n = (_name ?? '').trim();
    if (n.contains('@')) n = n.split('@').first;
    final parts = n.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// Maroon on light; a lighter maroon tint on the dark theme.
  Color _accentText(BuildContext context) => AppColors.accentText(context);

  void _goToBooking(BuildContext context, {DateTime? date, BoothPackage? pkg, int? guests}) {
    Navigator.of(context).pushReplacementNamed(
      '/book',
      arguments: BookingIntent(date: date, package: pkg, guests: guests),
    );
  }

  Future<void> _pickSearchDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      context: context,
      initialDate: _searchDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 180)),
    );
    if (picked != null) setState(() => _searchDate = picked);
  }

  void _goToContact(BuildContext context) {
    // Routes into the real "Chat with Staff" thread (Messages tab) rather
    // than a separate contact form — reuses the messaging system that
    // already exists instead of building a second, parallel one.
    Navigator.of(context).pushReplacementNamed('/messages');
  }

  void _openFooterLink(BuildContext context, String label) {
    switch (label) {
      case "FAQs":
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FaqScreen()));
        break;
      case "Cancellation Policy":
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const PolicyScreen(title: "Cancellation Policy", sections: kCancellationPolicySections),
        ));
        break;
      case "Terms of Service":
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const PolicyScreen(title: "Terms of Service", sections: kTermsOfServiceSections),
        ));
        break;
      case "Privacy Policy":
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const PolicyScreen(title: "Privacy Policy", sections: kPrivacyPolicySections, lastUpdated: kPrivacyPolicyLastUpdated),
        ));
        break;
      case "Contact":
        _goToContact(context);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Live from Admin → Pricing so a photo/price Admin just added shows up
    // here immediately; falls back to the static kPackages port only until
    // Admin has added a package (see PricingRepository.watchPackages).
    return StreamBuilder<List<BoothPackage>>(
      stream: PricingRepository.watchPackages(),
      builder: (context, snapshot) {
        final allPackages = (snapshot.data == null || snapshot.data!.isEmpty) ? kPackages : snapshot.data!;
        final featured = _decoratePackages(allPackages);
        final q = _query.trim().toLowerCase();
        final visible = featured.where((p) {
          if (_searchPackageId != null && p.id != _searchPackageId) return false;
          if (q.isNotEmpty && !p.name.toLowerCase().contains(q)) return false;
          return true;
        }).toList();
        final loading = snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData;
        final body = _buildBody(context, featured, visible, loading: loading);

        // The photos live in Firestore. If nothing arrives (no connection,
        // blocked, or truly empty) the app silently shows the default list
        // without photos - so say so, instead of leaving people guessing.
        String? liveDataProblem;
        if (snapshot.hasError) {
          liveDataProblem = "Couldn't load live packages: ${snapshot.error}";
        } else if (snapshot.connectionState == ConnectionState.active &&
            (snapshot.data == null || snapshot.data!.isEmpty)) {
          liveDataProblem = "No live package data received - showing default packages (no photos).";
        }
        if (liveDataProblem == null) return body;
        return Stack(
          fit: StackFit.expand,
          children: [
            body,
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                color: const Color(0xFFFFF3CD),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    liveDataProblem,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF664D03)),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, List<_FeaturedPackage> all, List<_FeaturedPackage> visible, {bool loading = false}) {
    const sidePad = EdgeInsets.symmetric(horizontal: 20);
    return Stack(
      children: [
        SingleChildScrollView(
          controller: _scroll,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(top: 12, bottom: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: sidePad,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _reveal(0, _buildHeader(context)),
                    const SizedBox(height: 18),
                    _reveal(1, _buildHeroBanner(context)),
                    const SizedBox(height: 18),
                    const AnnouncementBanner(),
                    _buildApprovalBanner(context),
                    _buildNextBooking(context),
                    _reveal(1, _buildSearchRow(context)),
                    const SizedBox(height: 30),
                    _buildSectionHeader(
                      context,
                      "Packages",
                      action: "See All",
                      onAction: () => _goToBooking(context, date: _searchDate, guests: _guests),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              _buildPackageChips(context, all),
              const SizedBox(height: 18),
              if (loading)
                _buildPackageSkeleton(context)
              else if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
                  child: Column(
                    children: [
                      Icon(CupertinoIcons.search, size: 34, color: AppPalette.textMuted(context)),
                      const SizedBox(height: 10),
                      Text("No packages match that search.", style: TextStyle(fontSize: 15, color: AppPalette.textMuted(context))),
                    ],
                  ),
                )
              else
                _buildPackageCarousel(context, visible),
              const SizedBox(height: 24),
              Padding(
                padding: sidePad,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHowItWorks(context),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              _buildTestimonial(context),
              const SizedBox(height: 30),
              Padding(
                padding: sidePad,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSecondaryCtas(context),
                    const SizedBox(height: 24),
                    _buildFooterList(context),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: _buildCollapsedBar(context)),
      ],
    );
  }

  // --- Small shared pieces -----------------------------------------------

  /// Fades + slides a section up when the screen first appears.
  Widget _reveal(int order, Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 450 + order * 90),
      curve: Curves.easeOutCubic,
      builder: (context, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 16 * (1 - t)), child: c),
      ),
      child: child,
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, {String? action, VoidCallback? onAction}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: AppPalette.textPrimary(context)),
          ),
        ),
        if (action != null)
          _Pressable(
            onTap: onAction,
            child: Text(action, style: TextStyle(fontSize: 16, color: _accentText(context))),
          ),
      ],
    );
  }

  /// Small grey caption above a grouped list, as in iOS Settings.
  Widget _groupLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 13, letterSpacing: 0.2, color: AppPalette.textMuted(context)),
      ),
    );
  }

  /// White (or dark-grey) rounded card holding [rows], separated by inset
  /// hairlines — iOS "inset grouped" list.
  Widget _groupedCard(BuildContext context, List<Widget> rows, {double separatorInset = 16}) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(shape: _squircle(12), color: AppPalette.groupedCard(context)),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Padding(
                padding: EdgeInsets.only(left: separatorInset),
                child: Container(height: 0.5, color: AppPalette.separator(context)),
              ),
            rows[i],
          ],
        ],
      ),
    );
  }

  /// Frosted top bar with the app name; fades in once the large title has
  /// scrolled out of view.
  Widget _buildCollapsedBar(BuildContext context) {
    return IgnorePointer(
      ignoring: !_scrolled,
      child: AnimatedOpacity(
        opacity: _scrolled ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppPalette.groupedBg(context).withValues(alpha: 0.78),
                border: Border(bottom: BorderSide(color: AppPalette.separator(context), width: 0.5)),
              ),
              child: Text(
                "Memoriae",
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Header (App Store "Today" style) ------------------------------------

  Widget _buildHeader(BuildContext context) {
    final initials = _initials;
    final first = _firstName;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _Pressable(
          onTap: () => Navigator.of(context).pushReplacementNamed('/profile'),
          child: ProfileAvatar(
            size: 46,
            color: AppColors.accent,
            fallback: initials.isEmpty
                ? const Icon(CupertinoIcons.person_fill, color: AppColors.onAccent, size: 20)
                : Text(initials, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.onAccent)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Welcome back",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppPalette.textMuted(context)),
              ),
              const SizedBox(height: 1),
              Text(
                first.isEmpty ? "Guest" : first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: AppPalette.textPrimary(context)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        NotificationBell(userId: _uid, background: AppPalette.groupedCard(context)),
      ],
    );
  }

  /// Big feature card under the header ("Explore new collection" in the
  /// reference design) - jumps straight into booking.
  Widget _buildHeroBanner(BuildContext context) {
    return _Pressable(
      onTap: () => _goToBooking(context, date: _searchDate, guests: _guests),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
        decoration: BoxDecoration(
          gradient: AppGradients.card,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Capture your\nbest moments",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -0.4, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: const ShapeDecoration(shape: StadiumBorder(), color: Colors.white),
                    child: const Text(
                      "Book now",
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 86,
              height: 86,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              ),
              child: const Icon(CupertinoIcons.camera_fill, size: 38, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  // --- Search -------------------------------------------------------------

  Widget _buildSearchRow(BuildContext context) {
    final hasDate = _searchDate != null;
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: ShapeDecoration(shape: _squircle(11), color: AppPalette.fill(context).withValues(alpha: 0.7)),
            child: Row(
              children: [
                Icon(CupertinoIcons.search, size: 18, color: AppPalette.textMuted(context)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    textInputAction: TextInputAction.search,
                    cursorColor: AppColors.accent,
                    style: TextStyle(fontSize: 17, color: AppPalette.textPrimary(context)),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: "Search packages",
                      hintStyle: TextStyle(fontSize: 17, color: AppPalette.textMuted(context)),
                    ),
                  ),
                ),
                if (_query.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                    child: Icon(CupertinoIcons.xmark_circle_fill, size: 17, color: AppPalette.textMuted(context)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        _Pressable(
          onTap: _pickSearchDate,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 42,
            padding: EdgeInsets.symmetric(horizontal: hasDate ? 14 : 13),
            decoration: ShapeDecoration(
              shape: hasDate ? const StadiumBorder() : _squircle(11),
              color: hasDate ? AppColors.accent : AppPalette.groupedCard(context),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.calendar, size: 19, color: hasDate ? AppColors.onAccent : _accentText(context)),
                if (hasDate) ...[
                  const SizedBox(width: 6),
                  Text(
                    DateFormat('MMM d').format(_searchDate!),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.onAccent),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _searchDate = null),
                    child: const Icon(CupertinoIcons.xmark_circle_fill, size: 16, color: AppColors.onAccent),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- Next booking (widget-style card) -----------------------------------

  /// Soonest confirmed / pending booking, front and centre. Renders nothing
  /// when the customer has no upcoming booking.
  Widget _buildNextBooking(BuildContext context) {
    if (_uid == null) return const SizedBox.shrink();
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: BookingRepository.watchBookingsForUser(_uid!),
      builder: (context, snap) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        Map<String, dynamic>? next;
        DateTime? nextDate;
        for (final b in snap.data ?? const <Map<String, dynamic>>[]) {
          final status = b['status'] as String? ?? '';
          if (status != 'confirmed' && status != 'pending_confirmation') continue;
          final ts = b['date'];
          if (ts is! Timestamp) continue;
          final d = ts.toDate();
          if (d.isBefore(today)) continue;
          if (nextDate == null || d.isBefore(nextDate)) {
            next = b;
            nextDate = d;
          }
        }
        if (next == null || nextDate == null) return const SizedBox.shrink();

        final booking = next;
        final date = nextDate;
        final days = DateTime(date.year, date.month, date.day).difference(today).inDays;
        final when = days == 0 ? "Today" : (days == 1 ? "Tomorrow" : "In $days days");
        final confirmed = booking['status'] == 'confirmed';
        final time = booking['time'] as String? ?? '';
        final packageName = booking['packageName'] as String? ?? 'Booking';

        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: _Pressable(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyBookingsScreen())),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: ShapeDecoration(
                shape: _squircle(22),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF8A2429), Color(0xFF3A1214)],
                ),
                shadows: [BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: ShapeDecoration(shape: _squircle(13), color: Colors.white.withValues(alpha: 0.16)),
                    child: Column(
                      children: [
                        Text(
                          DateFormat('MMM').format(date).toUpperCase(),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: Colors.white70),
                        ),
                        Text(
                          DateFormat('d').format(date),
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.05, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          confirmed ? "NEXT BOOKING · CONFIRMED" : "NEXT BOOKING · PENDING",
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: Colors.white60),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          packageName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: Colors.white),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          time.isEmpty ? when : '$when · $time',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const Icon(CupertinoIcons.chevron_right, size: 18, color: Colors.white54),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // --- Package chips + App Store style cards --------------------------------

  Widget _buildPackageChips(BuildContext context, List<_FeaturedPackage> all) {
    Widget chip(String label, bool selected, VoidCallback onTap) {
      return _Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: selected ? AppColors.accent : AppPalette.groupedCard(context),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: selected ? AppColors.onAccent : AppPalette.textPrimary(context)),
          ),
        ),
      );
    }

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: all.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == 0) return chip("All", _searchPackageId == null, () => setState(() => _searchPackageId = null));
          final p = all[i - 1];
          final selected = _searchPackageId == p.id;
          return chip(p.name, selected, () => setState(() => _searchPackageId = selected ? null : p.id));
        },
      ),
    );
  }

  /// Gray placeholder cards shown while the live packages are still loading,
  /// so the layout doesn't jump when the real cards arrive.
  Widget _buildPackageSkeleton(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cardWidth = (width * 0.82).clamp(280.0, 340.0).toDouble();
    final block = AppPalette.surface(context);

    Widget bar(double factor, double height) => FractionallySizedBox(
          widthFactor: factor,
          alignment: Alignment.centerLeft,
          child: Container(
            height: height,
            decoration: ShapeDecoration(shape: _squircle(height / 2), color: block),
          ),
        );

    return SizedBox(
      height: 424,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        itemCount: 2,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) => SizedBox(
          width: cardWidth,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: ShapeDecoration(shape: _squircle(22), color: block.withValues(alpha: 0.6)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: Container(color: block)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(0.85, 12),
                      const SizedBox(height: 8),
                      bar(0.55, 12),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: ShapeDecoration(shape: _squircle(11), color: block),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: bar(0.5, 14)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Width of one card plus the gap after it, used to turn scroll offset
  /// into the index of the card that is currently in front.
  double get _cardStep {
    final width = MediaQuery.of(context).size.width;
    return (width * 0.82).clamp(280.0, 340.0).toDouble() + 14;
  }

  Widget _buildPackageCarousel(BuildContext context, List<_FeaturedPackage> items) {
    final cardWidth = _cardStep - 14;
    final n = items.length;
    final loop = n > 1;
    final active = n == 0 ? 0 : _carouselIndex % n;
    if (loop && !_carouselPositioned) {
      _carouselPositioned = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_carousel.hasClients) return;
        _carousel.jumpTo(n * 1000 * _cardStep);
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 424,
          child: ListView.builder(
            controller: _carousel,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            // null itemCount (when there is more than one package) = endless
            // list, so after the last card it wraps to the first.
            itemCount: loop ? null : n,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(right: 14),
              child: SizedBox(width: cardWidth, child: _buildPackageCard(context, items[i % n], hero: !loop || (i >= _carouselIndex && i < _carouselIndex + n))),
            ),
          ),
        ),
        // Page dots: one per package, the one in front is a longer pill.
        if (items.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < items.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == active ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == active
                        ? _accentText(context)
                        : AppPalette.textMuted(context).withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  /// Large photo card in the style of the App Store's Today cards: caption
  /// and title over the photo, a frosted bar along the bottom with the
  /// duration, price and a capsule "BOOK" button.
  Widget _buildPackageCard(BuildContext context, _FeaturedPackage p, {bool hero = true}) {
    final photo = _photo(p.pkg.imageUrl);
    const panelColor = Color(0xFF2E2A26);

    return _Pressable(
      onTap: () => _goToBooking(context, pkg: p.pkg, date: _searchDate, guests: _guests),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: ShapeDecoration(
          shape: _squircle(22),
          color: panelColor,
          shadows: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 26, offset: const Offset(0, 12))],
        ),
        child: Column(
          children: [
            // Poster area: the photo keeps its full artwork and only the
            // title sits on top of it, so nothing covers the price text.
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (photo != null)
                    (hero
                        ? Hero(tag: 'pkg-photo-${p.id}', child: Image.memory(photo, fit: BoxFit.cover))
                        : Image.memory(photo, fit: BoxFit.cover))
                  else
                    DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF93292E), Color(0xFF2E2A26)],
                        ),
                      ),
                      child: Center(child: Icon(CupertinoIcons.camera_fill, size: 72, color: Colors.white.withValues(alpha: 0.14))),
                    ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 120,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black.withValues(alpha: 0.5), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    top: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: ShapeDecoration(shape: const StadiumBorder(), color: AppColors.accent),
                          child: Text(
                            p.tag.toUpperCase(),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: AppColors.onAccent),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          p.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 1.08, letterSpacing: -0.8, color: AppColors.onAccent),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Solid info panel: description on top, then duration/price/BOOK.
            Container(
              width: double.infinity,
              color: panelColor,
              padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p.description.isNotEmpty) ...[
                    Text(
                      p.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, height: 1.3, color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        clipBehavior: Clip.antiAlias,
                        alignment: Alignment.center,
                        decoration: ShapeDecoration(shape: _squircle(11), color: AppColors.accent),
                        child: photo != null
                            ? Image.memory(photo, width: 44, height: 44, fit: BoxFit.cover)
                            : const Icon(CupertinoIcons.camera_fill, size: 20, color: AppColors.onAccent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              p.duration,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                            const SizedBox(height: 1),
                            Text(formatPeso(p.price), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFE57F84))),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        decoration: ShapeDecoration(shape: const StadiumBorder(), color: Colors.white.withValues(alpha: 0.92)),
                        child: const Text("BOOK", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.accent)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Trust stats ---------------------------------------------------------

  // --- Approval banner ----------------------------------------------------

  /// Dashboard banner that surfaces the moment staff approve (or decline)
  /// a booking — the same `notifyCustomer` bookings the bell badges, just
  /// shown inline so it can't be missed even before anyone taps the bell.
  /// Only ever shows the single most recent one; older ones are still
  /// reachable from the bell. Dismissing (or tapping into My Bookings)
  /// clears it via `markNotificationSeen`, same as the bell sheet.
  Widget _buildApprovalBanner(BuildContext context) {
    if (_uid == null) return const SizedBox.shrink();
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: BookingRepository.watchNotifications(_uid!),
      builder: (context, snap) {
        final notifications = snap.data ?? const <Map<String, dynamic>>[];
        if (notifications.isEmpty) return const SizedBox.shrink();
        final latest = notifications.first;

        final status = latest['status'] as String? ?? '';
        final rescheduled = (latest['notifyType'] as String? ?? '') == 'rescheduled';
        final refunded = (latest['notifyType'] as String? ?? '') == 'refunded';
        final refundAmount = (latest['refundAmount'] as num?)?.toInt() ?? 0;
        final approved = status == 'confirmed';
        final color = (refunded || approved) ? const Color(0xFF2E7D32) : (rescheduled ? const Color(0xFF1565C0) : const Color(0xFFB3261E));
        final packageName = latest['packageName'] as String? ?? 'Booking';
        final time = latest['time'] as String? ?? '';
        final ts = latest['date'];
        final date = ts is Timestamp ? ts.toDate() : null;
        final id = latest['id'] as String?;

        final Color gradLight = refunded
            ? const Color(0xFF2FA36F)
            : approved
                ? const Color(0xFF43A047)
                : rescheduled
                    ? const Color(0xFF1E88E5)
                    : const Color(0xFFD64545);
        final Color gradDark = refunded
            ? const Color(0xFF15603F)
            : approved
                ? const Color(0xFF1B5E20)
                : rescheduled
                    ? const Color(0xFF0D47A1)
                    : const Color(0xFF8E1C1C);
        final IconData statusIcon = refunded
            ? Icons.payments_rounded
            : (rescheduled ? Icons.event_repeat_rounded : (approved ? Icons.verified_rounded : Icons.cancel_rounded));
        final String title = refunded
            ? "Your refund was sent"
            : (rescheduled ? "Your schedule was moved" : (approved ? "You're approved!" : "Booking declined"));
        final String pill = refunded ? 'REFUNDED' : (rescheduled ? 'RESCHEDULED' : (approved ? 'CONFIRMED' : 'DECLINED'));
        final String message = refunded
            ? "${formatPeso(refundAmount)} was sent to your GCash."
            : (rescheduled
                ? "Your event was moved to a new date. Please check the details below."
                : (approved
                    ? "Your booking is confirmed. We can't wait to capture your moments!"
                    : "Sorry, we couldn't accept this booking. Open My Bookings for details."));
        final String? dateText = date != null ? DateFormat('EEE, MMM d, yyyy').format(date) : null;

        Widget chip(IconData icon, String text) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context)),
                    ),
                  ),
                ],
              ),
            );

        void dismiss() {
          if (id != null) BookingRepository.markNotificationSeen(id);
        }

        void open() {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyBookingsScreen()));
          dismiss();
        }

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: child),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppPalette.cardBg(context),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: color.withValues(alpha: 0.25)),
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.20), blurRadius: 24, offset: const Offset(0, 10))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [gradLight, gradDark]),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -8,
                          bottom: -22,
                          child: Icon(statusIcon, size: 100, color: Colors.white.withValues(alpha: 0.10)),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.20),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                              ),
                              child: Icon(statusIcon, color: Colors.white, size: 28),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(20)),
                                    child: Text(
                                      pill,
                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: Colors.white),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    title,
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.2),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: dismiss,
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.18)),
                                child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message,
                          style: TextStyle(fontSize: 13, height: 1.45, color: AppPalette.textSecondary(context)),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            chip(Icons.photo_camera_outlined, packageName),
                            if (dateText != null) chip(Icons.event_outlined, dateText),
                            if (time.isNotEmpty) chip(Icons.schedule_rounded, time),
                            if (refunded && refundAmount > 0) chip(Icons.payments_outlined, formatPeso(refundAmount)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 44,
                          child: ElevatedButton(
                            onPressed: open,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: color,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: const StadiumBorder(),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('View My Bookings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                SizedBox(width: 8),
                                Icon(Icons.arrow_forward_rounded, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // --- How it works (Settings-style list) -----------------------------------

  Widget _buildHowItWorks(BuildContext context) {
    final steps = [
      (CupertinoIcons.square_grid_2x2_fill, AppColors.accent, "Choose a package", "Pick the duration and add-ons that fit your event"),
      (CupertinoIcons.calendar, const Color(0xFFC9962E), "Pick date & time", "Reserve a slot that works for your schedule"),
      (CupertinoIcons.checkmark_seal_fill, const Color(0xFF34C759), "Confirm & pay", "Upload your receipt and you're booked"),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _groupLabel(context, "How it works"),
        _groupedCard(
          context,
          [
            for (final (icon, color, title, desc) in steps)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(shape: _squircle(8), color: color),
                      child: Icon(icon, size: 18, color: AppColors.onAccent),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppPalette.textPrimary(context))),
                          const SizedBox(height: 1),
                          Text(desc, style: TextStyle(fontSize: 13, height: 1.3, color: AppPalette.textMuted(context))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
          separatorInset: 64,
        ),
      ],
    );
  }

  // --- Reviews ------------------------------------------------------------

  Widget _buildTestimonial(BuildContext context) {
    return StreamBuilder<List<FeedbackRecord>>(
      stream: FeedbackRepository.watchTopReviews(limit: 5),
      builder: (context, snapshot) {
        final reviews = snapshot.data ?? const <FeedbackRecord>[];
        // (quote, byline, stars) — real reviews when there are any,
        // otherwise a single placeholder so the section never looks empty.
        final items = reviews.isNotEmpty
            ? [for (final r in reviews) ('"${r.comment}"', '${r.customerName} · ${r.packageName}', r.rating)]
            : [('"Booking took two minutes and the booth attendant made our debut unforgettable."', 'Jana D. · Premium Celebration', 5)];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildSectionHeader(context, "What customers say"),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final (quote, byline, stars) = items[i];
                  final initial = byline.isEmpty ? '?' : byline[0].toUpperCase();
                  return Container(
                    width: 280,
                    padding: const EdgeInsets.all(18),
                    decoration: ShapeDecoration(shape: _squircle(16), color: AppPalette.groupedCard(context)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: List.generate(
                            5,
                            (k) => Icon(
                              CupertinoIcons.star_fill,
                              size: 14,
                              color: k < stars ? const Color(0xFFFFB400) : AppPalette.separator(context),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: Text(
                            quote,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, height: 1.4, color: AppPalette.textPrimary(context)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: AppColors.accentTint(0.12), shape: BoxShape.circle),
                              child: Text(initial, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _accentText(context))),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                byline,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.lock_fill, size: 12, color: AppPalette.textMuted(context)),
                  const SizedBox(width: 6),
                  Text("Secure GCash payment · Verified receipts only", style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // --- CTAs + footer ------------------------------------------------------

  Widget _buildSecondaryCtas(BuildContext context) {
    Widget button(String label, Color bg, Color fg, VoidCallback onTap) {
      return Expanded(
        child: _Pressable(
          onTap: onTap,
          child: Container(
            height: 50,
            alignment: Alignment.center,
            decoration: ShapeDecoration(shape: _squircle(14), color: bg),
            child: Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: fg)),
          ),
        ),
      );
    }

    return Row(
      children: [
        button("All Packages", AppColors.accent, Colors.white, () => _goToBooking(context, date: _searchDate, guests: _guests)),
        const SizedBox(width: 12),
        button("Contact Us", AppColors.accentTint(0.12), _accentText(context), () => _goToContact(context)),
      ],
    );
  }

  Widget _buildFooterList(BuildContext context) {
    const links = ["FAQs", "Cancellation Policy", "Terms of Service", "Privacy Policy", "Contact"];
    return _groupedCard(
      context,
      [
        for (final label in links)
          _Pressable(
            pressedScale: 1,
            onTap: () => _openFooterLink(context, label),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: TextStyle(fontSize: 16, color: AppPalette.textPrimary(context)))),
                  Icon(CupertinoIcons.chevron_right, size: 15, color: AppPalette.textMuted(context)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}