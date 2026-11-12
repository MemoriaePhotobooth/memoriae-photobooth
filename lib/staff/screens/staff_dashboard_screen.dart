import 'refund_requests_screen.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/booking_record.dart';
import '../models/camera_rental_record.dart';
import '../services/auth_service.dart';
import '../services/booking_repository.dart';
import '../services/camera_rental_repository.dart';
import '../services/staff_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/dashboard_kit.dart';
import '../widgets/glass_bottom_nav.dart';
import '../widgets/more_menu_sheet.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/refunds_to_send.dart';
import '../widgets/refund_decision_dialog.dart';
import 'staff_announcements_screen.dart';
import 'staff_calendar_screen.dart';
import 'staff_camera_rentals_screen.dart';
import 'staff_event_photos_screen.dart';
import 'staff_feedback_screen.dart';
import 'staff_login_screen.dart';
import 'staff_messages_screen.dart';
import 'staff_pos_screen.dart';
import 'staff_profile_screen.dart';
import 'staff_settings_screen.dart';
import 'staff_walkin_booking_screen.dart';
import 'staff_loyalty_link_screen.dart';
import '../widgets/floating_chat_bubble.dart';

/// Records that a pending refund has been sent back to the customer,
/// attributed to the signed-in staff member.
Future<void> _staffMarkRefunded(String bookingId) async {
  final staffId = AuthService.instance.currentUid;
  final staffName = await AuthService.instance.currentStaffDisplayName();
  await BookingRepository.markRefunded(bookingId, staffId: staffId, staffName: staffName);
}

/// Sections that get their own slot in the phone's floating bottom nav.
/// Kept to 4 (+ a trailing "More" tab) so the pill never gets cramped on a
/// 360px-wide phone; Calendar / Feedback / News and the account pages open
/// from the "More" sheet ([_openMoreMenu]). To promote/demote a section,
/// edit this list and [_kStaffNavTabs] together — same order in both.
const List<_StaffSection> _kStaffPrimarySections = [
  _StaffSection.bookings,
  _StaffSection.cameraRentals,
  _StaffSection.pos,
  _StaffSection.messages,
];

/// Tabs for the floating glass bottom nav: one per entry in
/// [_kStaffPrimarySections], then [kMoreNavTab].
const List<NavTabItem> _kStaffNavTabs = [
  NavTabItem(icon: Icons.event_note_outlined, activeIcon: Icons.event_note, label: "Bookings"),
  NavTabItem(icon: Icons.camera_alt_outlined, activeIcon: Icons.camera_alt, label: "Rentals"),
  NavTabItem(icon: Icons.point_of_sale_outlined, activeIcon: Icons.point_of_sale, label: "POS"),
  NavTabItem(icon: Icons.chat_bubble_outline, activeIcon: Icons.chat_bubble, label: "Messages"),
  kMoreNavTab,
];

/// Every section the staff app can open. On desktop they're all in the
/// sidebar; on phones the ones in [_kStaffPrimarySections] are bottom-nav
/// tabs and the rest live in the "More" sheet — both just set `_section`.
enum _StaffSection { bookings, cameraRentals, pos, calendar, eventPhotos, refundRequests, feedback, messages, announcements, profile, settings }

/// The staff panel. Same Flutter widgets, same codebase, on desktop and
/// mobile — the difference comes from a single `LayoutBuilder` breakpoint.
/// A separate app/project from the customer app and from the Admin app
/// (which additionally has staff management and pricing).
///
/// Wide windows (desktop/web) get a persistent left sidebar (branding, nav,
/// sign out) plus a two-pane master-detail bookings view. Narrow windows
/// (phone) get a plain AppBar + bottom nav and a single list that pushes a
/// detail screen — no sidebar, since there isn't room for one.
class StaffDashboardScreen extends StatefulWidget {
  const StaffDashboardScreen({super.key});

  @override
  State<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends State<StaffDashboardScreen> {
  static const double _desktopBreakpoint = 900;

  _StaffSection _section = _StaffSection.bookings;
  BookingRecord? _selected;

  // Bookings list filter/search/sort state.
  String _statusFilter = 'all';
  bool _sortNewestFirst = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  /// Drives the 15-minute-hold sweep. Bookings the customer never sent a
  /// receipt for get auto-rejected, so they land in this dashboard as
  /// rejected without anyone having to chase them by hand. A scheduled
  /// Cloud Function is the better home for this in production (it keeps
  /// running with no dashboard open) — this timer keeps the behaviour
  /// working while the app is the only thing deployed.
  Timer? _holdSweepTimer;

  /// "New booking alerts" (Settings): watches for bookings that newly need
  /// approval while this dashboard is open and pops up a snackbar.
  StreamSubscription<List<BookingRecord>>? _newBookingSub;
  Set<String>? _knownPendingIds; // null until the first snapshot (baseline)
  final DateTime _sessionStart = DateTime.now();

  /// Locks the person out the moment an admin deactivates or removes them
  /// (see [AuthService.watchAccess]).
  StreamSubscription<bool>? _accessSub;
  bool _kickedOut = false;

  @override
  void initState() {
    super.initState();
    StaffSettings.load(); // no-op if main_staff.dart already loaded it
    _sweepExpiredHolds();
    _holdSweepTimer = Timer.periodic(const Duration(seconds: 30), (_) => _sweepExpiredHolds());
    _listenForNewBookings();
    _accessSub = AuthService.instance.watchAccess().listen((hasAccess) {
      if (!hasAccess) _kickOut();
    }, onError: (_) {});
  }

  Future<void> _kickOut() async {
    if (_kickedOut) return;
    _kickedOut = true;
    await AuthService.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const StaffLoginScreen(notice: "Your access was turned off by an admin. Please contact them if this is a mistake."),
      ),
      (route) => false,
    );
  }

  void _listenForNewBookings() {
    _newBookingSub = BookingRepository.watchAllBookings().listen((bookings) {
      final pending = bookings.where((b) => b.status == 'pending_confirmation').toList();
      final known = _knownPendingIds;
      _knownPendingIds = pending.map((b) => b.id).toSet();
      if (known == null || !mounted) return; // first snapshot = baseline, no alert
      if (!StaffSettings.notifyNewBookings.value) return;
      // Only bookings created after this session started — guards against a
      // cache-then-server snapshot making old bookings look "new".
      final cutoff = _sessionStart.subtract(const Duration(minutes: 1));
      final fresh = pending.where((b) => !known.contains(b.id) && (b.createdAt?.isAfter(cutoff) ?? false)).toList();
      if (fresh.isEmpty) return;
      _announceNewBookings(fresh);
    }, onError: (_) {});
  }

  void _announceNewBookings(List<BookingRecord> fresh) {
    SystemSound.play(SystemSoundType.alert);
    final first = fresh.first;
    final who = first.customerName.trim().isEmpty ? 'a customer' : first.customerName.trim();
    final message = fresh.length == 1 ? "New booking from $who needs approval" : "${fresh.length} new bookings need approval";
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: "View",
          onPressed: () => _goToBooking(first, isDesktop: MediaQuery.of(context).size.width >= _desktopBreakpoint),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _accessSub?.cancel();
    _newBookingSub?.cancel();
    _holdSweepTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _sweepExpiredHolds() async {
    try {
      await BookingRepository.expireStaleHolds();
    } catch (_) {
      // Offline or a transient permission hiccup — the next tick retries.
    }
  }

  List<BookingRecord> _applyFilters(List<BookingRecord> bookings) {
    var list = bookings.where((b) {
      if (_statusFilter != 'all' && b.status != _statusFilter) return false;
      final q = _searchQuery.trim().toLowerCase();
      if (q.isEmpty) return true;
      return b.userId.toLowerCase().contains(q) ||
          b.customerName.toLowerCase().contains(q) ||
          b.bookingRef.toLowerCase().contains(q) ||
          b.id.toLowerCase().contains(q) ||
          b.packageName.toLowerCase().contains(q);
    }).toList();
    list.sort((a, b) {
      final cmp = a.date.compareTo(b.date);
      return _sortNewestFirst ? -cmp : cmp;
    });
    return list;
  }

  Future<void> _logout() async {
    await AuthService.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const StaffLoginScreen()),
    );
  }

  Future<void> _openWalkInBooking() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const StaffWalkInBookingScreen()),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Walk-in booking confirmed and payment logged to POS.")),
      );
    }
  }

  void _goToBooking(BookingRecord booking, {required bool isDesktop}) {
    setState(() {
      _section = _StaffSection.bookings;
      _selected = booking;
    });
    if (!isDesktop) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _StaffBookingDetailScreen(booking: booking)),
      );
    }
  }

  void _goToRentals({required bool isDesktop}) {
    setState(() => _section = _StaffSection.cameraRentals);
  }

  Future<void> _openNotifications({required bool isDesktop}) async {
    if (isDesktop) {
      // Anchored dropdown under the top bar's bell — fades/scales in from
      // the top-right, like the reference design's notification popover,
      // instead of sliding up from the bottom of the whole screen.
      await showGeneralDialog<void>(
        context: context,
        barrierLabel: 'Notifications',
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.05),
        transitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (dialogContext, _, __) {
          // Sits just right of the expanded sidebar card (16px page margin +
          // card width + a small gap), top-aligned with it, instead of
          // covering the sidebar's own icons.
          final screen = MediaQuery.of(dialogContext).size;
          const left = 16 + _StaffSidebar._expandedCard + 12;
          final width = (screen.width - left - 16).clamp(320.0, 420.0).toDouble();
          return SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 16, left: left),
                child: Material(
                  color: Colors.transparent,
                  child: SizedBox(
                    width: width,
                    child: _NotificationsPanel(
                      isDesktop: true,
                      onGoToBooking: (b) {
                        Navigator.of(dialogContext).pop();
                        _goToBooking(b, isDesktop: true);
                      },
                      onGoToRentals: () {
                        Navigator.of(dialogContext).pop();
                        _goToRentals(isDesktop: true);
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        transitionBuilder: (context, anim, __, child) {
          return FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
              alignment: Alignment.topRight,
              child: child,
            ),
          );
        },
      );
      return;
    }

    // Mobile keeps a bottom sheet (a dropdown wouldn't fit a narrow
    // screen), using the same tabs/tiles as the desktop panel.
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: _NotificationsPanel(
            isDesktop: false,
            onGoToBooking: (b) {
              Navigator.of(sheetContext).pop();
              _goToBooking(b, isDesktop: false);
            },
            onGoToRentals: () {
              Navigator.of(sheetContext).pop();
              _goToRentals(isDesktop: false);
            },
          ),
        );
      },
    );
  }

  /// Which bottom-nav slot is lit. Anything that isn't a primary tab is
  /// reached through "More", so that tab lights up instead. Profile/Settings
  /// (opened from the avatar / Profile screen) keep no tab lit.
  int get _bottomNavIndex {
    if (_section == _StaffSection.profile || _section == _StaffSection.settings) return -1;
    final i = _kStaffPrimarySections.indexOf(_section);
    return i >= 0 ? i : _kStaffNavTabs.length - 1;
  }

  void _onBottomNavTap(int i) {
    if (i < _kStaffPrimarySections.length) {
      setState(() => _section = _kStaffPrimarySections[i]);
    } else {
      _openMoreMenu();
    }
  }

  /// Phone-only: the "More" tab's sheet — Calendar, Feedback, News, Profile,
  /// Settings, plus dark mode and sign out (which used to crowd the header).
  /// Tiles switch `_section` just like the desktop sidebar does.
  void _openMoreMenu() {
    MoreMenuItem item(IconData icon, String label, _StaffSection target) => MoreMenuItem(
          icon: icon,
          label: label,
          selected: _section == target,
          onTap: () => setState(() => _section = target),
        );

    showMoreMenuSheet(
      context,
      onLogout: _logout,
      groups: [
        MoreMenuGroup(title: "Tools", items: [
          item(Icons.calendar_month_rounded, "Calendar", _StaffSection.calendar),
          item(Icons.photo_library_rounded, "Event Photos", _StaffSection.eventPhotos),
          item(Icons.undo_rounded, "Refund Requests", _StaffSection.refundRequests),
          item(Icons.star_rounded, "Feedback", _StaffSection.feedback),
          item(Icons.campaign_rounded, "News", _StaffSection.announcements),
        ]),
        MoreMenuGroup(title: "Account", items: [
          item(Icons.person_rounded, "My Profile", _StaffSection.profile),
          item(Icons.settings_rounded, "Settings", _StaffSection.settings),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= _desktopBreakpoint;

        if (isDesktop) {
          return Scaffold(
            backgroundColor: AppPalette.surface(context),
            body: Stack(
              children: [
                Row(
                  children: [
                    // Only the slim icon rail reserves space — the expanded
                    // sidebar floats over the content on hover instead of
                    // pushing it.
                    const SizedBox(width: _StaffSidebar.railWidth),
                    Expanded(
                      child: Column(
                        children: [
                          _StaffTopBar(
                            onSearchSubmitted: (q) => setState(() {
                              _section = _StaffSection.bookings;
                              _searchQuery = q;
                              _searchController.text = q;
                            }),
                            onOpenNotifications: () => _openNotifications(isDesktop: true),
                          ),
                          Expanded(child: _buildSectionArea(context, isDesktop: true)),
                        ],
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: _StaffSidebar(
                    section: _section,
                    onSelectSection: (s) => setState(() => _section = s),
                    onLogout: _logout,
                  ),
                ),
                // Hidden on the Messages section itself, so the same
                // conversation isn't shown twice on screen.
                if (_section != _StaffSection.messages)
                  FloatingChatBubble(
                    onOpenFullMessages: () => setState(() => _section = _StaffSection.messages),
                    bottomOffset: 20,
                  ),
              ],
            ),
          );
        }

        // Mobile: same header/rounded-card language as the customer app's
        // HomeScreen + AppLayoutShell — avatar/title header and a floating
        // glass pill nav. The pill only has 4 primary tabs + "More"; the
        // other sections open from the More sheet (see _openMoreMenu).
        // Sections inside "More" aren't pushed routes, so the system Back
        // button / swipe would otherwise leave the whole dashboard. Back from
        // any other section returns to the first tab (Bookings) instead.
        return PopScope(
          canPop: _section == _StaffSection.bookings,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(() => _section = _StaffSection.bookings);
          },
          child: Scaffold(
            backgroundColor: AppPalette.bg(context),
            body: SafeArea(
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                            child: DashboardHeader(
                              eyebrow: "Welcome back",
                              title: _sectionTitle(_section),
                              initials: "ST",
                              onAvatarTap: () => setState(() => _section = _StaffSection.profile),
                              // Phone header = avatar + title + bell. Dark mode and
                              // sign out moved into the "More" sheet; the logo
                              // badge is dropped so titles get the room.
                              showLogo: false,
                              actions: [
                                DashboardHeaderAction(
                                  icon: Icons.notifications_outlined,
                                  tooltip: "Notifications",
                                  trailingGap: 0,
                                  badge: const _PendingCountBadge(),
                                  onTap: () => _openNotifications(isDesktop: false),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 96),
                              child: _buildSectionArea(context, isDesktop: false),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: GlassBottomNav(
                      tabs: _kStaffNavTabs,
                      currentIndex: _bottomNavIndex,
                      onTap: _onBottomNavTap,
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

  String _sectionTitle(_StaffSection s) {
    switch (s) {
      case _StaffSection.bookings:
        return "Staff Dashboard";
      case _StaffSection.cameraRentals:
        return "Camera Rentals";
      case _StaffSection.pos:
        return "Point of Sale";
      case _StaffSection.calendar:
        return "Calendar";
      case _StaffSection.eventPhotos:
        return "Event Photos";
      case _StaffSection.refundRequests:
        return "Refund Requests";
      case _StaffSection.feedback:
        return "Feedback";
      case _StaffSection.messages:
        return "Messages";
      case _StaffSection.announcements:
        return "Announcements";
      case _StaffSection.profile:
        return "My Profile";
      case _StaffSection.settings:
        return "Settings";
    }
  }

  Widget _buildSectionArea(BuildContext context, {required bool isDesktop}) {
    switch (_section) {
      case _StaffSection.bookings:
        return _buildBookingsArea(context, isDesktop: isDesktop);
      case _StaffSection.cameraRentals:
        return isDesktop
            ? _withDesktopHeader(context, "Camera Rentals", const StaffCameraRentalsScreen())
            : const StaffCameraRentalsScreen();
      case _StaffSection.pos:
        return isDesktop ? _withDesktopHeader(context, null, const StaffPosScreen()) : const StaffPosScreen();
      case _StaffSection.calendar:
        return isDesktop ? _withDesktopHeader(context, "Calendar", const StaffCalendarScreen()) : const StaffCalendarScreen();
      case _StaffSection.eventPhotos:
        return isDesktop
            ? _withDesktopHeader(context, "Event Photos", const StaffEventPhotosScreen())
            : const StaffEventPhotosScreen();
      case _StaffSection.refundRequests:
        return isDesktop
            ? _withDesktopHeader(context, "Refund Requests", const RefundRequestsScreen())
            : const RefundRequestsScreen();
      case _StaffSection.feedback:
        return isDesktop ? _withDesktopHeader(context, "Feedback", const StaffFeedbackScreen()) : const StaffFeedbackScreen();
      case _StaffSection.messages:
        return isDesktop ? _withDesktopHeader(context, "Messages", const StaffMessagesScreen()) : const StaffMessagesScreen();
      case _StaffSection.announcements:
        return isDesktop
            ? _withDesktopHeader(context, "Announcements", const StaffAnnouncementsScreen())
            : const StaffAnnouncementsScreen();
      case _StaffSection.profile:
        final profile = StaffProfileScreen(
          onOpenSettings: () => setState(() => _section = _StaffSection.settings),
          onLogout: _logout,
        );
        return isDesktop ? _withDesktopHeader(context, "My Profile", profile) : profile;
      case _StaffSection.settings:
        final settings = StaffSettingsScreen(
          onChangePassword: () => _showChangePasswordDialog(context),
        );
        return isDesktop ? _withDesktopHeader(context, "Settings", settings) : settings;
    }
  }

  BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppShadows.soft,
        border: Border.all(color: AppPalette.divider(context)),
      );

  /// Every desktop section sits in the same rounded white card on a soft
  /// grey canvas. [title] null = the screen brings its own header (POS).
  Widget _withDesktopHeader(BuildContext context, String? title, Widget child) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 20, 20),
      child: Container(
        decoration: _cardDecoration(context),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            if (title != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
                child: Row(
                  children: [
                    Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppPalette.textPrimary(context))),
                  ],
                ),
              ),
              Divider(height: 1, color: AppPalette.divider(context)),
            ],
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  /// Dashboard-style header for the Bookings landing page — a greeting,
  /// a confirmation-rate ring, two quick-action tiles,
  /// other section, and a "bookings this week" chart + mini calendar
  /// strip. Adapted from a reference design the user provided, restyled
  /// in the app's own maroon palette. The actual booking list/search/
  /// filters stay exactly as they were, directly below this.
  Widget _buildBookingsDashboardHero(BuildContext context, List<BookingRecord> bookings, {required bool isDesktop}) {
    final now = DateTime.now();
    final hour = now.hour;
    final greeting = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening");
    final confirmedCount = bookings.where((b) => b.status == 'confirmed').length;
    final completedCount = bookings.where((b) => b.status == 'completed').length;
    final resolvedCount = confirmedCount + completedCount;
    final progressPct = bookings.isEmpty ? 0.0 : resolvedCount / bookings.length;

    final startOfWeek = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final weekCounts = List<int>.filled(7, 0);
    for (final b in bookings) {
      final d = DateTime(b.date.year, b.date.month, b.date.day);
      final offset = d.difference(startOfWeek).inDays;
      if (offset >= 0 && offset < 7) weekCounts[offset]++;
    }

    final greetingRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FutureBuilder<String>(
                future: AuthService.instance.currentStaffDisplayName(),
                builder: (context, snap) {
                  final name = (snap.data ?? '').trim();
                  final fallback = (AuthService.instance.currentEmail ?? 'there').split('@').first;
                  final shown = name.isNotEmpty ? name.split(' ').first : fallback;
                  return Text(
                    '$greeting, $shown',
                    style: TextStyle(fontSize: isDesktop ? 24 : 20, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppPalette.textPrimary(context)),
                  );
                },
              ),
              const SizedBox(height: 3),
              Text(
                "Here's what's happening with bookings today.",
                style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context)),
              ),
            ],
          ),
        ),
      ],
    );

    final progressRing = _DashboardTileCard(
      child: Column(
        children: [
          SizedBox(
            width: 92,
            height: 92,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 92,
                  height: 92,
                  child: CircularProgressIndicator(
                    value: 1,
                    strokeWidth: 9,
                    strokeCap: StrokeCap.round,
                    color: AppPalette.divider(context),
                  ),
                ),
                SizedBox(
                  width: 92,
                  height: 92,
                  child: CircularProgressIndicator(
                    value: progressPct.clamp(0, 1),
                    strokeWidth: 9,
                    strokeCap: StrokeCap.round,
                    color: AppColors.accent,
                    backgroundColor: Colors.transparent,
                  ),
                ),
                Text('${(progressPct * 100).round()}%', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text("Resolved", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
          Text('$resolvedCount of ${bookings.length} bookings', style: TextStyle(fontSize: 10.5, color: AppPalette.textMuted(context)), textAlign: TextAlign.center),
        ],
      ),
    );

    final walkInTile = _QuickActionTile(
      title: "New Walk-in",
      subtitle: "Book & take payment on the spot",
      buttonLabel: "Start",
      icon: Icons.person_add_alt_1,
      background: AppColors.accent,
      foreground: Colors.white,
      onTap: _openWalkInBooking,
    );

    final posTile = _QuickActionTile(
      title: "Point of Sale",
      subtitle: "Ring up add-ons & rentals",
      buttonLabel: "Open",
      icon: Icons.point_of_sale_rounded,
      background: AppColors.brandCream,
      foreground: AppPalette.textPrimary(context),
      onTap: () => setState(() => _section = _StaffSection.pos),
    );

    final loyaltyTile = _QuickActionTile(
      title: "Loyalty card",
      subtitle: "Link a customer's card for their discount",
      buttonLabel: "Link",
      icon: Icons.card_membership,
      background: AppColors.brandCream,
      foreground: AppPalette.textPrimary(context),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const StaffLoyaltyLinkScreen()),
      ),
    );

    final tileRow = isDesktop
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 168, child: progressRing),
                const SizedBox(width: 14),
                Expanded(child: walkInTile),
                const SizedBox(width: 14),
                Expanded(child: posTile),
              ],
            ),
          )
        : Column(
            children: [
              Row(
                children: [
                  SizedBox(width: 140, child: progressRing),
                  const SizedBox(width: 12),
                  Expanded(child: walkInTile),
                ],
              ),
              const SizedBox(height: 12),
              posTile,
            ],
          );

    final chartCard = _DashboardTileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Bookings this week", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
          const SizedBox(height: 14),
          _WeeklyBookingsChart(counts: weekCounts, startOfWeek: startOfWeek),
        ],
      ),
    );

    final calendarCard = _DashboardTileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(DateFormat('MMMM y').format(now), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => setState(() => _section = _StaffSection.calendar),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text("View", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.accent)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _MiniWeekStrip(startOfWeek: startOfWeek, onDayTap: () => setState(() => _section = _StaffSection.calendar)),
        ],
      ),
    );

    final chartAndCalendarRow = isDesktop
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 2, child: chartCard),
                const SizedBox(width: 14),
                Expanded(child: calendarCard),
              ],
            ),
          )
        : Column(children: [chartCard, const SizedBox(height: 12), calendarCard]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        greetingRow,
        const SizedBox(height: 16),
        tileRow,
        const SizedBox(height: 12),
        loyaltyTile,
        const SizedBox(height: 14),
        chartAndCalendarRow,
      ],
    );
  }

  Widget _buildBookingsArea(BuildContext context, {required bool isDesktop}) {
    return StreamBuilder<List<BookingRecord>>(
      stream: BookingRepository.watchAllBookings(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                "Couldn't load bookings: ${snapshot.error}\n\nThis usually means Firestore security rules aren't deployed yet — see firestore.rules.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppPalette.textMuted(context)),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accent));
        }

        final bookings = snapshot.data!;
        final filtered = _applyFilters(bookings);

        Widget body;
        if (bookings.isEmpty) {
          body = const _BookingsEmpty(
            icon: Icons.event_available_outlined,
            title: "No bookings yet",
            subtitle: "New bookings from customers and walk-ins will show up here.",
          );
        } else if (filtered.isEmpty) {
          body = const _BookingsEmpty(
            icon: Icons.search_off_rounded,
            title: "No bookings match",
            subtitle: "Try a different search or pick another status.",
          );
        } else {
          final list = _BookingList(
            bookings: filtered,
            selectedId: isDesktop ? _selected?.id : null,
            onTap: (b) {
              if (isDesktop) {
                setState(() => _selected = b);
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => _StaffBookingDetailScreen(booking: b)),
                );
              }
            },
          );

          if (!isDesktop) {
            body = list;
          } else {
            final detail = _selected != null
                ? _BookingDetailPane(booking: _selected!)
                : Center(
                    child: Text("Select a booking to view details", style: TextStyle(color: AppPalette.textMuted(context))),
                  );

            body = LayoutBuilder(
              builder: (context, constraints) {
                final listWidth = constraints.maxWidth.clamp(680, double.infinity) * 0.34;
                return Row(
                  children: [
                    SizedBox(width: listWidth.clamp(380, 520), child: list),
                    VerticalDivider(width: 1, color: AppPalette.divider(context)),
                    Expanded(child: detail),
                  ],
                );
              },
            );
          }
        }

        final statusCounts = <String, int>{'all': bookings.length};
        for (final b in bookings) {
          statusCounts[b.status] = (statusCounts[b.status] ?? 0) + 1;
        }
        final filterBar = _BookingFilterBar(
          counts: statusCounts,
          searchController: _searchController,
          onSearchChanged: (q) => setState(() => _searchQuery = q),
          statusFilter: _statusFilter,
          onStatusChanged: (s) => setState(() => _statusFilter = s),
          sortNewestFirst: _sortNewestFirst,
          onToggleSort: () => setState(() => _sortNewestFirst = !_sortNewestFirst),
        );

        if (!isDesktop) {
          // Whole page scrolls so the hero/filters never overflow on short
          // screens; the booking list keeps a sensible minimum height.
          return LayoutBuilder(
            builder: (context, box) {
              final listHeight = box.maxHeight * 0.75 < 420 ? 420.0 : box.maxHeight * 0.75;
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: _buildBookingsDashboardHero(context, bookings, isDesktop: false),
                    ),
                    RefundsToSendBanner(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      onMarkRefunded: (b) => _staffMarkRefunded(b.id),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: filterBar,
                    ),
                    SizedBox(height: listHeight, child: body),
                  ],
                ),
              );
            },
          );
        }

        // Desktop: greeting header, at-a-glance stat tiles, then one big
        // card holding the filters + list/detail split.
        final pending = bookings.where((b) => b.status == 'pending_confirmation').length;
        final confirmed = bookings.where((b) => b.status == 'confirmed').length;
        final completed = bookings.where((b) => b.status == 'completed').length;
        return LayoutBuilder(
          builder: (context, box) {
            // The list card fills the window when there's room, but never
            // shrinks below 560px — the page scrolls instead of overflowing.
            final cardHeight = box.maxHeight - 44 < 560 ? 560.0 : box.maxHeight - 44;
            return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 22, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBookingsDashboardHero(context, bookings, isDesktop: true),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: _StatTile(icon: Icons.event_note_rounded, color: AppColors.accent, value: '${bookings.length}', label: 'Total bookings', active: _statusFilter == 'all', onTap: () => setState(() => _statusFilter = 'all'))),
                  const SizedBox(width: 14),
                  Expanded(child: _StatTile(icon: Icons.hourglass_top_rounded, color: const Color(0xFFB07A2A), value: '$pending', label: 'Pending approval', active: _statusFilter == 'pending_confirmation', onTap: () => setState(() => _statusFilter = 'pending_confirmation'))),
                  const SizedBox(width: 14),
                  Expanded(child: _StatTile(icon: Icons.check_circle_rounded, color: const Color(0xFF2E7D32), value: '$confirmed', label: 'Confirmed', active: _statusFilter == 'confirmed', onTap: () => setState(() => _statusFilter = 'confirmed'))),
                  const SizedBox(width: 14),
                  Expanded(child: _StatTile(icon: Icons.verified_rounded, color: const Color(0xFF1565C0), value: '$completed', label: 'Completed', active: _statusFilter == 'completed', onTap: () => setState(() => _statusFilter = 'completed'))),
                ],
              ),
              const SizedBox(height: 18),
              RefundsToSendBanner(
                padding: const EdgeInsets.only(bottom: 18),
                onMarkRefunded: (b) => _staffMarkRefunded(b.id),
              ),
              SizedBox(
                height: cardHeight,
                child: Container(
                  decoration: _cardDecoration(context),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                        child: Row(
                          children: [
                            Text("All bookings", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.accentTint(0.10), borderRadius: BorderRadius.circular(999)),
                              child: Text('${filtered.length}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.accent)),
                            ),
                          ],
                        ),
                      ),
                      Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 14), child: filterBar),
                      Divider(height: 1, color: AppPalette.divider(context)),
                      Expanded(child: body),
                    ],
                  ),
                ),
              ),
            ],
          ),
            );
          },
        );
      },
    );
  }
}

/// Bell icon with a live badge for how many bookings still need approval.
enum _NotifTab { bookings, rentals }

/// The notifications popover/sheet content itself — "Bookings" and
/// "Rentals" tabs with unread counts, a "Mark all as read" action, and
/// per-item tiles (avatar-style icon, title, relative time + category,
/// unread dot). Pending bookings get inline Accept/Decline buttons that
/// call the real repository right from here, the way the reference
/// design's request item does — everything else just navigates on tap.
/// Read/unread here is a local, in-session marker (there's no persisted
/// "seen" flag on these records) so it resets next time the panel opens.
class _NotificationsPanel extends StatefulWidget {
  final bool isDesktop;
  final ValueChanged<BookingRecord> onGoToBooking;
  final VoidCallback onGoToRentals;

  const _NotificationsPanel({required this.isDesktop, required this.onGoToBooking, required this.onGoToRentals});

  @override
  State<_NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<_NotificationsPanel> {
  _NotifTab _tab = _NotifTab.bookings;
  final Set<String> _readIds = {};
  bool _busy = false;

  Future<void> _accept(BookingRecord b) async {
    setState(() => _busy = true);
    try {
      final staffId = AuthService.instance.currentUid;
      final staffName = await AuthService.instance.currentStaffDisplayName();
      await BookingRepository.updateStatus(b.id, 'confirmed', staffId: staffId, staffName: staffName);
      if (mounted) setState(() => _readIds.add(b.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline(BookingRecord b) async {
    setState(() => _busy = true);
    try {
      final staffId = AuthService.instance.currentUid;
      final staffName = await AuthService.instance.currentStaffDisplayName();
      RefundDecision? refund;
      if (RefundDecisionDialog.needed(b)) {
        refund = await RefundDecisionDialog.show(context, b);
        if (refund == null) {
          if (mounted) setState(() => _busy = false);
          return;
        }
      }
      await BookingRepository.updateStatus(
        b.id,
        'cancelled',
        rejectionReason: 'Declined from notifications',
        staffId: staffId,
        staffName: staffName,
        refund: refund,
      );
      if (mounted) setState(() => _readIds.add(b.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _acknowledgeRental(CameraRentalRecord r) async {
    await CameraRentalRepository.acknowledge(r.id);
    if (mounted) setState(() => _readIds.add(r.id));
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
    if (diff.inHours < 24) return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.isDesktop ? BorderRadius.circular(20) : const BorderRadius.vertical(top: Radius.circular(20));
    return Container(
      constraints: BoxConstraints(maxHeight: widget.isDesktop ? 520 : MediaQuery.of(context).size.height * 0.82),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: radius,
        boxShadow: widget.isDesktop ? AppShadows.card : null,
        border: widget.isDesktop ? Border.all(color: AppPalette.divider(context)) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: StreamBuilder<List<BookingRecord>>(
        stream: BookingRepository.watchAllBookings(),
        builder: (context, bookingSnap) {
          final bookings = (bookingSnap.data ?? const <BookingRecord>[]).where((b) => b.status == 'pending_confirmation').toList()
            ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
          return StreamBuilder<List<CameraRentalRecord>>(
            stream: CameraRentalRepository.watchAllRentals(),
            builder: (context, rentalSnap) {
              final rentals = (rentalSnap.data ?? const <CameraRentalRecord>[]).where((r) => !r.acknowledged).toList()
                ..sort((a, b) => b.rentedAt.compareTo(a.rentedAt));

              final unreadBookings = bookings.where((b) => !_readIds.contains(b.id)).length;
              final unreadRentals = rentals.where((r) => !_readIds.contains(r.id)).length;

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!widget.isDesktop)
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 2),
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(color: AppPalette.divider(context), borderRadius: BorderRadius.circular(999)),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 16, 4),
                    child: Row(
                      children: [
                        Text("Notifications", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                        const Spacer(),
                        TextButton(
                          onPressed: (unreadBookings + unreadRentals) == 0
                              ? null
                              : () => setState(() {
                                    _readIds.addAll(bookings.map((b) => b.id));
                                    _readIds.addAll(rentals.map((r) => r.id));
                                  }),
                          style: TextButton.styleFrom(foregroundColor: AppColors.accent, padding: const EdgeInsets.symmetric(horizontal: 8)),
                          child: const Text("Mark all as read", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Row(
                      children: [
                        _NotifTabButton(
                          label: 'Bookings',
                          count: unreadBookings,
                          selected: _tab == _NotifTab.bookings,
                          onTap: () => setState(() => _tab = _NotifTab.bookings),
                        ),
                        const SizedBox(width: 22),
                        _NotifTabButton(
                          label: 'Rentals',
                          count: unreadRentals,
                          selected: _tab == _NotifTab.rentals,
                          onTap: () => setState(() => _tab = _NotifTab.rentals),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: AppPalette.divider(context)),
                  Flexible(
                    child: _tab == _NotifTab.bookings
                        ? (bookings.isEmpty
                            ? _emptyState(context)
                            : ListView.separated(
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                itemCount: bookings.length,
                                separatorBuilder: (_, __) => Divider(height: 1, color: AppPalette.divider(context)),
                                itemBuilder: (context, i) {
                                  final b = bookings[i];
                                  return _NotifTile(
                                    unread: !_readIds.contains(b.id),
                                    color: AppColors.accent,
                                    icon: Icons.event_available,
                                    title: '${b.customerName} booked ${b.packageName}',
                                    meta: '${_timeAgo(b.createdAt ?? DateTime.now())} · New booking',
                                    onTap: () {
                                      setState(() => _readIds.add(b.id));
                                      widget.onGoToBooking(b);
                                    },
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        OutlinedButton(
                                          onPressed: _busy ? null : () => _decline(b),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: AppPalette.textSecondary(context),
                                            side: BorderSide(color: AppPalette.divider(context)),
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          child: const Text("Decline", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton(
                                          onPressed: _busy ? null : () => _accept(b),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.accent,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          child: const Text("Accept", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ))
                        : (rentals.isEmpty
                            ? _emptyState(context)
                            : ListView.separated(
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                itemCount: rentals.length,
                                separatorBuilder: (_, __) => Divider(height: 1, color: AppPalette.divider(context)),
                                itemBuilder: (context, i) {
                                  final r = rentals[i];
                                  return _NotifTile(
                                    unread: !_readIds.contains(r.id),
                                    color: AppColors.highlight,
                                    icon: Icons.camera_alt,
                                    title: '${r.cameraName} rented out',
                                    meta: 'Due back ${DateFormat('MMM d, h:mm a').format(r.dueAt)} · New rental',
                                    onTap: () {
                                      setState(() => _readIds.add(r.id));
                                      widget.onGoToRentals();
                                    },
                                    trailing: TextButton(
                                      onPressed: () => _acknowledgeRental(r),
                                      style: TextButton.styleFrom(foregroundColor: AppColors.accent, padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                      child: const Text("Acknowledge", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    ),
                                  );
                                },
                              )),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(child: Text("You're all caught up.", style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)))),
    );
  }
}

/// One tab in the notifications panel's "Bookings / Rentals" switcher —
/// label, an unread-count pill, and a short accent underline when active.
class _NotifTabButton extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _NotifTabButton({required this.label, required this.count, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: selected ? AppPalette.textPrimary(context) : AppPalette.textMuted(context)),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(999)),
                    child: Text('$count', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 2,
              width: 28,
              color: selected ? AppColors.accent : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}

/// One notification row — tinted icon "avatar", bold title, relative
/// time + category meta line, an unread dot, and whatever action widget
/// fits that item (Accept/Decline for a booking, Acknowledge for a
/// rental) — mirrors the reference design's item layout.
class _NotifTile extends StatelessWidget {
  final bool unread;
  final Color color;
  final IconData icon;
  final String title;
  final String meta;
  final VoidCallback onTap;
  final Widget trailing;

  const _NotifTile({
    required this.unread,
    required this.color,
    required this.icon,
    required this.title,
    required this.meta,
    required this.onTap,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Icon(icon, size: 17, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, height: 1.3, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
                      ),
                      if (unread)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, top: 4),
                          child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(meta, style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
                  const SizedBox(height: 10),
                  trailing,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One clickable metric tile in the desktop stat row — tinted icon badge,
/// big number, label. Tapping filters the list below; the active filter's
/// tile gets an accent outline.
/// Plain rounded white card wrapper used across the Bookings dashboard
/// hero — same shape language for the progress ring, chart, and mini
/// calendar so they read as one family.
class _DashboardTileCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _DashboardTileCard({required this.child}) : padding = const EdgeInsets.all(16);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppShadows.soft,
      ),
      child: child,
    );
  }
}

/// A colored call-to-action card — "New Walk-in", "Point of Sale" — icon
/// up top, title/subtitle, and a small pill button that repeats the tap
/// target for anyone tapping precisely.
class _QuickActionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String buttonLabel;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: foreground),
              const SizedBox(height: 10),
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: foreground)),
              const SizedBox(height: 3),
              Text(subtitle, style: TextStyle(fontSize: 10.5, color: foreground.withValues(alpha: 0.75)), maxLines: 2),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: foreground.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(buttonLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: foreground)),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward, size: 12, color: foreground),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single-series "bookings per day" bar chart for the current week — no
/// charting package needed, just seven rounded bars.
class _WeeklyBookingsChart extends StatelessWidget {
  final List<int> counts; // 7 entries, Monday first
  final DateTime startOfWeek;

  const _WeeklyBookingsChart({required this.counts, required this.startOfWeek});

  @override
  Widget build(BuildContext context) {
    final maxCount = counts.fold<int>(1, (m, c) => c > m ? c : m);
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final today = DateTime.now();

    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (counts[i] > 0)
                      Text('${counts[i]}', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppPalette.textMuted(context))),
                    const SizedBox(height: 3),
                    Container(
                      height: counts[i] == 0 ? 3 : (counts[i] / maxCount * 70).clamp(6, 70).toDouble(),
                      decoration: BoxDecoration(
                        color: () {
                          final d = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day + i);
                          final isToday = d.year == today.year && d.month == today.month && d.day == today.day;
                          return counts[i] == 0 ? AppPalette.divider(context) : (isToday ? AppColors.accent : AppColors.accentTint(0.45));
                        }(),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(labels[i], style: TextStyle(fontSize: 10.5, color: AppPalette.textMuted(context))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Seven-day strip for the current week — day-of-week letter + date
/// number, today highlighted. Tapping any day jumps to the Calendar
/// section (there's no per-day drill-down here, just a shortcut).
class _MiniWeekStrip extends StatelessWidget {
  final DateTime startOfWeek;
  final VoidCallback onDayTap;

  const _MiniWeekStrip({required this.startOfWeek, required this.onDayTap});

  @override
  Widget build(BuildContext context) {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final today = DateTime.now();

    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Builder(builder: (context) {
              final d = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day + i);
              final isToday = d.year == today.year && d.month == today.month && d.day == today.day;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Material(
                  color: isToday ? AppColors.accent : AppPalette.surface(context),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onDayTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          Text(labels[i], style: TextStyle(fontSize: 9, color: isToday ? Colors.white70 : AppPalette.textMuted(context))),
                          const SizedBox(height: 3),
                          Text('${d.day}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: isToday ? Colors.white : AppPalette.textPrimary(context))),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _StatTile({required this.icon, required this.color, required this.value, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppPalette.cardBg(context),
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppShadows.soft,
            border: Border.all(color: active ? color : AppPalette.divider(context), width: active ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppPalette.textPrimary(context))),
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "New Walk-in Booking" call-to-action — a maroon gradient pill with a
/// soft glow, a round icon badge and a trailing arrow, instead of a flat
/// default button. [expand] stretches it full-width for the mobile layout.
class _WalkInButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool expand;
  const _WalkInButton({required this.onPressed}) : expand = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(8, 8, 18, 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.accent, Color(0xFF9A3236)]),
            borderRadius: BorderRadius.circular(999),
            boxShadow: AppShadows.accentGlowSmall,
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: const Icon(Icons.person_add_alt_1, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
              const Text("New Walk-in Booking", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  final VoidCallback onTap;
  final Color iconColor;
  const _NotificationBell({required this.onTap, this.iconColor = Colors.white});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BookingRecord>>(
      stream: BookingRepository.watchAllBookings(),
      builder: (context, bookingSnapshot) {
        final bookingCount =
            (bookingSnapshot.data ?? const <BookingRecord>[]).where((b) => b.status == 'pending_confirmation').length;
        return StreamBuilder<List<CameraRentalRecord>>(
          stream: CameraRentalRepository.watchAllRentals(),
          builder: (context, rentalSnapshot) {
            final rentalCount = (rentalSnapshot.data ?? const <CameraRentalRecord>[]).where((r) => !r.acknowledged).length;
            final count = bookingCount + rentalCount;
            return IconButton(
              onPressed: onTap,
              tooltip: "Notifications",
              icon: Badge(
                isLabelVisible: count > 0,
                label: Text('$count'),
                backgroundColor: AppColors.highlight,
                child: Icon(Icons.notifications_outlined, color: iconColor),
              ),
            );
          },
        );
      },
    );
  }
}

/// Small red/gold count of everything still waiting on staff (bookings to
/// approve + rentals to acknowledge) — shown on the phone header's bell.
class _PendingCountBadge extends StatelessWidget {
  const _PendingCountBadge();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BookingRecord>>(
      stream: BookingRepository.watchAllBookings(),
      builder: (context, bookingSnap) {
        final bookingCount = (bookingSnap.data ?? const <BookingRecord>[]).where((b) => b.status == 'pending_confirmation').length;
        return StreamBuilder<List<CameraRentalRecord>>(
          stream: CameraRentalRepository.watchAllRentals(),
          builder: (context, rentalSnap) {
            final rentalCount = (rentalSnap.data ?? const <CameraRentalRecord>[]).where((r) => !r.acknowledged).length;
            final count = bookingCount + rentalCount;
            if (count == 0) return const SizedBox.shrink();
            return Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.highlight, borderRadius: BorderRadius.circular(999)),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white, height: 1.1),
              ),
            );
          },
        );
      },
    );
  }
}

/// Persistent top header bar for the desktop staff shell: global search,
/// a live system-status badge, the notification bell (with its pending
/// count) and a live clock — a floating rounded card above every section.
class _StaffTopBar extends StatefulWidget {
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback onOpenNotifications;

  const _StaffTopBar({required this.onSearchSubmitted, required this.onOpenNotifications});

  @override
  State<_StaffTopBar> createState() => _StaffTopBarState();
}

class _StaffTopBarState extends State<_StaffTopBar> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: AppPalette.cardBg(context),
          borderRadius: BorderRadius.circular(22),
          boxShadow: AppShadows.soft,
          border: Border.all(color: AppPalette.divider(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: widget.onSearchSubmitted,
                    textInputAction: TextInputAction.search,
                    style: TextStyle(fontSize: 13, color: AppPalette.textPrimary(context)),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: "Search by Booking Ref, Customer Name, or Package...",
                      hintStyle: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context)),
                      prefixIcon: const Icon(Icons.search_rounded, size: 19, color: AppColors.accent),
                      filled: true,
                      fillColor: AppPalette.surface(context),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            const _SystemStatusBadge(),
            const SizedBox(width: 14),
            _NotificationBell(onTap: widget.onOpenNotifications, iconColor: AppPalette.textPrimary(context)),
            const SizedBox(width: 6),
            const _LiveClock(),
          ],
        ),
      ),
    );
  }
}

/// "System Online" pill — real, not decorative: it reflects whether the
/// bookings stream (the same one the whole dashboard depends on) is
/// currently connected, not a hardcoded label.
class _SystemStatusBadge extends StatelessWidget {
  const _SystemStatusBadge();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BookingRecord>>(
      stream: BookingRepository.watchAllBookings(),
      builder: (context, snapshot) {
        final online = !snapshot.hasError;
        final color = online ? AppColors.success : const Color(0xFFDC2626);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 7),
              Text(
                online ? "System Online" : "Connection Issue",
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Small ticking date/time readout for the top bar. Self-contained so it
/// doesn't force the rest of the header to rebuild every minute.
class _LiveClock extends StatefulWidget {
  const _LiveClock();

  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(DateFormat('h:mm a').format(now), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
        Text(DateFormat('EEE, MMM d').format(now), style: TextStyle(fontSize: 10, color: AppPalette.textMuted(context))),
      ],
    );
  }
}

/// Persistent desktop sidebar — a floating, rounded maroon card. At rest it
/// is a slim icon-only rail; when the cursor is over it, it expands (over the
/// content, without pushing it) to show the labels, and collapses again when
/// the cursor leaves.
class _StaffSidebar extends StatefulWidget {
  /// Space the collapsed rail takes in the page layout (card + its margins).
  static const double railWidth = 88;
  static const double _collapsedCard = 68;
  static const double _expandedCard = 244;

  final _StaffSection section;
  final ValueChanged<_StaffSection> onSelectSection;
  final VoidCallback onLogout;

  const _StaffSidebar({
    required this.section,
    required this.onSelectSection,
    required this.onLogout,
  });

  @override
  State<_StaffSidebar> createState() => _StaffSidebarState();
}

class _StaffSidebarState extends State<_StaffSidebar> {
  static const _anim = Duration(milliseconds: 220);

  bool _hovering = false;
  // Keeps the sidebar open while the profile popup menu is showing (the
  // popup's barrier would otherwise count as the cursor leaving).
  bool _menuOpen = false;
  bool get _expanded => _hovering || _menuOpen;

  @override
  Widget build(BuildContext context) {
    final email = AuthService.instance.currentEmail ?? '';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : 'S';
    final expanded = _expanded;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 4, 16),
          child: AnimatedContainer(
            duration: _anim,
            curve: Curves.easeOutCubic,
            width: expanded ? _StaffSidebar._expandedCard : _StaffSidebar._collapsedCard,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.accent, Color.lerp(AppColors.accent, Colors.black, 0.25)!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(26),
              boxShadow: AppShadows.accentGlow,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header + menu scroll when the window is short; the user
                // card below stays pinned to the bottom of the sidebar.
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 18, 6, 18),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(color: AppColors.brandCream, borderRadius: BorderRadius.circular(13)),
                                child: Image.asset('assets/images/memoriae_logo.webp', fit: BoxFit.contain),
                              ),
                              // Fixed height + width and clipped: OverflowBox
                              // sizes itself to its parent's constraints, which
                              // are unbounded vertically inside a Column.
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: ClipRect(
                                    child: OverflowBox(
                                      alignment: Alignment.centerLeft,
                                      minWidth: 0,
                                      maxWidth: 190,
                                      child: AnimatedOpacity(
                                        duration: _anim,
                                        opacity: expanded ? 1 : 0,
                                        child: Padding(
                                          padding: const EdgeInsets.only(left: 11),
                                          child: Row(
                                            children: [
                                              const Expanded(
                                                child: Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text("Memoriae", maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.2)),
                                                    Text("Staff Portal", maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: TextStyle(fontSize: 11, color: Colors.white70)),
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
                            ],
                          ),
                        ),
                        // "MENU" label when open, a thin divider when collapsed
                        // (same height either way so nothing jumps).
                        SizedBox(
                          height: 26,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: expanded
                                ? Padding(
                                    padding: const EdgeInsets.only(left: 22),
                                    child: Text(
                                      "MENU",
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.clip,
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: Colors.white.withValues(alpha: 0.5)),
                                    ),
                                  )
                                : Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 18), color: Colors.white.withValues(alpha: 0.22)),
                          ),
                        ),
                        _navItem(context, icon: Icons.event_note_rounded, label: "Bookings", target: _StaffSection.bookings),
                        _navItem(context, icon: Icons.camera_alt_rounded, label: "Camera Rentals", target: _StaffSection.cameraRentals),
                        _navItem(context, icon: Icons.point_of_sale_rounded, label: "Point of Sale", target: _StaffSection.pos),
                        _navItem(context, icon: Icons.calendar_month_rounded, label: "Calendar", target: _StaffSection.calendar),
                        _navItem(context, icon: Icons.photo_library_rounded, label: "Event Photos", target: _StaffSection.eventPhotos),
                        _navItem(context, icon: Icons.undo_rounded, label: "Refund Requests", target: _StaffSection.refundRequests),
                        _navItem(context, icon: Icons.star_rounded, label: "Feedback", target: _StaffSection.feedback),
                        _navItem(context, icon: Icons.chat_bubble_rounded, label: "Messages", target: _StaffSection.messages),
                        _navItem(context, icon: Icons.campaign_rounded, label: "Announcements", target: _StaffSection.announcements),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                // Pinned footer: the profile card. Tapping it opens a popup
                // menu with My Profile, Settings and Log out.
                Container(
                  margin: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: (widget.section == _StaffSection.profile || widget.section == _StaffSection.settings) ? 0.24 : 0.10),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Builder(
                      builder: (cardContext) => InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _openAccountMenu(cardContext),
                        child: AnimatedPadding(
                          duration: _anim,
                          curve: Curves.easeOutCubic,
                          padding: EdgeInsets.fromLTRB(expanded ? 12 : 5, 10, expanded ? 12 : 5, 10),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                child: Text(initial, style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 15)),
                              ),
                              Expanded(
                                child: SizedBox(
                                  height: 38,
                                  child: ClipRect(
                                    child: OverflowBox(
                                      alignment: Alignment.centerLeft,
                                      minWidth: 0,
                                      maxWidth: 170,
                                      child: AnimatedOpacity(
                                        duration: _anim,
                                        opacity: expanded ? 1 : 0,
                                        child: Padding(
                                          padding: const EdgeInsets.only(left: 10),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    const Text("Staff", maxLines: 1, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white)),
                                                    Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.7))),
                                                  ],
                                                ),
                                              ),
                                              Icon(Icons.unfold_more_rounded, size: 18, color: Colors.white.withValues(alpha: 0.7)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
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
        ),
      ),
    );
  }

  /// Popup above the profile card: My Profile, Settings, Log out.
  Future<void> _openAccountMenu(BuildContext cardContext) async {
    final box = cardContext.findRenderObject() as RenderBox;
    final overlay = Overlay.of(cardContext).context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final size = box.size;
    // 3 rows (48 each) + divider (16) + vertical padding (16), so the menu
    // opens upward just above the card instead of covering it.
    const menuHeight = 3 * 48.0 + 16 + 16;

    setState(() => _menuOpen = true);
    String? choice;
    try {
      choice = await showMenu<String>(
        context: cardContext,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(topLeft.dx, topLeft.dy - menuHeight - 6, size.width, menuHeight),
          Offset.zero & overlay.size,
        ),
        constraints: BoxConstraints.tightFor(width: size.width < 200 ? 200 : size.width),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        items: [
          PopupMenuItem<String>(
            value: 'profile',
            child: Row(children: [
              Icon(Icons.person_outline_rounded, size: 19, color: AppPalette.textPrimary(cardContext)),
              const SizedBox(width: 12),
              const Text("My Profile"),
            ]),
          ),
          PopupMenuItem<String>(
            value: 'settings',
            child: Row(children: [
              Icon(Icons.settings_outlined, size: 19, color: AppPalette.textPrimary(cardContext)),
              const SizedBox(width: 12),
              const Text("Settings"),
            ]),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: 'logout',
            child: Row(children: [
              Icon(Icons.logout_rounded, size: 19, color: AppColors.accent),
              SizedBox(width: 12),
              Text("Log out", style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      );
    } finally {
      if (mounted) setState(() => _menuOpen = false);
    }

    switch (choice) {
      case 'profile':
        widget.onSelectSection(_StaffSection.profile);
        break;
      case 'settings':
        widget.onSelectSection(_StaffSection.settings);
        break;
      case 'logout':
        widget.onLogout();
        break;
    }
  }

  Widget _navItem(BuildContext context, {required IconData icon, required String label, required _StaffSection target}) {
    final selected = widget.section == target;
    final expanded = _expanded;
    return InkWell(
      onTap: () => widget.onSelectSection(target),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: selected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 5))] : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: selected ? AppColors.accent : Colors.white.withValues(alpha: 0.75)),
            Expanded(
              child: AnimatedOpacity(
                duration: _anim,
                opacity: expanded ? 1 : 0,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                      color: selected ? AppColors.accent : Colors.white.withValues(alpha: 0.9),
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

/// Search box + status filter chips + a date sort toggle, shown above the
/// booking list on both desktop and mobile.
class _BookingFilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String statusFilter;
  final ValueChanged<String> onStatusChanged;
  final bool sortNewestFirst;
  final VoidCallback onToggleSort;

  /// How many bookings each status holds ('all' = every booking), shown on
  /// the chips so staff can see what needs attention before tapping.
  final Map<String, int> counts;

  const _BookingFilterBar({
    required this.counts,
    required this.searchController,
    required this.onSearchChanged,
    required this.statusFilter,
    required this.onStatusChanged,
    required this.sortNewestFirst,
    required this.onToggleSort,
  });

  static const _statuses = [
    ('all', 'All', Icons.apps_rounded),
    ('pending_confirmation', 'Needs approval', Icons.hourglass_top_rounded),
    ('confirmed', 'Confirmed', Icons.check_circle_outline_rounded),
    ('cancelled', 'Cancelled', Icons.cancel_outlined),
    ('completed', 'Completed', Icons.task_alt_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 12),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: (counts['pending_confirmation'] ?? 0) == 0 ? const Color(0xFF2E7D32) : const Color(0xFFB07A2A),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                (counts['pending_confirmation'] ?? 0) == 0
                    ? "No bookings waiting for approval"
                    : "${counts['pending_confirmation']} waiting for your approval",
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppPalette.textSecondary(context)),
              ),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                style: TextStyle(fontSize: 13, color: AppPalette.textPrimary(context)),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: "Search name, booking ID or reference",
                  hintStyle: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
                  prefixIcon: Icon(Icons.search, size: 18, color: AppPalette.textMuted(context)),
                  suffixIcon: searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            searchController.clear();
                            onSearchChanged('');
                          },
                        ),
                  filled: true,
                  fillColor: AppPalette.surface(context),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppPalette.divider(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Tooltip(
              message: sortNewestFirst ? "Newest date first" : "Oldest date first",
              child: OutlinedButton.icon(
                onPressed: onToggleSort,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppPalette.textPrimary(context),
                  side: BorderSide(color: AppPalette.divider(context)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: Icon(sortNewestFirst ? Icons.arrow_downward : Icons.arrow_upward, size: 15),
                label: const Text("Date", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _statuses.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final (value, label, icon) = _statuses[i];
              final selected = statusFilter == value;
              final count = counts[value] ?? 0;
              final urgent = value == 'pending_confirmation' && count > 0;
              final fg = selected ? Colors.white : AppPalette.textPrimary(context);
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => onStatusChanged(value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    decoration: BoxDecoration(
                      gradient: selected
                          ? LinearGradient(
                              colors: [AppColors.accent, Color.lerp(AppColors.accent, Colors.black, 0.22)!],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: selected ? null : AppPalette.cardBg(context),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: selected ? Colors.transparent : AppPalette.divider(context)),
                      boxShadow: selected
                          ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 15, color: fg),
                        const SizedBox(width: 6),
                        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
                        if (count > 0) ...[
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: selected
                                  ? Colors.white.withValues(alpha: 0.22)
                                  : (urgent ? const Color(0xFFB07A2A) : AppColors.accentTint(0.10)),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: selected || urgent ? Colors.white : AppColors.accent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BookingList extends StatefulWidget {
  final List<BookingRecord> bookings;
  final String? selectedId;
  final ValueChanged<BookingRecord> onTap;

  const _BookingList({required this.bookings, required this.selectedId, required this.onTap});

  @override
  State<_BookingList> createState() => _BookingListState();
}

class _BookingListState extends State<_BookingList> {
  int _page = 0;

  /// Section a booking falls under, so the list reads in order of time.
  String _groupOf(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final days = d.difference(today).inDays;
    if (days < 0) return 'Past';
    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    if (days <= 7) return 'This week';
    return 'Later';
  }

  @override
  Widget build(BuildContext context) {
    final bookings = widget.bookings;
    _page = PageWindow.clamp(_page, bookings.length);
    final pageItems = PageWindow.slice(bookings, _page);

    // Interleave section headers with the cards on this page.
    final rows = <Object>[];
    String? lastGroup;
    for (final b in pageItems) {
      final g = _groupOf(b.date);
      if (g != lastGroup) {
        rows.add(g);
        lastGroup = g;
      }
      rows.add(b);
    }

    return Column(
      children: [
        Expanded(
          child: bookings.isEmpty
              ? _emptyState(context)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    if (row is String) return _groupHeader(context, row);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _bookingCard(context, row as BookingRecord),
                    );
                  },
                ),
        ),
        PaginationBar(
          page: _page,
          pageCount: PageWindow.pageCount(bookings.length),
          onPageChanged: (p) => setState(() => _page = p),
        ),
      ],
    );
  }

  Widget _groupHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: AppPalette.textMuted(context),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 40, color: AppPalette.textMuted(context)),
            const SizedBox(height: 10),
            Text("Nothing here yet",
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
            const SizedBox(height: 4),
            Text(
              "No bookings match this filter. Try another status or clear the search.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, height: 1.4, color: AppPalette.textMuted(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoPill(BuildContext context, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppPalette.textMuted(context)),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppPalette.textSecondary(context))),
        ],
      ),
    );
  }

  Widget _bookingCard(BuildContext context, BookingRecord b) {
    final isSelected = b.id == widget.selectedId;
    final name = b.customerName.trim().isEmpty ? 'Guest' : b.customerName.trim();
    final needsAction = b.status == 'pending_confirmation';
    final cancelled = b.status == 'cancelled';
    final when = _whenLabel(b.date);
    const amber = Color(0xFFB07A2A);
    final muted = AppPalette.textMuted(context);
    final statusColor = _bookingStatusColor(b.status);
    final radius = BorderRadius.circular(20);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: () => widget.onTap(b),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.accentTint(0.06) : AppPalette.cardBg(context),
            borderRadius: radius,
            boxShadow: isSelected
                ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.16), blurRadius: 18, offset: const Offset(0, 8))]
                : AppShadows.soft,
            border: Border.all(
              color: isSelected ? AppColors.accent : AppPalette.divider(context),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(19, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.accent, Color.lerp(AppColors.accent, Colors.black, 0.25)!],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(name[0].toUpperCase(),
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
                                const SizedBox(height: 3),
                                Text(b.packageName.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: AppPalette.textSecondary(context))),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusChip(status: b.status),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _infoPill(context, Icons.calendar_today_outlined, DateFormat('MMM d, yyyy').format(b.date)),
                          _infoPill(context, Icons.schedule_rounded, b.time),
                          if (when != null && !cancelled)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(color: when.$2.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                              child: Text(when.$1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: when.$2)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Divider(height: 1, color: AppPalette.divider(context).withValues(alpha: 0.7)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: needsAction
                                ? Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                      decoration: BoxDecoration(color: amber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.touch_app_rounded, size: 13, color: amber),
                                          SizedBox(width: 5),
                                          Text("Tap to review and approve",
                                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: amber)),
                                        ],
                                      ),
                                    ),
                                  )
                                : Row(
                                    children: [
                                      Icon(Icons.tag_rounded, size: 13, color: muted),
                                      const SizedBox(width: 3),
                                      Flexible(
                                        child: Text(
                                          b.bookingRef,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: muted),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          Text(
                            '₱${NumberFormat('#,##0').format(b.totalPrice)}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: cancelled ? muted : AppPalette.textPrimary(context),
                              decoration: cancelled ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(left: 0, top: 0, bottom: 0, width: 5, child: ColoredBox(color: statusColor)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Today" / "Tomorrow" / "In 3 days" for an upcoming booking date, or null
/// when it is further away or already past (label text, color).
(String, Color)? _whenLabel(DateTime date) {
  final now = DateTime.now();
  final days = DateTime(date.year, date.month, date.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (days == 0) return ('Today', const Color(0xFFC62828));
  if (days == 1) return ('Tomorrow', const Color(0xFFB07A2A));
  if (days > 1 && days <= 7) return ('In $days days', const Color(0xFF2E7D32));
  return null;
}

/// Friendly empty state for the bookings list.
class _BookingsEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _BookingsEmpty({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.accentTint(0.08), shape: BoxShape.circle),
              child: Icon(icon, size: 26, color: AppColors.accent),
            ),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
            const SizedBox(height: 4),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
          ],
        ),
      ),
    );
  }
}

/// One color per booking status — shared by the list card's side stripe and
/// the status chip so they always match.
Color _bookingStatusColor(String status) {
  switch (status) {
    case 'confirmed':
      return const Color(0xFF2E7D32);
    case 'completed':
      return const Color(0xFF1565C0);
    case 'cancelled':
      return const Color(0xFFC62828);
    case 'awaiting_receipt':
      return const Color(0xFF6A4FB6);
    default:
      return const Color(0xFFB07A2A);
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  Color _color() => _bookingStatusColor(status);

  String _label() {
    switch (status) {
      case 'pending_confirmation':
        return 'Pending';
      case 'cancelled':
        return 'Rejected';
      case 'awaiting_receipt':
        return 'Awaiting receipt';
      default:
        return status.isEmpty ? '' : status[0].toUpperCase() + status.substring(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(_label(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

/// Mobile-only: the detail pane pushed as its own screen instead of shown
/// side-by-side.
class _StaffBookingDetailScreen extends StatelessWidget {
  final BookingRecord booking;
  const _StaffBookingDetailScreen({required this.booking});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: const Text("Booking Details"),
      ),
      body: _BookingDetailPane(booking: booking),
    );
  }
}

class _BookingDetailPane extends StatefulWidget {
  final BookingRecord booking;
  const _BookingDetailPane({required this.booking});

  @override
  State<_BookingDetailPane> createState() => _BookingDetailPaneState();
}

class _BookingDetailPaneState extends State<_BookingDetailPane> {
  bool _updating = false;

  /// The booking as it looks right after a reschedule — the parent hands
  /// this pane a fixed snapshot, so without this the Schedule card would
  /// keep showing the old date until the booking is re-selected.
  BookingRecord? _override;

  // The parent hands this pane a fixed snapshot, so it also follows the
  // live booking — otherwise buttons like "Mark balance paid" or
  // "Mark refunded" would stay on screen after they've been used.
  StreamSubscription<List<BookingRecord>>? _liveSub;
  BookingRecord? _live;
  BookingRecord get _current => _live ?? _override ?? widget.booking;

  @override
  void initState() {
    super.initState();
    _listenLive();
  }

  @override
  void didUpdateWidget(covariant _BookingDetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.booking.id != widget.booking.id) {
      _override = null;
      _listenLive();
    }
  }

  void _listenLive() {
    _liveSub?.cancel();
    _live = null;
    final id = widget.booking.id;
    _liveSub = BookingRepository.watchAllBookings().listen((list) {
      for (final x in list) {
        if (x.id == id) {
          if (mounted) setState(() => _live = x);
          return;
        }
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    super.dispose();
  }

  Future<void> _markRefunded() async {
    setState(() => _updating = true);
    try {
      await _staffMarkRefunded(_current.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Refund marked as sent.")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't update refund: $e")));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _openReschedule() async {
    final updated = await showDialog<BookingRecord>(
      context: context,
      builder: (_) => _RescheduleDialog(booking: _current),
    );
    if (updated == null || !mounted) return;
    setState(() => _override = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Booking rescheduled — the customer has been notified and will see the new schedule.")),
    );
  }

  static const _rejectionReasons = [
    'Invalid GCash reference',
    'Slot unavailable',
    'Payment mismatch',
    'Other',
  ];

  /// Confirms, then records that the customer paid what was left after
  /// their downpayment (usually collected on the event day).
  Future<void> _markBalancePaid() async {
    final b = _current;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.payments_rounded, color: AppColors.accent),
        title: const Text("Mark balance as paid?"),
        content: Text(
          "Confirm you've received the remaining ${_money(b.balanceDue)} from this customer. "
          "The booking will then count as fully paid.",
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text("Not yet")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text("Yes, received"),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _updating = true);
    try {
      final staffId = AuthService.instance.currentUid;
      final staffName = await AuthService.instance.currentStaffDisplayName();
      await BookingRepository.markBalancePaid(b.id, staffId: staffId, staffName: staffName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Balance marked as paid.")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't update payment: $e")));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _setStatus(String status, {String? rejectionReason, RefundDecision? refund}) async {
    setState(() => _updating = true);
    try {
      final staffId = AuthService.instance.currentUid;
      final staffName = await AuthService.instance.currentStaffDisplayName();
      await BookingRepository.updateStatus(
        _current.id,
        status,
        rejectionReason: rejectionReason,
        staffId: staffId,
        staffName: staffName,
        refund: refund,
      );
      if (mounted && status == 'cancelled') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Booking rejected — the customer has been notified.")),
        );
      }
      if (mounted && status == 'confirmed') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Booking accepted — that date is now locked, and other requests for it were declined.")),
        );
      }
    } on DoubleBookingException catch (e) {
      if (!mounted) return;
      _showDoubleBookingDialog(e.message);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't update status: $e")));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  /// A clash is worth more than a snackbar — it means the booking wasn't
  /// accepted, so it gets a dialog the staff member has to acknowledge.
  void _showDoubleBookingDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.event_busy, color: AppColors.accent),
        title: const Text("Date already booked"),
        content: Text(message, style: const TextStyle(fontSize: 13)),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text("Got it"),
          ),
        ],
      ),
    );
  }

  /// Asks the staff member for a reason before rejecting — required so the
  /// customer gets a specific, useful explanation rather than a bare
  /// "rejected" status.
  Future<void> _confirmReject() async {
    String selected = _rejectionReasons.first;
    final customController = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Reject booking"),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Choose a reason — it's sent to the customer.",
                      style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)),
                    ),
                    const SizedBox(height: 8),
                    for (final r in _rejectionReasons)
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(r, style: const TextStyle(fontSize: 13)),
                        value: r,
                        groupValue: selected,
                        activeColor: AppColors.accent,
                        onChanged: (v) => setDialogState(() => selected = v!),
                      ),
                    if (selected == 'Other')
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 4),
                        child: TextField(
                          controller: customController,
                          autofocus: true,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            hintText: "Describe the reason",
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text("Cancel")),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                  onPressed: () {
                    final finalReason = selected == 'Other' ? customController.text.trim() : selected;
                    if (finalReason.isEmpty) return;
                    Navigator.of(dialogContext).pop(finalReason);
                  },
                  child: const Text("Reject & notify"),
                ),
              ],
            );
          },
        );
      },
    );

    if (reason != null && reason.isNotEmpty) {
      RefundDecision? refund;
      if (RefundDecisionDialog.needed(_current)) {
        if (!mounted) return;
        refund = await RefundDecisionDialog.show(context, _current);
        if (refund == null) return; // backed out — leave the booking as is
      }
      await _setStatus('cancelled', rejectionReason: reason, refund: refund);
    }
  }

  void _openReceiptLightbox(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _ReceiptLightbox(url: url),
    );
  }

  @override
  String _money(int v) => '₱${NumberFormat('#,##0').format(v)}';

  Widget _card(BuildContext context, {required IconData icon, required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.divider(context)),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.accentTint(0.10), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 16, color: AppColors.accent),
              ),
              const SizedBox(width: 10),
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: AppPalette.divider(context).withValues(alpha: 0.7)),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = _current;
    final name = b.customerName.trim().isEmpty ? 'Guest' : b.customerName.trim();
    return Container(
      color: AppPalette.surface(context),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          RefundStatusCard(booking: b, busy: _updating, onMarkRefunded: _markRefunded),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.accent, Color.lerp(AppColors.accent, Colors.black, 0.25)!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: Text(name[0].toUpperCase(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.accent)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                        const SizedBox(height: 2),
                        Text(b.packageName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.8))),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999)),
                          child: Text('REF ${b.bookingRef}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_money(b.totalPrice), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: Colors.white)),
                      Text("Total", style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.75))),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                        child: _StatusChip(status: b.status),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (b.isAwaitingReceipt) _buildHoldBanner(context, b),
            if (b.status == 'cancelled' && (b.rejectionReason ?? '').isNotEmpty || b.autoRejected)
              _card(context, icon: Icons.block, title: "Rejection", children: [
                if ((b.rejectionReason ?? '').isNotEmpty) _detailRow(context, "Reason", b.rejectionReason!),
                if (b.autoRejected) _detailRow(context, "Rejected by", "System (automatic)"),
              ]),
            _card(context, icon: Icons.event_outlined, title: "Schedule", children: [
              _detailRow(context, "Date", DateFormat('EEEE, MMM d, yyyy').format(b.date)),
              _detailRow(context, "Time", b.time),
              _detailRow(context, "Location", b.location.isNotEmpty ? b.location : "Not specified"),
              _detailRow(context, "Duration", b.duration),
              if (b.guests != null) _detailRow(context, "Guests", '${b.guests}'),
              if (b.wasRescheduled && b.previousDate != null) _buildRescheduledNote(context, b),
              const SizedBox(height: 6),
              if (BookingRepository.canReschedule(b.status))
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _updating ? null : _openReschedule,
                    icon: const Icon(Icons.edit_calendar_outlined, size: 16),
                    label: const Text("Reschedule booking", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side: const BorderSide(color: AppColors.accent),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                )
              else if (b.isAwaitingReceipt)
                Text("Can be rescheduled once the customer's receipt is in.", style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
            ]),
            _card(context, icon: Icons.receipt_long_outlined, title: "Pricing", children: [
              _detailRow(context, "Package", _money(b.price)),
              if (b.addOnNames.isNotEmpty) _detailRow(context, "Add-ons", '${b.addOnNames.join(", ")} (+${_money(b.addOnsPrice)})'),
              _detailRow(context, "Total", _money(b.totalPrice)),
              if (b.isDownpayment) ...[
                _detailRow(context, "Paid so far", '${_money(b.paidAmount)} (downpayment)'),
                _detailRow(context, "Balance", b.hasBalance ? '${_money(b.balanceDue)} — collect on event day' : 'Settled'),
                if (b.hasBalance && b.status != 'cancelled' && b.status != 'awaiting_receipt') ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _updating ? null : _markBalancePaid,
                      icon: const Icon(Icons.payments_rounded, size: 16),
                      label: Text("Mark balance paid (${_money(b.balanceDue)})"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE08A00),
                        side: const BorderSide(color: Color(0xFFE08A00)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ],
            ]),
            _card(context, icon: Icons.person_outline, title: "Customer", children: [
              if (b.customerName.isNotEmpty) _detailRow(context, "Name", b.customerName),
              _detailRow(context, "Customer ID", b.userId),
              if (b.createdAt != null) _detailRow(context, "Booked", DateFormat('MMM d, yyyy h:mm a').format(b.createdAt!)),
            ]),
            _card(context, icon: Icons.image_outlined, title: "Payment Receipt", children: [
              if (b.receiptUrl.isNotEmpty)
                GestureDetector(
                  onTap: () => _openReceiptLightbox(b.receiptUrl),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppPalette.surface(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppPalette.divider(context)),
                    ),
                    child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: buildReceiptImage(
                          b.receiptUrl,
                          fit: BoxFit.contain,
                          height: 220,
                          width: double.infinity,
                          errorBuilder: (context, error, stack) => Container(
                            height: 160,
                            color: AppPalette.surface(context),
                            alignment: Alignment.center,
                            child: Text("Couldn't load receipt image", style: TextStyle(color: AppPalette.textMuted(context))),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(999)),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.zoom_in, size: 13, color: Colors.white),
                              SizedBox(width: 4),
                              Text("Tap to zoom", style: TextStyle(fontSize: 10.5, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    children: [
                      Icon(b.receiptFileName.isNotEmpty ? Icons.cloud_upload_outlined : Icons.image_not_supported_outlined, size: 18, color: AppPalette.textMuted(context)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          b.receiptFileName.isNotEmpty ? "Uploading \"${b.receiptFileName}\" to cloud storage — check back shortly." : "No receipt on file.",
                          style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)),
                        ),
                      ),
                    ],
                  ),
                ),
              ..._receiptScanInfo(context, b),
            ]),
            _buildDecisionCard(context, b),
          ],
        ),
      ),
    );
  }

  /// "Rescheduled from <old date · time> by <staff>" — so the next staff
  /// member (and Admin) can see the booking was moved and why.
  Widget _buildRescheduledNote(BuildContext context, BookingRecord b) {
    const blue = Color(0xFF1565C0);
    final was = '${DateFormat('EEE, MMM d, yyyy').format(b.previousDate!)}'
        '${(b.previousTime ?? '').isEmpty ? '' : ' · ${b.previousTime}'}';
    final by = (b.rescheduledByStaffName ?? '').trim();
    final why = (b.rescheduleReason ?? '').trim();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: blue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.event_repeat, size: 16, color: blue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Rescheduled from $was${by.isEmpty ? '' : ' by $by'}${why.isEmpty ? '' : '\nReason: $why'}',
              style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context)),
            ),
          ),
        ],
      ),
    );
  }

  /// Shown while a booking is still just a slot hold: the customer hasn't
  /// sent their receipt yet, and the booking auto-rejects when the
  /// countdown reaches zero — so there's nothing to approve here yet.
  Widget _buildHoldBanner(BuildContext context, BookingRecord b) {
    final left = b.holdRemaining;
    final label = left == null
        ? "Waiting for the customer's payment receipt."
        : left == Duration.zero
            ? "The hold has lapsed — this will be auto-rejected on the next sweep."
            : "Waiting for the customer's payment receipt — "
                "${left.inMinutes}m ${(left.inSeconds % 60).toString().padLeft(2, '0')}s left on the hold.";

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF6A4FB6).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hourglass_top, size: 16, color: Color(0xFF6A4FB6)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context))),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)))),
          Expanded(child: Text(value, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context)))),
        ],
      ),
    );
  }

  /// Approve / Reject / Mark Completed — state-aware: it tells staff what is
  /// expected at this point of the booking, and an action that has already
  /// happened shows as "done" instead of a dead grey button.
  Widget _buildDecisionCard(BuildContext context, BookingRecord b) {
    const green = Color(0xFF2E7D32);
    const red = Color(0xFFC62828);
    const blue = Color(0xFF1565C0);
    final status = b.status;
    // A slot hold has no receipt to check yet, so there's nothing to accept
    // or mark done — it either turns into a real request or auto-rejects.
    final holdBlocked = b.isAwaitingReceipt;

    final (String, IconData, Color) info = switch (status) {
      'pending_confirmation' => (
          "Check the receipt above, then approve or reject this request.",
          Icons.visibility_outlined,
          const Color(0xFFB07A2A),
        ),
      'confirmed' => (
          "Approved. Mark it completed once the session is done.",
          Icons.check_circle_outline_rounded,
          green,
        ),
      'completed' => ("This booking is completed.", Icons.task_alt_rounded, blue),
      'cancelled' => ("This booking was rejected.", Icons.block_rounded, red),
      _ => (
          "Waiting for the customer's receipt — there's nothing to approve yet.",
          Icons.hourglass_top_rounded,
          const Color(0xFF6A4FB6),
        ),
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.divider(context)),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _updating
              ? const LinearProgressIndicator(minHeight: 3, color: AppColors.accent)
              : const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.accentTint(0.10), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.fact_check_outlined, size: 16, color: AppColors.accent),
                    ),
                    const SizedBox(width: 10),
                    Text("Approval",
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
                    const Spacer(),
                    _StatusChip(status: status),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: info.$3.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(info.$2, size: 17, color: info.$3),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(info.$1,
                            style: TextStyle(fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600, color: AppPalette.textSecondary(context))),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _DecisionButton(
                        label: status == 'confirmed' ? "Approved" : "Approve",
                        icon: Icons.check_rounded,
                        color: green,
                        kind: _DecisionKind.solid,
                        done: status == 'confirmed',
                        onPressed: (_updating || status == 'confirmed' || holdBlocked) ? null : () => _setStatus('confirmed'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _DecisionButton(
                        label: status == 'cancelled' ? "Rejected" : "Reject",
                        icon: Icons.close_rounded,
                        color: red,
                        kind: _DecisionKind.tonal,
                        done: status == 'cancelled',
                        onPressed: (_updating || status == 'cancelled') ? null : _confirmReject,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _DecisionButton(
                  label: status == 'completed' ? "Completed" : "Mark Completed",
                  icon: Icons.task_alt_rounded,
                  color: blue,
                  kind: _DecisionKind.outline,
                  done: status == 'completed',
                  onPressed: (_updating || status == 'completed' || holdBlocked) ? null : () => _setStatus('completed'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 12, color: AppPalette.textMuted(context)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text("Only a staff member can approve or reject a booking request.",
                          style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _DecisionKind { solid, tonal, outline }

/// Big, rounded action button used by the Approval card. [done] marks the
/// action that has already been applied to the booking (shown as a calm
/// tinted "done" state); a null [onPressed] otherwise means it's blocked.
class _DecisionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final _DecisionKind kind;
  final bool done;
  final VoidCallback? onPressed;

  const _DecisionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.kind,
    required this.onPressed,
    this.done = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(14);

    Color fg;
    Color? bg;
    Gradient? gradient;
    Border? border;
    List<BoxShadow>? shadow;
    var shownIcon = icon;

    if (done) {
      fg = color;
      bg = color.withValues(alpha: 0.10);
      border = Border.all(color: color.withValues(alpha: 0.35));
      shownIcon = Icons.check_circle_rounded;
    } else if (!enabled) {
      fg = AppPalette.textMuted(context).withValues(alpha: 0.75);
      bg = AppPalette.surface(context);
      border = Border.all(color: AppPalette.divider(context));
    } else if (kind == _DecisionKind.solid) {
      fg = Colors.white;
      gradient = LinearGradient(
        colors: [color, Color.lerp(color, Colors.black, 0.2)!],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
      shadow = [BoxShadow(color: color.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 6))];
    } else if (kind == _DecisionKind.tonal) {
      fg = color;
      bg = color.withValues(alpha: 0.10);
      border = Border.all(color: color.withValues(alpha: 0.4));
    } else {
      fg = color;
      bg = Colors.transparent;
      border = Border.all(color: color, width: 1.3);
    }

    return Container(
      decoration: BoxDecoration(color: bg, gradient: gradient, borderRadius: radius, border: border, boxShadow: shadow),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: Container(
            height: 50,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(shownIcon, size: 19, color: fg),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen modal image viewer / lightbox for previewing a payment
/// receipt before approving or rejecting a booking — pinch/scroll to zoom
/// via [InteractiveViewer].
class _ReceiptLightbox extends StatelessWidget {
  final String url;
  const _ReceiptLightbox({required this.url});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: buildReceiptImage(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => const Text(
                    "Couldn't load receipt image",
                    style: TextStyle(color: Colors.white),
                  ),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                  },
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the self-service "Change Password" dialog for the signed-in
/// staff member. Requires their current password (Firebase needs a
/// recent sign-in before it allows a password change — see
/// `AuthService.changePassword`), a new password, and a matching
/// confirmation.
Future<void> _showChangePasswordDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => const _ChangePasswordDialog(),
  );
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _saving = false;
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Rebuild on every keystroke so the requirement checklist updates live.
    _newController.addListener(() => setState(() {}));
    _confirmController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _hasLength => _newController.text.length >= 8;
  bool get _hasUpper => RegExp(r'[A-Z]').hasMatch(_newController.text);
  bool get _hasLower => RegExp(r'[a-z]').hasMatch(_newController.text);
  bool get _hasNumber => RegExp(r'[0-9]').hasMatch(_newController.text);
  bool get _hasSymbol => RegExp(r'[^A-Za-z0-9]').hasMatch(_newController.text);
  bool get _matches => _confirmController.text.isNotEmpty && _confirmController.text == _newController.text;
  bool get _strongEnough => _hasLength && _hasUpper && _hasLower && _hasNumber && _hasSymbol;

  Future<void> _submit() async {
    final current = _currentController.text;
    final next = _newController.text;
    final confirm = _confirmController.text;

    if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
      setState(() => _error = "Fill in all three fields.");
      return;
    }
    if (!_strongEnough) {
      setState(() => _error = "New password doesn't meet all the requirements below.");
      return;
    }
    if (next == current) {
      setState(() => _error = "New password must be different from your current one.");
      return;
    }
    if (next != confirm) {
      setState(() => _error = "New password and confirmation don't match.");
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AuthService.instance.changePassword(currentPassword: current, newPassword: next);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Password changed.")),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required bool visible,
    required VoidCallback onToggle,
    required IconData icon,
    TextInputAction action = TextInputAction.next,
    VoidCallback? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: !visible,
      enabled: !_saving,
      textInputAction: action,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
      style: TextStyle(color: AppPalette.textPrimary(context), fontSize: 14),
      decoration: InputDecoration(
        hintText: label,
        hintStyle: TextStyle(color: AppPalette.textMuted(context), fontSize: 13),
        filled: true,
        fillColor: AppPalette.surface(context),
        prefixIcon: Icon(icon, size: 18, color: AppPalette.textMuted(context)),
        suffixIcon: IconButton(
          tooltip: visible ? "Hide password" : "Show password",
          icon: Icon(visible ? Icons.visibility : Icons.visibility_off, size: 18, color: AppPalette.textMuted(context)),
          onPressed: onToggle,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.accent, width: 1.4)),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 14),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppPalette.textSecondary(context))),
    );
  }

  Widget _rule(String text, bool ok) {
    final color = ok ? const Color(0xFF2E7D32) : AppPalette.textMuted(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, size: 15, color: color),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: ok ? FontWeight.w600 : FontWeight.w400)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppPalette.cardBg(context),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: AppColors.accentTint(0.10), borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.lock_reset_rounded, color: AppColors.accent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Change password",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppPalette.textPrimary(context)),
                        ),
                        const SizedBox(height: 2),
                        Text("Keep your account secure.", style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
                      ],
                    ),
                  ),
                ],
              ),
              _label("Current password"),
              _field(
                label: "Enter current password",
                controller: _currentController,
                visible: _showCurrent,
                onToggle: () => setState(() => _showCurrent = !_showCurrent),
                icon: Icons.lock_outline,
              ),
              _label("New password"),
              _field(
                label: "Enter new password",
                controller: _newController,
                visible: _showNew,
                onToggle: () => setState(() => _showNew = !_showNew),
                icon: Icons.key_outlined,
              ),
              _label("Confirm new password"),
              _field(
                label: "Re-enter new password",
                controller: _confirmController,
                visible: _showConfirm,
                onToggle: () => setState(() => _showConfirm = !_showConfirm),
                icon: Icons.key_outlined,
                action: TextInputAction.done,
                onSubmitted: _saving ? null : _submit,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 7),
                decoration: BoxDecoration(
                  color: AppPalette.surface(context),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _rule("At least 8 characters", _hasLength),
                    _rule("An uppercase letter (A-Z)", _hasUpper),
                    _rule("A lowercase letter (a-z)", _hasLower),
                    _rule("A number (0-9)", _hasNumber),
                    _rule("A symbol (e.g. @ # ! %)", _hasSymbol),
                    _rule("Both new passwords match", _matches),
                  ],
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: _error == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(color: AppColors.accentTint(0.08), borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 1),
                                child: Icon(Icons.error_outline, size: 16, color: AppColors.accent),
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_error ?? '', style: const TextStyle(fontSize: 12, color: AppColors.accent))),
                            ],
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppPalette.textSecondary(context),
                        side: BorderSide(color: AppPalette.divider(context)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text("Update password", style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders a receipt image from either format `receiptUrl` can hold: a
/// `data:image/...;base64,...` URI (the current format — receipts are
/// stored inline in the Firestore document, not Firebase Storage, to
/// avoid requiring the Blaze billing plan) or, for backward compatibility
/// with any booking saved back when this app *did* use Storage, a real
/// `https://` download URL.
Widget buildReceiptImage(
  String value, {
  BoxFit fit = BoxFit.contain,
  double? height,
  double? width,
  Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
  Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder,
}) {
  return _ReceiptImage(
    value: value,
    fit: fit,
    height: height,
    width: width,
    errorBuilder: errorBuilder,
    loadingBuilder: loadingBuilder,
  );
}

class _ReceiptImage extends StatelessWidget {
  final String value;
  final BoxFit fit;
  final double? height;
  final double? width;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder;

  const _ReceiptImage({
    required this.value,
    required this.fit,
    required this.height,
    required this.width,
    required this.errorBuilder,
    required this.loadingBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (value.startsWith('data:')) {
      try {
        final base64Part = value.substring(value.indexOf(',') + 1);
        final bytes = base64Decode(base64Part);
        return Image.memory(bytes, fit: fit, height: height, width: width, errorBuilder: errorBuilder);
      } catch (e, st) {
        return errorBuilder?.call(context, e, st) ??
            const Text("Couldn't load receipt image", style: TextStyle(color: Colors.white));
      }
    }
    return Image.network(value, fit: fit, height: height, width: width, errorBuilder: errorBuilder, loadingBuilder: loadingBuilder);
  }
}


/// Staff dialog for moving a customer's booking to another date/time.
/// Saves through [BookingRepository.rescheduleBooking] itself, so a clash
/// ("that date was just taken") shows inline and the dialog stays open;
/// on success it pops the updated [BookingRecord].
class _RescheduleDialog extends StatefulWidget {
  final BookingRecord booking;
  const _RescheduleDialog({required this.booking});

  @override
  State<_RescheduleDialog> createState() => _RescheduleDialogState();
}

class _RescheduleDialogState extends State<_RescheduleDialog> {
  late DateTime _date;
  late TimeOfDay _start;
  TimeOfDay? _end;
  final _reasonController = TextEditingController();
  bool _saving = false;
  bool _loadingDates = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final b = widget.booking;
    _date = DateTime(b.date.year, b.date.month, b.date.day);
    final times = RegExp(r'(\d{1,2}):(\d{2})\s*([AaPp][Mm])').allMatches(b.time).map((m) {
      var h = int.parse(m.group(1)!) % 12;
      if (m.group(3)!.toLowerCase() == 'pm') h += 12;
      return TimeOfDay(hour: h, minute: int.parse(m.group(2)!));
    }).toList();
    _start = times.isNotEmpty ? times[0] : const TimeOfDay(hour: 10, minute: 0);
    _end = times.length > 1 ? times[1] : null;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  String _fmt(TimeOfDay t) => DateFormat('h:mm a').format(DateTime(2000, 1, 1, t.hour, t.minute));
  String get _timeLabel => _end == null ? _fmt(_start) : '${_fmt(_start)} – ${_fmt(_end!)}';
  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _pickDate() async {
    setState(() => _loadingDates = true);
    Set<DateTime> locked = {};
    try {
      locked = await BookingRepository.watchLockedDates().first;
    } catch (_) {}
    if (!mounted) return;
    setState(() => _loadingDates = false);

    final today = DateTime.now();
    final first = DateTime(today.year, today.month, today.day);
    final own = widget.booking.date;
    final initial = _date.isBefore(first) ? first : _date;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: first.add(const Duration(days: 365)),
      // Dates held by OTHER bookings are greyed out; this booking's own
      // current date stays selectable so staff can change only the time.
      selectableDayPredicate: (d) => _sameDay(d, own) || !locked.any((l) => _sameDay(l, d)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickStart() async {
    final t = await showTimePicker(context: context, initialTime: _start);
    if (t != null) setState(() => _start = t);
  }

  Future<void> _pickEnd() async {
    final t = await showTimePicker(context: context, initialTime: _end ?? TimeOfDay(hour: (_start.hour + 3) % 24, minute: _start.minute));
    if (t != null) setState(() => _end = t);
  }

  Future<void> _save() async {
    final b = widget.booking;
    final startMin = _start.hour * 60 + _start.minute;
    if (_end != null && (_end!.hour * 60 + _end!.minute) <= startMin) {
      setState(() => _error = "End time must be after the start time.");
      return;
    }
    if (_sameDay(_date, b.date) && _timeLabel == b.time) {
      setState(() => _error = "That's the same date and time — pick something different.");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final staffId = AuthService.instance.currentUid;
      final staffName = await AuthService.instance.currentStaffDisplayName();
      final reason = _reasonController.text.trim();
      await BookingRepository.rescheduleBooking(
        b.id,
        newDate: _date,
        newTime: _timeLabel,
        reason: reason,
        staffId: staffId,
        staffName: staffName,
      ).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      Navigator.of(context).pop(b.copyWith(
        date: _date,
        time: _timeLabel,
        previousDate: b.date,
        previousTime: b.time,
        rescheduledAt: DateTime.now(),
        rescheduledByStaffName: staffName,
        rescheduleReason: reason,
        rescheduleCount: b.rescheduleCount + 1,
      ));
    } on DoubleBookingException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't reschedule: $e");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(BuildContext context, {required IconData icon, required String label, required String value, required VoidCallback? onTap}) {
    return InkWell(
      onTap: _saving ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 10.5, color: AppPalette.textMuted(context))),
                  Text(value, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    return AlertDialog(
      backgroundColor: AppPalette.cardBg(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      icon: const Icon(Icons.edit_calendar_outlined, color: AppColors.accent),
      title: const Text("Reschedule booking"),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Currently: ${DateFormat('EEE, MMM d, yyyy').format(b.date)}${b.time.isEmpty ? '' : ' · ${b.time}'}",
                style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)),
              ),
              const SizedBox(height: 12),
              _field(context, icon: Icons.event, label: "New date", value: DateFormat('EEEE, MMM d, yyyy').format(_date), onTap: _loadingDates ? null : _pickDate),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _field(context, icon: Icons.schedule, label: "Start", value: _fmt(_start), onTap: _pickStart)),
                  const SizedBox(width: 8),
                  Expanded(child: _field(context, icon: Icons.schedule_outlined, label: "End (optional)", value: _end == null ? "Not set" : _fmt(_end!), onTap: _pickEnd)),
                  if (_end != null)
                    IconButton(
                      tooltip: "Clear end time",
                      visualDensity: VisualDensity.compact,
                      onPressed: _saving ? null : () => setState(() => _end = null),
                      icon: Icon(Icons.close, size: 16, color: AppPalette.textMuted(context)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reasonController,
                enabled: !_saving,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: "Note to customer (optional)",
                  hintText: "e.g. Moved to a later time as requested",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "The customer gets a notification and their My Bookings updates right away.",
                style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFFC62828), fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text("Cancel")),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text("Reschedule & notify"),
        ),
      ],
    );
  }
}


/// What the Customer app's on-device OCR read off the GCash receipt — the
/// reference number (with a copy button) and the amount — so it can be
/// matched against GCash quickly. The amount is flagged when it differs from
/// what the customer should have sent. It's auto-read, so the receipt image
/// above stays the source of truth.
List<Widget> _receiptScanInfo(BuildContext context, BookingRecord b) {
  final ref = b.receiptRefNo;
  final scanned = b.receiptOcrAmount;
  if (ref.isEmpty && scanned == null) return const [];

  final expected = b.amountPaid ?? b.totalPrice;
  final mismatch = scanned != null && (scanned - expected).abs() >= 0.5;
  final money = NumberFormat('#,##0.00');
  final accent = mismatch ? Colors.orange : Colors.green.shade600;
  final refPretty = ref.length == 13 ? '${ref.substring(0, 4)} ${ref.substring(4, 7)} ${ref.substring(7)}' : ref;

  Widget row(String label, Widget value) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
            const Spacer(),
            value,
          ],
        ),
      );

  return [
    const SizedBox(height: 12),
    Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(mismatch ? Icons.info_outline : Icons.document_scanner_outlined, size: 16, color: accent),
              const SizedBox(width: 6),
              Text("Read from receipt (auto-scan)",
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
            ],
          ),
          if (ref.isNotEmpty)
            row(
              "Ref No.",
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(refPretty,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: ref));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reference number copied")));
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.copy_rounded, size: 16, color: AppPalette.textMuted(context)),
                    ),
                  ),
                ],
              ),
            ),
          if (scanned != null)
            row(
              "Amount",
              Text("₱${money.format(scanned)}",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
            ),
          if (scanned != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                mismatch
                    ? "Doesn't match the ₱${money.format(expected)} the customer should have sent — check the receipt image."
                    : "Matches the ₱${money.format(expected)} due.",
                style: TextStyle(fontSize: 11.5, height: 1.35, color: AppPalette.textSecondary(context)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text("Auto-read by the app — always verify against the receipt image.",
                style: TextStyle(fontSize: 10.5, color: AppPalette.textMuted(context))),
          ),
        ],
      ),
    ),
  ];
}
