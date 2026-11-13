import '../../shared/app_modal.dart';
import '../../shared/top_toast.dart';
import 'refund_requests_screen.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../models/activity_log_entry.dart';
import '../models/booking_record.dart';
import '../models/customer_summary.dart';
import '../services/activity_filter.dart';
import '../widgets/refunds_to_send.dart';
import '../widgets/refund_decision_dialog.dart';
import '../widgets/refund_sent_dialog.dart';
import '../models/camera_rental_record.dart';
import '../models/feedback_record.dart';
import '../models/pos_transaction_record.dart';
import '../services/activity_log_repository.dart';
import '../services/admin_service.dart';
import '../services/admin_settings.dart';
import '../services/block_repository.dart';
import '../services/booking_repository.dart';
import '../services/camera_rental_repository.dart';
import '../services/feedback_repository.dart';
import '../services/finance_export.dart';
import '../services/pos_repository.dart';
import '../models/pricing_item_record.dart';
import '../services/pricing_repository.dart';
import '../services/user_account_repository.dart';
import '../theme/app_colors.dart';
import '../../shared/top_alert.dart';
import '../theme/app_palette.dart';
import '../widgets/dashboard_kit.dart';
import '../widgets/glass_bottom_nav.dart';
import '../widgets/more_menu_sheet.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/reschedule_dialog.dart';
import '../widgets/revenue_charts.dart';
import '../models/shift_closing_record.dart';
import '../services/shift_closing_repository.dart';
import 'admin_announcements_screen.dart';
import 'admin_calendar_screen.dart';
import 'admin_event_photos_screen.dart';
import 'admin_camera_rentals_screen.dart';
import 'admin_feedback_screen.dart';
import 'admin_login_screen.dart';
import 'admin_messages_screen.dart';
import 'admin_pricing_screen.dart';
import 'admin_profile_screen.dart';
import 'admin_settings_screen.dart';
import 'admin_staff_screen.dart';

/// Sections that get their own slot in the phone's floating bottom nav.
/// Kept to 4 (+ a trailing "More" tab) so the pill never gets cramped on a
/// 360px-wide phone; every other section is reached through the "More"
/// sheet ([_openMoreMenu]). To promote/demote a section, edit this list and
/// [_kAdminNavTabs] together — they must stay in the same order.
const List<_AdminSection> _kAdminPrimarySections = [
  _AdminSection.dashboard,
  _AdminSection.bookings,
  _AdminSection.cameraRentals,
  _AdminSection.messages,
];

/// Tabs for the floating glass bottom nav: one per entry in
/// [_kAdminPrimarySections], then [kMoreNavTab].
const List<NavTabItem> _kAdminNavTabs = [
  NavTabItem(icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard, label: "Dashboard"),
  NavTabItem(icon: Icons.event_note_outlined, activeIcon: Icons.event_note, label: "Bookings"),
  NavTabItem(icon: Icons.camera_alt_outlined, activeIcon: Icons.camera_alt, label: "Rentals"),
  NavTabItem(icon: Icons.chat_bubble_outline, activeIcon: Icons.chat_bubble, label: "Messages"),
  kMoreNavTab,
];

/// Every section the admin can open. On desktop they're all in the sidebar;
/// on phones the ones in [_kAdminPrimarySections] are bottom-nav tabs and
/// the rest live in the "More" sheet — both just set `_section`.
enum _AdminSection { dashboard, bookings, cameraRentals, calendar, eventPhotos, refundRequests, feedback, messages, announcements, liveQueue, loyalty, financialLogs, activityLog, customers, staff, pricing, profile, settings }

/// The admin panel — this app's home screen once signed in. Same Flutter
/// widgets, same codebase, on desktop and mobile; the difference comes
/// from a single `LayoutBuilder` breakpoint. A separate project from the
/// Staff app (`photobooth_staff_demo`), which has the same Bookings/
/// Camera Rentals/Calendar/Feedback/Messages sections but not Staff or
/// Pricing.
///
/// Wide windows (desktop/web) get a persistent left sidebar (branding, nav,
/// sign out) plus a two-pane master-detail bookings view. Narrow windows
/// (phone) get a plain AppBar + bottom nav and a single list that pushes a
/// detail screen — no sidebar, since there isn't room for one.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  static const double _desktopBreakpoint = 900;

  _AdminSection _section = _AdminSection.dashboard;
  BookingRecord? _selected;
  bool _bulkSelectMode = false;
  final Set<String> _bulkSelectedIds = {};

  /// Ids of completed bookings in the current list — never selectable for
  /// deletion. Refreshed every time the Bookings list is built.
  Set<String> _completedBookingIds = {};
  final TextEditingController _bookingSearchController = TextEditingController();
  String _bookingSearchQuery = '';
  String _bookingStatusFilter = 'all'; // 'all' | booking status key
  String _posPaymentFilter = 'all'; // 'all' | 'cash' | 'gcash'
  String _posStaffFilter = 'all'; // 'all' | a staff email
  String _activityRoleFilter = 'all'; // 'all' | 'admin' | 'staff'
  final TextEditingController _activitySearchController = TextEditingController();
  String _activityQuery = '';
  ActivityCategory _activityCategory = ActivityCategory.all;
  String _activityRange = 'all'; // 'all' | 'today' | 'week' | 'month'
  int _activityPage = 0;
  int _activityLimit = 300; // how many of the newest log entries are loaded
  // Financial Logs period: today | week | month | all. A notifier (not plain
  // state) so the page also updates when pushed as its own route on mobile.
  final ValueNotifier<String> _financePeriod = ValueNotifier<String>('month');
  final TextEditingController _customerSearchController = TextEditingController();
  String _customerQuery = '';
  String _customerSort = 'spent'; // 'spent' | 'bookings' | 'recent'
  int _customerPage = 0;

  static const List<List<String>> _bookingCategories = [
    ['all', 'All'],
    ['pending_confirmation', 'Pending'],
    ['awaiting_receipt', 'Awaiting receipt'],
    ['confirmed', 'Confirmed'],
    ['completed', 'Completed'],
    ['cancelled', 'Rejected'],
  ];

  /// Category chips for Booking Management (filters the list by status).
  Widget _bookingCategoryChips(BuildContext context, List<BookingRecord> bookings) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final c in _bookingCategories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Builder(builder: (context) {
                final selected = _bookingStatusFilter == c[0];
                final count = c[0] == 'all' ? bookings.length : bookings.where((b) => b.status == c[0]).length;
                return ChoiceChip(
                  label: Text('${c[1]} ($count)'),
                  selected: selected,
                  onSelected: (_) => setState(() {
                    _bookingStatusFilter = c[0];
                    _selected = null;
                    _bulkSelectedIds.clear();
                  }),
                  labelStyle: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppPalette.textPrimary(context),
                  ),
                  selectedColor: AppColors.accent,
                  backgroundColor: AppPalette.surface(context),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999), side: BorderSide.none),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                );
              }),
            ),
        ],
      ),
    );
  }

  List<BookingRecord> _applyBookingSearch(List<BookingRecord> bookings) {
    final q = _bookingSearchQuery.trim().toLowerCase();
    if (_bookingStatusFilter != 'all') {
      bookings = bookings.where((b) => b.status == _bookingStatusFilter).toList();
    }
    if (q.isEmpty) return bookings;
    return bookings.where((b) {
      return b.userId.toLowerCase().contains(q) ||
          b.customerName.toLowerCase().contains(q) ||
          b.bookingRef.toLowerCase().contains(q) ||
          b.id.toLowerCase().contains(q) ||
          b.packageName.toLowerCase().contains(q);
    }).toList();
  }

  void _toggleBulkSelect(String id) {
    if (_completedBookingIds.contains(id)) return; // finished bookings can't be deleted
    setState(() {
      if (_bulkSelectedIds.contains(id)) {
        _bulkSelectedIds.remove(id);
      } else {
        _bulkSelectedIds.add(id);
      }
    });
  }

  void _exitBulkSelectMode() {
    setState(() {
      _bulkSelectMode = false;
      _bulkSelectedIds.clear();
    });
  }

  Future<void> _deleteSelectedBookings() async {
    final ids = _bulkSelectedIds.where((id) => !_completedBookingIds.contains(id)).toList();
    if (ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: AppColors.accent),
        title: Text("Delete ${ids.length} booking${ids.length == 1 ? '' : 's'}?"),
        content: const Text(
          "This permanently removes these booking records — there's no undo.",
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text("Cancel")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    int failures = 0;
    for (final id in ids) {
      try {
        await BookingRepository.deleteBooking(id);
      } catch (_) {
        failures++;
      }
    }
    if (!mounted) return;
    _exitBulkSelectMode();
    if (_selected != null && ids.contains(_selected!.id)) {
      setState(() => _selected = null);
    }
    TopToast.show(context, failures == 0
              ? "Deleted ${ids.length} booking${ids.length == 1 ? '' : 's'}."
              : "Deleted ${ids.length - failures} of ${ids.length} — $failures failed.");
  }

  /// Drives the 15-minute-hold sweep. Bookings the customer never sent a
  /// receipt for get auto-rejected, so they show up as rejected here
  /// without anyone having to chase them by hand. A scheduled Cloud
  /// Function is the better home for this in production (it keeps running
  /// with no dashboard open) — this timer keeps the behaviour working
  /// while the app is the only thing deployed.
  Timer? _holdSweepTimer;

  /// "New booking alerts" (Settings): watches for bookings that newly need
  /// approval while this dashboard is open and pops up a snackbar.
  StreamSubscription<List<BookingRecord>>? _newBookingSub;
  Set<String>? _knownPendingIds; // null until the first snapshot (baseline)
  final DateTime _sessionStart = DateTime.now();

  @override
  void initState() {
    super.initState();
    AdminSettings.load(); // no-op if main_admin.dart already loaded it
    _sweepExpiredHolds();
    _holdSweepTimer = Timer.periodic(const Duration(seconds: 30), (_) => _sweepExpiredHolds());
    _listenForNewBookings();
  }

  void _listenForNewBookings() {
    _newBookingSub = BookingRepository.watchAllBookings().listen((bookings) {
      final pending = bookings.where((b) => b.status == 'pending_confirmation').toList();
      final known = _knownPendingIds;
      _knownPendingIds = pending.map((b) => b.id).toSet();
      if (known == null || !mounted) return; // first snapshot = baseline, no alert
      if (!AdminSettings.notifyNewBookings.value) return;
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
    final who = first.customerName.trim().isEmpty ? 'a customer' : shortenForAlert(first.customerName);
    final single = fresh.length == 1;
    TopAlert.show(
      context,
      title: single ? 'New booking' : '${fresh.length} new bookings',
      message: single ? '$who needs approval' : 'They need approval',
      accent: AppColors.accent,
      onAction: () => _goToBooking(first, isDesktop: MediaQuery.of(context).size.width >= _desktopBreakpoint),
    );
  }

  @override
  void dispose() {
    _newBookingSub?.cancel();
    _holdSweepTimer?.cancel();
    _bookingSearchController.dispose();
    _financePeriod.dispose();
    _customerSearchController.dispose();
    _activitySearchController.dispose();
    super.dispose();
  }

  Future<void> _sweepExpiredHolds() async {
    try {
      await BookingRepository.expireStaleHolds();
    } catch (_) {
      // Offline or a transient permission hiccup — the next tick retries.
    }
  }

  Future<void> _logout() async {
    await AdminService.instance.signOutAdmin();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
    );
  }

  void _goToBooking(BookingRecord booking, {required bool isDesktop}) {
    setState(() {
      _section = _AdminSection.bookings;
      _selected = booking;
    });
    if (!isDesktop) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _AdminBookingDetailScreen(booking: booking)),
      );
    }
  }

  void _goToRentals({required bool isDesktop}) {
    setState(() => _section = _AdminSection.cameraRentals);
  }

  /// Which bottom-nav slot is lit. Anything that isn't a primary tab is
  /// reached through "More", so that tab lights up instead. Profile/Settings
  /// (opened from the avatar / Profile screen) keep no tab lit.
  int get _bottomNavIndex {
    if (_section == _AdminSection.profile || _section == _AdminSection.settings) return -1;
    final i = _kAdminPrimarySections.indexOf(_section);
    return i >= 0 ? i : _kAdminNavTabs.length - 1;
  }

  void _onBottomNavTap(int i) {
    if (i < _kAdminPrimarySections.length) {
      setState(() => _section = _kAdminPrimarySections[i]);
    } else {
      _openMoreMenu();
    }
  }

  /// Phone-only: the "More" tab's sheet. Lists every section that doesn't
  /// have its own bottom-nav tab (plus Profile/Settings, dark mode and
  /// sign out). Tiles switch `_section` just like the desktop sidebar does,
  /// so the bottom nav and header title stay put instead of pushing a
  /// separate route.
  void _openMoreMenu() {
    MoreMenuItem item(IconData icon, String label, _AdminSection target) => MoreMenuItem(
          icon: icon,
          label: label,
          selected: _section == target,
          onTap: () => setState(() => _section = target),
        );

    showMoreMenuSheet(
      context,
      onLogout: _logout,
      groups: [
        MoreMenuGroup(title: "Operations", items: [
          item(Icons.calendar_month_rounded, "Calendar", _AdminSection.calendar),
          item(Icons.photo_library_rounded, "Event Photos", _AdminSection.eventPhotos),
          item(Icons.undo_rounded, "Refund Requests", _AdminSection.refundRequests),
          item(Icons.hourglass_top_rounded, "Live Queue", _AdminSection.liveQueue),
          item(Icons.people_alt_rounded, "Customers", _AdminSection.customers),
          item(Icons.star_rounded, "Feedback", _AdminSection.feedback),
          item(Icons.campaign_rounded, "Announcements", _AdminSection.announcements),
        ]),
        MoreMenuGroup(title: "Records", items: [
          item(Icons.receipt_long_rounded, "Financial Logs", _AdminSection.financialLogs),
          item(Icons.history_rounded, "Activity Log", _AdminSection.activityLog),
          item(Icons.nfc_rounded, "RFID Loyalty", _AdminSection.loyalty),
        ]),
        MoreMenuGroup(title: "Manage", items: [
          item(Icons.badge_rounded, "Staff", _AdminSection.staff),
          item(Icons.sell_rounded, "Pricing", _AdminSection.pricing),
        ]),
        MoreMenuGroup(title: "Account", items: [
          item(Icons.person_rounded, "My Profile", _AdminSection.profile),
          item(Icons.settings_rounded, "Settings", _AdminSection.settings),
        ]),
      ],
    );
  }

  Future<void> _openNotifications({required bool isDesktop}) async {
    if (isDesktop) {
      // Anchored dropdown near the bell — fades/scales in from the
      // top-right, like the reference design's notification popover,
      // instead of sliding up from the bottom of the whole screen.
      await showGeneralDialog<void>(
        context: context,
        barrierLabel: 'Notifications',
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.05),
        transitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (dialogContext, _, __) {
          return Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 66, right: 24),
              child: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: 400,
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
    await showAppModal<void>(
      context,
      maxWidth: 520,
      builder: (sheetContext) {
        return _NotificationsPanel(
          isDesktop: false,
          onGoToBooking: (b) {
            Navigator.of(sheetContext).pop();
            _goToBooking(b, isDesktop: false);
          },
          onGoToRentals: () {
            Navigator.of(sheetContext).pop();
            _goToRentals(isDesktop: false);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= _desktopBreakpoint;

        if (isDesktop) {
          return Scaffold(
            // Soft grey/cream canvas: the floating sidebar, the top bar and
            // every section sit on it as rounded cards.
            backgroundColor: AppPalette.surface(context),
            body: Stack(
              children: [
                Row(
                  children: [
                    // Only the slim icon rail reserves space — the expanded
                    // sidebar floats over the content on hover instead of
                    // pushing it.
                    const SizedBox(width: _AdminSidebar.railWidth),
                    Expanded(
                      child: Column(
                        children: [
                          _AdminTopBar(
                            onSearchSubmitted: (q) => setState(() {
                              _section = _AdminSection.bookings;
                              _bookingSearchQuery = q;
                              _bookingSearchController.text = q;
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
                  child: _AdminSidebar(
                    section: _section,
                    onSelectSection: (s) => setState(() => _section = s),
                    onLogout: _logout,
                    onOpenNotifications: () => _openNotifications(isDesktop: true),
                  ),
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
        // any other section returns to the Dashboard tab first.
        return PopScope(
          canPop: _section == _AdminSection.dashboard,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(() => _section = _AdminSection.dashboard);
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
                              initials: "AD",
                              onAvatarTap: () => setState(() => _section = _AdminSection.profile),
                              // Phone header = avatar + title + bell. Dark mode,
                              // sign out and the long tail of sections moved
                              // into the "More" sheet; the logo badge is dropped
                              // so long titles ("Booking Management") fit.
                              showLogo: false,
                              actions: [
                                DashboardHeaderAction(
                                  icon: Icons.notifications_outlined,
                                  tooltip: "Notifications",
                                  trailingGap: 0,
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
                      tabs: _kAdminNavTabs,
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

  String _sectionTitle(_AdminSection s) {
    switch (s) {
      case _AdminSection.dashboard:
        return "Dashboard";
      case _AdminSection.bookings:
        return "Booking Management";
      case _AdminSection.cameraRentals:
        return "Camera Rental";
      case _AdminSection.calendar:
        return "Calendar";
      case _AdminSection.eventPhotos:
        return "Event Photos";
      case _AdminSection.refundRequests:
        return "Refund Requests";
      case _AdminSection.feedback:
        return "Feedback";
      case _AdminSection.messages:
        return "Messages";
      case _AdminSection.announcements:
        return "Announcements";
      case _AdminSection.liveQueue:
        return "Live Queue & Timers";
      case _AdminSection.loyalty:
        return "RFID Loyalty Rewards";
      case _AdminSection.financialLogs:
        return "Financial Receipts/Logs";
      case _AdminSection.activityLog:
        return "Activity Log";
      case _AdminSection.customers:
        return "Customers";
      case _AdminSection.staff:
        return "Staff";
      case _AdminSection.pricing:
        return "Pricing";
      case _AdminSection.profile:
        return "My Profile";
      case _AdminSection.settings:
        return "Settings";
    }
  }

  Widget _buildSectionArea(BuildContext context, {required bool isDesktop}) {
    switch (_section) {
      case _AdminSection.dashboard:
        return _buildDashboardHome(context, isDesktop: isDesktop);
      case _AdminSection.bookings:
        return _buildBookingsArea(context, isDesktop: isDesktop);
      case _AdminSection.cameraRentals:
        return isDesktop
            ? _withDesktopHeader(context, "Camera Rental", const AdminCameraRentalsScreen())
            : const AdminCameraRentalsScreen();
      case _AdminSection.calendar:
        return isDesktop ? _withDesktopHeader(context, "Calendar", const AdminCalendarScreen()) : const AdminCalendarScreen();
      case _AdminSection.eventPhotos:
        return isDesktop
            ? _withDesktopHeader(context, "Event Photos", const AdminEventPhotosScreen())
            : const AdminEventPhotosScreen();
      case _AdminSection.refundRequests:
        return isDesktop
            ? _withDesktopHeader(context, "Refund Requests", const RefundRequestsScreen())
            : const RefundRequestsScreen();
      case _AdminSection.feedback:
        return isDesktop ? _withDesktopHeader(context, "Feedback", const AdminFeedbackScreen()) : const AdminFeedbackScreen();
      case _AdminSection.messages:
        return isDesktop ? _withDesktopHeader(context, "Messages", const AdminMessagesScreen()) : const AdminMessagesScreen();
      case _AdminSection.announcements:
        return isDesktop
            ? _withDesktopHeader(context, "Announcements", const AdminAnnouncementsScreen())
            : const AdminAnnouncementsScreen();
      case _AdminSection.liveQueue:
        return isDesktop
            ? _withDesktopHeader(context, "Live Queue & Timers", _buildLiveQueuePage(context, isDesktop: true))
            : _buildLiveQueuePage(context, isDesktop: false);
      case _AdminSection.loyalty:
        const loyaltyStub = _ComingSoonSection(
          icon: Icons.nfc_rounded,
          title: "RFID Loyalty Rewards",
        );
        return isDesktop ? _withDesktopHeader(context, "RFID Loyalty Rewards", loyaltyStub) : loyaltyStub;
      case _AdminSection.financialLogs:
        final logsPage = _buildFinancialLogsPage(context, isDesktop: isDesktop);
        return isDesktop ? _withDesktopHeader(context, "Financial Receipts/Logs", logsPage) : logsPage;
      case _AdminSection.activityLog:
        final activityPage = _buildActivityLogPage(context);
        return isDesktop ? _withDesktopHeader(context, "Activity Log", activityPage) : activityPage;
      case _AdminSection.customers:
        final customersPage = _buildCustomersPage(context, isDesktop: isDesktop);
        return isDesktop ? _withDesktopHeader(context, "Customers", customersPage) : customersPage;
      case _AdminSection.staff:
        return isDesktop ? _withDesktopHeader(context, "Staff", const AdminStaffScreen()) : const AdminStaffScreen();
      case _AdminSection.pricing:
        return isDesktop ? _withDesktopHeader(context, "Pricing", const AdminPricingScreen()) : const AdminPricingScreen();
      case _AdminSection.profile:
        final profile = AdminProfileScreen(
          onOpenSettings: () => setState(() => _section = _AdminSection.settings),
          onLogout: _logout,
        );
        return isDesktop ? _withDesktopHeader(context, "My Profile", profile) : profile;
      case _AdminSection.settings:
        final settings = AdminSettingsScreen(
          onChangePassword: () => _showAdminChangePasswordDialog(context),
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
  /// grey canvas (same as the Staff dashboard).
  Widget _withDesktopHeader(BuildContext context, String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 20, 20),
      child: Container(
        decoration: _cardDecoration(context),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
              child: Row(
                children: [
                  Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppPalette.textPrimary(context))),
                ],
              ),
            ),
            Divider(height: 1, color: AppPalette.divider(context)),
            Expanded(child: child),
          ],
        ),
      ),
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
        final filtered = _applyBookingSearch(bookings);
        final searchBar = _BookingSearchBar(
          controller: _bookingSearchController,
          onChanged: (q) => setState(() => _bookingSearchQuery = q),
        );

        Widget body;
        if (bookings.isEmpty) {
          body = Center(
            child: Text("No bookings yet.", style: TextStyle(color: AppPalette.textMuted(context))),
          );
        } else if (filtered.isEmpty) {
          body = Center(
            child: Text(_bookingStatusFilter == 'all' ? "No bookings match your search." : "No bookings in this category.", style: TextStyle(color: AppPalette.textMuted(context))),
          );
        } else {
          _completedBookingIds = {for (final b in bookings) if (b.status == 'completed') b.id};
          final list = _BookingList(
            bookings: filtered,
            selectedId: isDesktop ? _selected?.id : null,
            selectMode: _bulkSelectMode,
            selectedIds: _bulkSelectedIds,
            onToggleSelect: _toggleBulkSelect,
            onTap: (b) {
              if (_bulkSelectMode) {
                _toggleBulkSelect(b.id);
              } else if (isDesktop) {
                setState(() => _selected = b);
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => _AdminBookingDetailScreen(booking: b)),
                );
              }
            },
          );

          if (!isDesktop) {
            body = list;
          } else {
            final detail = _selected != null
                ? _BookingDetailPane(booking: _selected!, onDeleted: () => setState(() => _selected = null))
                : Center(
                    child: Text("Select a booking to view details", style: TextStyle(color: AppPalette.textMuted(context))),
                  );

            body = Row(
              children: [
                SizedBox(width: 380, child: list),
                VerticalDivider(width: 1, color: AppPalette.divider(context)),
                Expanded(child: detail),
              ],
            );
          }
        }

        final selectToolbar = _bulkSelectMode
            ? _BulkSelectToolbar(
                selectedCount: _bulkSelectedIds.length,
                totalCount: filtered.where((b) => b.status != 'completed').length,
                onSelectAll: () => setState(() => _bulkSelectedIds
                  ..clear()
                  ..addAll(filtered.where((b) => b.status != 'completed').map((b) => b.id))),
                onClear: () => setState(() => _bulkSelectedIds.clear()),
                onDelete: _bulkSelectedIds.isEmpty ? null : _deleteSelectedBookings,
                onCancel: _exitBulkSelectMode,
              )
            : null;

        if (!isDesktop) {
          final pendingCount = bookings.where((b) => b.status == 'pending_confirmation').length;
          final confirmedCount = bookings.where((b) => b.status == 'confirmed').length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: DashboardHeroBanner(
                  watermarkIcon: Icons.admin_panel_settings,
                  pillLabel: "ADMIN PORTAL",
                  title: "Business Overview",
                  subtitle: "Bookings, rentals, staff & pricing in one place.",
                  stats: [
                    HeroStat(value: '${bookings.length}', label: 'Total bookings'),
                    HeroStat(value: '$pendingCount', label: 'Pending'),
                    HeroStat(value: '$confirmedCount', label: 'Confirmed'),
                  ],
                ),
              ),
              if (selectToolbar != null) selectToolbar,
              if (selectToolbar == null && bookings.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _bulkSelectMode = true),
                      icon: const Icon(Icons.checklist, size: 16),
                      label: const Text("Select"),
                    ),
                  ),
                ),
              RefundsToSendBanner(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                onMarkRefunded: (b, reference) => BookingRepository.markRefunded(b.id, reference: reference),
              ),
              if (bookings.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: _bookingCategoryChips(context, bookings),
                ),
              if (bookings.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: searchBar,
                ),
              Expanded(child: body),
            ],
          );
        }

        // Desktop has no AppBar (the sidebar carries branding/sign out),
        // so give the content pane its own small header instead. The KPI
        // overview now lives on the separate Dashboard section instead of
        // duplicating it here.
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 20, 20),
          child: Container(
            decoration: _cardDecoration(context),
            clipBehavior: Clip.antiAlias,
            child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
              child: Row(
                children: [
                  Text("Booking Management", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppPalette.textPrimary(context))),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _bookingCategoryChips(context, bookings),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (!_bulkSelectMode && bookings.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => setState(() => _bulkSelectMode = true),
                      icon: const Icon(Icons.checklist, size: 16),
                      label: const Text("Select"),
                    )
                  else
                    Text('${filtered.length} of ${bookings.length}', style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
                ],
              ),
            ),
            if (selectToolbar != null) selectToolbar,
            RefundsToSendBanner(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              onMarkRefunded: (b, reference) => BookingRepository.markRefunded(b.id, reference: reference),
            ),
            if (bookings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
                child: searchBar,
              ),
            Divider(height: 1, color: AppPalette.divider(context)),
            Expanded(child: body),
          ],
            ),
          ),
        );
      },
    );
  }

  /// [start, end) for a Financial Logs period, or null for "all time".
  /// "This week" runs Monday–Sunday; "This month" is the calendar month.
  DateTimeRange? _financeRange(String period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (period) {
      case 'today':
        return DateTimeRange(start: today, end: DateTime(today.year, today.month, today.day + 1));
      case 'week':
        final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
        return DateTimeRange(start: monday, end: DateTime(monday.year, monday.month, monday.day + 7));
      case 'month':
        return DateTimeRange(start: DateTime(now.year, now.month), end: DateTime(now.year, now.month + 1));
      default:
        return null;
    }
  }

  String _financePeriodLabel(String period, DateTimeRange? range) {
    if (range == null) return 'All time';
    final lastDay = DateTime(range.end.year, range.end.month, range.end.day - 1);
    switch (period) {
      case 'today':
        return 'Today · ${DateFormat('EEE, MMM d').format(range.start)}';
      case 'week':
        return 'This week · ${DateFormat('MMM d').format(range.start)} – ${DateFormat('MMM d').format(lastDay)}';
      default:
        return 'This month · ${DateFormat('MMMM y').format(range.start)}';
    }
  }

  List<RevenueBucket> _financeBuckets(String period, DateTimeRange? range, List<RevenueEntry> periodEntries) {
    final r = range;
    if (r == null) return RevenueBuckets.monthly(periodEntries);
    switch (period) {
      case 'today':
        return RevenueBuckets.hourly(periodEntries, r.start);
      case 'week':
        return RevenueBuckets.daily(periodEntries, r.start, 7, label: (d) => DateFormat('E').format(d), showLabel: (_, __) => true);
      default:
        final days = DateTime(r.start.year, r.start.month + 1, 0).day;
        return RevenueBuckets.daily(periodEntries, r.start, days, label: (d) => '${d.day}', showLabel: (i, d) => d.day == 1 || d.day % 5 == 0);
    }
  }

  String _financeChartTitle(String period) {
    switch (period) {
      case 'today':
        return 'Revenue by hour';
      case 'all':
        return 'Revenue by month';
      default:
        return 'Revenue by day';
    }
  }

  bool _exportingFinance = false;

  /// Builds the report for the period on screen and either saves it as a PDF
  /// or copies it as CSV (paste straight into Excel / Google Sheets).
  Future<void> _exportFinance({
    required bool pdf,
    required String periodLabel,
    required DateTimeRange? range,
    required int totalRevenue,
    required int onlineRevenue,
    required int posRevenue,
    required int cashRevenue,
    required int gcashRevenue,
    required List<BookingRecord> bookings,
    required List<PosTransactionRecord> sales,
  }) async {
    if (_exportingFinance) return;
    setState(() => _exportingFinance = true);
    try {
      bool inRange(DateTime d) => range == null || (!d.isBefore(range.start) && d.isBefore(range.end));
      final allClosings = await ShiftClosingRepository.watchRecent().first;
      final report = FinanceReport(
        periodLabel: periodLabel,
        totalRevenue: totalRevenue,
        onlineRevenue: onlineRevenue,
        posRevenue: posRevenue,
        cashRevenue: cashRevenue,
        gcashRevenue: gcashRevenue,
        bookings: bookings,
        sales: sales,
        closings: allClosings.where((c) => inRange(c.closedAt)).toList(),
      );
      if (pdf) {
        final bytes = await FinanceExport.buildPdf(report);
        await Printing.sharePdf(bytes: bytes, filename: 'memoriae-financial-report-${FinanceExport.fileStamp()}.pdf');
      } else {
        await Clipboard.setData(ClipboardData(text: FinanceExport.buildCsv(report)));
        TopToast.show(null, "CSV copied. Paste it into Excel or Google Sheets.");
      }
    } catch (e) {
      TopToast.show(null, "Couldn't export the report: $e", kind: TopToastKind.error);
    } finally {
      if (mounted) setState(() => _exportingFinance = false);
    }
  }

  Widget _financePeriodBar(BuildContext context, String period) {
    Widget chip(String value, String label) {
      final selected = period == value;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _financePeriod.value = value,
        labelStyle: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppPalette.textPrimary(context)),
        selectedColor: AppColors.accent,
        backgroundColor: AppPalette.surface(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999), side: BorderSide.none),
        showCheckmark: false,
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [chip('today', 'Today'), chip('week', 'This week'), chip('month', 'This month'), chip('all', 'All time')],
    );
  }

  /// Financial Receipts/Logs — a real ledger, not a placeholder: every
  /// booking that has a payment receipt attached, plus every over-the-
  /// counter POS sale from the Staff app, newest first, for the chosen
  /// period (today / this week / this month / all time). Total Revenue,
  /// the charts and both breakdowns are all computed from one shared list
  /// (`RevenueEntry.fromRecords`) so they always agree — and a walk-in
  /// booking's payment is counted once, not as both a booking and a POS
  /// sale. Built entirely from data that already exists rather than a new
  /// "reporting" collection.
  Widget _buildFinancialLogsPage(BuildContext context, {required bool isDesktop}) {
    // Listens to the period notifier (instead of plain setState) so the
    // page also updates when it's pushed as its own route on mobile.
    return ValueListenableBuilder<String>(
      valueListenable: _financePeriod,
      builder: (context, period, _) {
        return StreamBuilder<List<BookingRecord>>(
          stream: BookingRepository.watchAllBookings(),
          builder: (context, bookingSnapshot) {
            final bookings = bookingSnapshot.data ?? const <BookingRecord>[];
            return StreamBuilder<List<PosTransactionRecord>>(
              stream: PosRepository.watchAllTransactions(),
              builder: (context, posSnapshot) {
                final allSales = posSnapshot.data ?? const <PosTransactionRecord>[];
                final range = _financeRange(period);
                bool inRange(DateTime? d) => range == null || (d != null && !d.isBefore(range.start) && d.isBefore(range.end));
                String money(int v) => '₱${NumberFormat('#,##0').format(v)}';

                final periodEntries = RevenueEntry.fromRecords(bookings, allSales).where((e) => inRange(e.when)).toList();
                int sumWhere(bool Function(RevenueEntry e) test) => periodEntries.where(test).fold<int>(0, (s, e) => s + e.amount);
                final totalRevenue = sumWhere((_) => true);
                final onlineRevenue = sumWhere((e) => e.source == RevenueSource.online);
                final posRevenue = sumWhere((e) => e.source == RevenueSource.pos);
                final cashRevenue = sumWhere((e) => e.source == RevenueSource.pos && e.method == 'cash');
                final gcashRevenue = sumWhere((e) => e.source == RevenueSource.pos && e.method == 'gcash');
                final otherPosRevenue = posRevenue - cashRevenue - gcashRevenue;

                final withReceipts = bookings.where((b) => b.receiptUrl.isNotEmpty && inRange(b.createdAt ?? b.date)).toList()
                  ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
                final periodSales = allSales.where((s) => inRange(s.createdAt)).toList();
                final staffEmails = allSales.map((s) => s.staffEmail).where((e) => e.isNotEmpty).toSet().toList()..sort();

                final filteredSales = periodSales.where((s) {
                  final paymentOk = _posPaymentFilter == 'all' || s.paymentMethod == _posPaymentFilter;
                  final staffOk = _posStaffFilter == 'all' || s.staffEmail == _posStaffFilter;
                  return paymentOk && staffOk;
                }).toList();

                final cards = [
                  _AdminStatCard(icon: Icons.payments_rounded, iconColor: AppColors.success, value: money(totalRevenue), label: 'Total revenue'),
                  _AdminStatCard(icon: Icons.receipt_long_rounded, iconColor: AppColors.accent, value: '${withReceipts.length}', label: 'Booking receipts'),
                  _AdminStatCard(icon: Icons.point_of_sale_rounded, iconColor: const Color(0xFF3B82F6), value: '${periodSales.length}', label: 'POS sales (${money(posRevenue)})'),
                ];
                final summary = isDesktop
                    ? Row(children: [for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(width: 14), Expanded(child: cards[i])]])
                    : Column(children: [
                        Row(children: [Expanded(child: cards[0]), const SizedBox(width: 12), Expanded(child: cards[1])]),
                        const SizedBox(height: 12),
                        cards[2],
                      ]);

                final sourceSplit = RevenueSplitCard(
                  title: 'Where the money came from',
                  subtitle: 'Online bookings vs counter (POS) sales',
                  segments: [
                    SplitSegment(label: 'Online bookings', amount: onlineRevenue, color: AppColors.accent),
                    SplitSegment(label: 'Counter sales (POS)', amount: posRevenue, color: const Color(0xFF3B82F6)),
                  ],
                );
                final methodSplit = RevenueSplitCard(
                  title: 'Counter sales by payment method',
                  subtitle: 'Online bookings pay by uploaded receipt, so they\'re not in this split',
                  segments: [
                    SplitSegment(label: 'Cash', amount: cashRevenue, color: AppColors.success),
                    SplitSegment(label: 'GCash', amount: gcashRevenue, color: const Color(0xFF3B82F6)),
                    if (otherPosRevenue > 0) SplitSegment(label: 'Other', amount: otherPosRevenue, color: AppColors.highlight),
                  ],
                );
                final splits = isDesktop
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: sourceSplit), const SizedBox(width: 14), Expanded(child: methodSplit)])
                    : Column(children: [sourceSplit, const SizedBox(height: 12), methodSplit]);

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _financePeriodBar(context, period),
                      const SizedBox(height: 10),
                      Text(_financePeriodLabel(period, range), style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final asPdf in const [true, false])
                            OutlinedButton.icon(
                              onPressed: _exportingFinance
                                  ? null
                                  : () => _exportFinance(
                                        pdf: asPdf,
                                        periodLabel: _financePeriodLabel(period, range),
                                        range: range,
                                        totalRevenue: totalRevenue,
                                        onlineRevenue: onlineRevenue,
                                        posRevenue: posRevenue,
                                        cashRevenue: cashRevenue,
                                        gcashRevenue: gcashRevenue,
                                        bookings: withReceipts,
                                        sales: periodSales,
                                      ),
                              icon: Icon(asPdf ? Icons.picture_as_pdf_outlined : Icons.copy_all_outlined, size: 16),
                              label: Text(asPdf ? "Export PDF" : "Copy as CSV", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.accent,
                                side: const BorderSide(color: AppColors.accent),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      summary,
                      const SizedBox(height: 18),
                      RevenueChartCard(
                        title: _financeChartTitle(period),
                        subtitle: _financePeriodLabel(period, range),
                        total: totalRevenue,
                        chart: RevenueBarChart(buckets: _financeBuckets(period, range, periodEntries), height: isDesktop ? 190 : 170),
                      ),
                      const SizedBox(height: 14),
                      splits,
                      const SizedBox(height: 26),
                      Text("Booking Payments", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                      const SizedBox(height: 4),
                      Text(
                        "Every booking with a payment receipt attached in this period, most recent first.",
                        style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
                      ),
                      const SizedBox(height: 14),
                      if (withReceipts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: Text("No receipts on file for this period.", style: TextStyle(color: AppPalette.textMuted(context)))),
                        )
                      else
                        ...withReceipts.map((b) => _receiptLogRow(context, b)),
                      const SizedBox(height: 26),
                      Row(
                        children: [
                          Icon(Icons.point_of_sale_rounded, size: 15, color: AppPalette.textPrimary(context)),
                          const SizedBox(width: 6),
                          Text("Counter Sales (POS)", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Walk-in sales rung up by staff — packages, rental fees, and add-ons.",
                        style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
                      ),
                      const SizedBox(height: 12),
                      _posFilterBar(context, staffEmails),
                      const SizedBox(height: 12),
                      if (periodSales.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: Text("No POS sales in this period.", style: TextStyle(color: AppPalette.textMuted(context)))),
                        )
                      else if (filteredSales.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: Text("No sales match this filter.", style: TextStyle(color: AppPalette.textMuted(context)))),
                        )
                      else
                        ...filteredSales.map((s) => _posSaleRow(context, s)),
                      const SizedBox(height: 26),
                      Row(
                        children: [
                          Icon(Icons.point_of_sale_rounded, size: 15, color: AppPalette.textPrimary(context)),
                          const SizedBox(width: 6),
                          Text("Shift Close-outs", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Cash counts staff submitted when closing their shift, and whether the drawer matched what the POS expected.",
                        style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<List<ShiftClosingRecord>>(
                        stream: ShiftClosingRepository.watchRecent(),
                        builder: (context, closingSnap) {
                          final closings = (closingSnap.data ?? const <ShiftClosingRecord>[]).where((c) => inRange(c.closedAt)).toList();
                          if (closings.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Center(child: Text("No shift close-outs in this period.", style: TextStyle(color: AppPalette.textMuted(context)))),
                            );
                          }
                          return Column(children: closings.map((c) => _shiftClosingRow(context, c)).toList());
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// Customers — one row per person with how often they book, how much
  /// they've spent, and their average rating. Tap a row for their full
  /// booking and review history. Everything is derived from bookings +
  /// feedback that already exist; there's no separate customers collection.
  Widget _buildCustomersPage(BuildContext context, {required bool isDesktop}) {
    return StreamBuilder<Map<String, BlockedUser>>(
      stream: BlockRepository.watchBlocked(),
      builder: (context, blockedSnap) => _buildCustomersList(context, blockedSnap.data ?? const <String, BlockedUser>{}, isDesktop: isDesktop),
    );
  }

  Widget _buildCustomersList(BuildContext context, Map<String, BlockedUser> blocked, {required bool isDesktop}) {
    return StreamBuilder<List<BookingRecord>>(
      stream: BookingRepository.watchAllBookings(),
      builder: (context, bookingSnap) {
        final bookings = bookingSnap.data ?? const <BookingRecord>[];
        return StreamBuilder<List<FeedbackRecord>>(
          stream: FeedbackRepository.watchAllFeedback(),
          builder: (context, feedbackSnap) {
            final feedback = feedbackSnap.data ?? const <FeedbackRecord>[];
            return StreamBuilder<List<RegisteredAccount>>(
              stream: UserAccountRepository.watchAccounts(),
              builder: (context, accountSnap) {
            final accounts = accountSnap.data ?? const <RegisteredAccount>[];
            final all = groupCustomers(bookings, feedback, accounts: accounts);

            final q = _customerQuery.trim().toLowerCase();
            final filtered = q.isEmpty
                ? [...all]
                : all
                    .where((c) => c.name.toLowerCase().contains(q) || c.email.toLowerCase().contains(q) || c.contact.toLowerCase().contains(q))
                    .toList();
            filtered.sort((a, b) {
              switch (_customerSort) {
                case 'bookings':
                  return b.activeBookingCount.compareTo(a.activeBookingCount);
                case 'recent':
                  return (b.lastBookingDate ?? DateTime(0)).compareTo(a.lastBookingDate ?? DateTime(0));
                case 'newest':
                  return (b.registeredAt ?? DateTime(0)).compareTo(a.registeredAt ?? DateTime(0));
                default:
                  return b.totalSpent.compareTo(a.totalSpent);
              }
            });

            final repeat = all.where((c) => c.activeBookingCount >= 2).length;
            final newAccounts = all.where((c) => c.isNewAccount).length;
            final byspend = [...all]..sort((a, b) => b.totalSpent.compareTo(a.totalSpent));
            final top = byspend.isEmpty ? null : byspend.first;

            _customerPage = PageWindow.clamp(_customerPage, filtered.length);
            final pageItems = PageWindow.slice(filtered, _customerPage);

            final cards = [
              _AdminStatCard(icon: Icons.people_alt_rounded, iconColor: AppColors.accent, value: '${all.length}', label: 'Customers'),
              _AdminStatCard(icon: Icons.repeat_rounded, iconColor: const Color(0xFF3B82F6), value: '$repeat', label: 'Repeat customers (2+)'),
              _AdminStatCard(icon: Icons.person_add_alt_1_rounded, iconColor: const Color(0xFF2E7D32), value: '$newAccounts', label: 'New accounts (7 days)'),
              _AdminStatCard(
                icon: Icons.emoji_events_rounded,
                iconColor: AppColors.highlight,
                value: top == null ? '₱0' : '₱${top.totalSpent}',
                label: top != null && top.totalSpent > 0 ? 'Top: ${top.name}' : 'Top spender',
              ),
            ];
            final summary = isDesktop
                ? Row(children: [for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(width: 14), Expanded(child: cards[i])]])
                : Column(children: [
                    Row(children: [Expanded(child: cards[0]), const SizedBox(width: 12), Expanded(child: cards[1])]),
                    const SizedBox(height: 12),
                    Row(children: [Expanded(child: cards[2]), const SizedBox(width: 12), Expanded(child: cards[3])]),
                  ]);

            Widget sortChip(String value, String label) {
              final selected = _customerSort == value;
              return ChoiceChip(
                label: Text(label),
                selected: selected,
                onSelected: (_) => setState(() {
                  _customerSort = value;
                  _customerPage = 0;
                }),
                labelStyle: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppPalette.textPrimary(context)),
                selectedColor: AppColors.accent,
                backgroundColor: AppPalette.surface(context),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999), side: BorderSide.none),
                showCheckmark: false,
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  summary,
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      color: AppPalette.cardBg(context),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: AppShadows.soft,
                      border: Border.all(color: AppPalette.divider(context).withValues(alpha: 0.5)),
                    ),
                    child: TextField(
                      controller: _customerSearchController,
                      onChanged: (v) => setState(() {
                        _customerQuery = v;
                        _customerPage = 0;
                      }),
                      style: TextStyle(fontSize: 13, color: AppPalette.textPrimary(context)),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: "Search by name, email or contact number",
                        hintStyle: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
                        prefixIcon: const Icon(Icons.search_rounded, size: 19, color: AppColors.accent),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [sortChip('newest', 'Newly registered'), sortChip('spent', 'Top spenders'), sortChip('bookings', 'Most bookings'), sortChip('recent', 'Recent')]),
                  const SizedBox(height: 14),
                  if (all.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text("No customers yet — they appear here once someone registers or books.", style: TextStyle(color: AppPalette.textMuted(context)))),
                    )
                  else if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text("No customers match your search.", style: TextStyle(color: AppPalette.textMuted(context)))),
                    )
                  else ...[
                    ...pageItems.map((c) => _customerRow(context, c, blocked)),
                    PaginationBar(
                      page: _customerPage,
                      pageCount: PageWindow.pageCount(filtered.length),
                      onPageChanged: (p) => setState(() => _customerPage = p),
                    ),
                  ],
                ],
              ),
            );
              },
            );
          },
        );
      },
    );
  }

  Widget _customerRow(BuildContext context, CustomerSummary c, Map<String, BlockedUser> blocked) {
    final isBlocked = c.isBlockedIn(blocked);
    final rating = c.avgRating;
    final regular = c.activeBookingCount >= 3;
    final last = c.lastBookingDate;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.soft,
        border: Border.all(color: AppPalette.divider(context).withValues(alpha: 0.5)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showCustomerDetail(context, c),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.accentTint(0.12), shape: BoxShape.circle),
                  child: Text(c.name.substring(0, 1).toUpperCase(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.accent)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(c.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                          ),
                          if (isBlocked) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFFB3261E).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                              child: const Text("Blocked", style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFFB3261E))),
                            ),
                          ],
                          if (c.isNewAccount) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFF2E7D32).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                              child: const Text("New", style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
                            ),
                          ],
                          if (regular) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.highlight.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(999)),
                              child: const Text("Regular", style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppColors.highlight)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${c.activeBookingCount} ${c.activeBookingCount == 1 ? "booking" : "bookings"}'
                        '${last != null ? " · last ${DateFormat('MMM d, yyyy').format(last)}" : ""}'
                        '${c.registeredAt != null ? " · registered ${DateFormat('MMM d, yyyy').format(c.registeredAt!)}" : ""}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₱${c.totalSpent}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                    const SizedBox(height: 3),
                    if (rating != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, size: 13, color: AppColors.highlight),
                          const SizedBox(width: 2),
                          Text(rating.toStringAsFixed(1), style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
                        ],
                      )
                    else
                      Text("No review", style: TextStyle(fontSize: 10.5, color: AppPalette.textMuted(context))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCustomerDetail(BuildContext context, CustomerSummary c) {
    final history = [...c.bookings]..sort((a, b) => b.date.compareTo(a.date));
    final reviews = [...c.feedback]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final rating = c.avgRating;
    final initial = c.name.trim().isEmpty ? '?' : c.name.trim().substring(0, 1).toUpperCase();

    showDialog<void>(
      context: context,
      builder: (sheetContext) {
        final ink = AppPalette.textPrimary(sheetContext);
        final muted = AppPalette.textMuted(sheetContext);
        final line = AppPalette.divider(sheetContext);
        const danger = Color(0xFFB3261E);
        const success = Color(0xFF2E7D32);

        Widget sectionTitle(String title, {String? count}) => Row(
              children: [
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink)),
                const Spacer(),
                if (count != null) Text(count, style: TextStyle(fontSize: 12, color: muted)),
              ],
            );

        Widget metaLine(IconData icon, String text) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: muted),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted)),
                ),
              ],
            );

        Widget statCell(String value, String label) => Expanded(
              child: Column(
                children: [
                  Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink)),
                  const SizedBox(height: 3),
                  Text(label, style: TextStyle(fontSize: 11, color: muted)),
                ],
              ),
            );

        return StreamBuilder<Map<String, BlockedUser>>(
          stream: BlockRepository.watchBlocked(),
          builder: (sheetContext, blockedSnap) {
            final blocked = blockedSnap.data ?? const <String, BlockedUser>{};
            final isBlocked = c.isBlockedIn(blocked);
            final blockInfo = blocked.entries.where((e) => c.userIds.contains(e.key)).map((e) => e.value).firstOrNull;
            final hasAccount = c.userIds.isNotEmpty;

            return Dialog(
              backgroundColor: AppPalette.bg(sheetContext),
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 520,
                  maxHeight: MediaQuery.of(sheetContext).size.height * 0.84,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: identity on the left, close on the right.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.accentTint(0.10),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(initial,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.accent)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.25, color: ink)),
                                const SizedBox(height: 6),
                                if (c.email.isNotEmpty) metaLine(Icons.mail_outline_rounded, c.email),
                                if (c.contact.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  metaLine(Icons.phone_outlined, c.contact),
                                ],
                                if (c.registeredAt != null) ...[
                                  const SizedBox(height: 3),
                                  metaLine(Icons.event_available_outlined,
                                      'Joined ${DateFormat('MMM d, yyyy').format(c.registeredAt!)}'),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            tooltip: 'Close',
                            style: IconButton.styleFrom(backgroundColor: AppPalette.surface(sheetContext)),
                            icon: Icon(Icons.close_rounded, size: 18, color: muted),
                          ),
                        ],
                      ),

                      if (isBlocked) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: danger.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.block_rounded, size: 16, color: danger),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Blocked${blockInfo == null ? '' : ' on ${DateFormat('MMM d, yyyy').format(blockInfo.blockedAt)}'}.'
                                  '${blockInfo != null && blockInfo.reason.isNotEmpty ? ' Reason: ${blockInfo.reason}' : ''}'
                                  ' They can\'t book, rent, review or message.',
                                  style: const TextStyle(fontSize: 12, height: 1.4, color: danger),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 18),

                      // Actions.
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: !hasAccount
                                  ? null
                                  : () {
                                      final uid = c.userIds.first;
                                      Navigator.of(sheetContext).pop();
                                      if (!context.mounted) return;
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                            builder: (_) => AdminMessageThreadScreen(userId: uid, customerName: c.name)),
                                      );
                                    },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.accent,
                                side: BorderSide(color: hasAccount ? AppColors.accent.withValues(alpha: 0.5) : line),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                              label: const Text('Message', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: !hasAccount
                                  ? null
                                  : () => isBlocked
                                      ? _unblockCustomer(sheetContext, c)
                                      : _blockCustomer(sheetContext, c),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isBlocked ? success : danger,
                                side: BorderSide(
                                  color: !hasAccount ? line : (isBlocked ? success : danger).withValues(alpha: 0.5),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              icon: Icon(isBlocked ? Icons.lock_open_rounded : Icons.block_rounded, size: 16),
                              label: Text(isBlocked ? 'Unblock' : 'Block',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                            ),
                          ),
                        ],
                      ),
                      if (!hasAccount)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            "Walk-in without an app account, so there's no one to message or block.",
                            style: TextStyle(fontSize: 11.5, color: muted),
                          ),
                        ),

                      const SizedBox(height: 20),

                      // Key numbers in one flat strip.
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                        decoration: BoxDecoration(
                          color: AppPalette.surface(sheetContext),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            children: [
                              statCell('${c.activeBookingCount}', 'Bookings'),
                              VerticalDivider(width: 1, thickness: 1, color: line, indent: 4, endIndent: 4),
                              statCell('₱${c.totalSpent}', 'Spent'),
                              VerticalDivider(width: 1, thickness: 1, color: line, indent: 4, endIndent: 4),
                              statCell(rating == null ? '—' : rating.toStringAsFixed(1), 'Avg rating'),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 26),

                      sectionTitle('Booking history', count: '${history.length}'),
                      const SizedBox(height: 4),
                      if (history.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text('No bookings yet. This account just registered.',
                              style: TextStyle(fontSize: 12.5, color: muted)),
                        )
                      else
                        for (var i = 0; i < history.length; i++) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(history[i].packageName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: ink)),
                                      const SizedBox(height: 3),
                                      metaLine(Icons.schedule_rounded,
                                          '${DateFormat('MMM d, yyyy').format(history[i].date)} · ${history[i].time}'),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('₱${history[i].totalPrice}',
                                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ink)),
                                    const SizedBox(height: 5),
                                    _StatusChip(status: history[i].status),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (i < history.length - 1) Divider(height: 1, color: line),
                        ],

                      const SizedBox(height: 26),

                      sectionTitle('Reviews', count: reviews.isEmpty ? null : '${reviews.length}'),
                      const SizedBox(height: 4),
                      if (reviews.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text("This customer hasn't left a review yet.",
                              style: TextStyle(fontSize: 12.5, color: muted)),
                        )
                      else
                        for (var i = 0; i < reviews.length; i++) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    ...List.generate(
                                      5,
                                      (s) => Icon(
                                        s < reviews[i].rating ? Icons.star_rounded : Icons.star_outline_rounded,
                                        size: 15,
                                        color: AppColors.highlight,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        '${reviews[i].packageName} · ${DateFormat('MMM d, yyyy').format(reviews[i].createdAt)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 11.5, color: muted),
                                      ),
                                    ),
                                  ],
                                ),
                                if (reviews[i].comment.trim().isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(reviews[i].comment,
                                      style: TextStyle(fontSize: 13, height: 1.45, color: ink)),
                                ],
                              ],
                            ),
                          ),
                          if (i < reviews.length - 1) Divider(height: 1, color: line),
                        ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _blockCustomer(BuildContext sheetContext, CustomerSummary c) async {
    final reasonController = TextEditingController();
    final ok = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        title: Text('Block ${c.name}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("They won't be able to make bookings, rent cameras, leave reviews or send messages. You can unblock them anytime. Existing bookings aren't affected."),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Reason (optional, only you see this)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB3261E), foregroundColor: Colors.white),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await BlockRepository.block(userIds: c.userIds, name: c.name, reason: reasonController.text);
      TopToast.show(null, '${c.name} is now blocked.');
    } catch (_) {
      TopToast.show(null, "Couldn't block this customer. Check your connection and admin permissions.", kind: TopToastKind.error);
    }
  }

  Future<void> _unblockCustomer(BuildContext sheetContext, CustomerSummary c) async {
    try {
      await BlockRepository.unblock(userIds: c.userIds, name: c.name);
      TopToast.show(null, '${c.name} is unblocked.');
    } catch (_) {
      TopToast.show(null, "Couldn't unblock this customer. Check your connection and admin permissions.", kind: TopToastKind.error);
    }
  }

  /// Activity Log — who did what, newest first. Fed by the `activityLog`
  /// collection that both the Admin and Staff repositories write to right
  /// after an action succeeds (approve/reject/complete/delete a booking,
  /// cancel a hold, check in a rental, void a POS sale, walk-in booking).
  Widget _buildActivityLogPage(BuildContext context) {
    return StreamBuilder<List<ActivityLogEntry>>(
      stream: ActivityLogRepository.watchRecent(limit: _activityLimit),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                "Couldn't load the activity log. If this is the first time, publish the updated firestore.rules (it adds the activityLog collection).\n\n${snapshot.error}",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context)),
              ),
            ),
          );
        }
        final all = snapshot.data ?? const <ActivityLogEntry>[];
        final now = DateTime.now();
        final startOfToday = DateTime(now.year, now.month, now.day);
        final DateTime? since = switch (_activityRange) {
          'today' => startOfToday,
          'week' => startOfToday.subtract(const Duration(days: 6)),
          'month' => startOfToday.subtract(const Duration(days: 29)),
          _ => null,
        };
        final entries = filterActivity(
          all,
          role: _activityRoleFilter,
          category: _activityCategory,
          query: _activityQuery,
          since: since,
        );
        final hasActiveFilter = _activityRoleFilter != 'all' ||
            _activityCategory != ActivityCategory.all ||
            _activityQuery.trim().isNotEmpty ||
            _activityRange != 'all';
        _activityPage = PageWindow.clamp(_activityPage, entries.length);
        final pageEntries = PageWindow.slice(entries, _activityPage);

        Widget chipFor(bool selected, String label, VoidCallback onTap) {
          return ChoiceChip(
            label: Text(label),
            selected: selected,
            onSelected: (_) => setState(() {
              onTap();
              _activityPage = 0;
            }),
            labelStyle: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppPalette.textPrimary(context)),
            selectedColor: AppColors.accent,
            backgroundColor: AppPalette.surface(context),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999), side: BorderSide.none),
            showCheckmark: false,
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "A record of who approved, rejected, cancelled, checked in, or voided what. Entries can't be edited or deleted.",
                style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
              ),
              ValueListenableBuilder<String?>(
                valueListenable: ActivityLogRepository.lastWriteError,
                builder: (context, error, _) {
                  if (error == null) return const SizedBox(height: 12);
                  return Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      "The last action couldn't be written to the log, so it won't appear below. "
                      "This is usually because the updated firestore.rules (with the activityLog collection) hasn't been published yet.\n\n$error",
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFFDC2626)),
                    ),
                  );
                },
              ),
              Container(
                decoration: BoxDecoration(
                  color: AppPalette.cardBg(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppPalette.divider(context).withValues(alpha: 0.5)),
                ),
                child: TextField(
                  controller: _activitySearchController,
                  onChanged: (v) => setState(() {
                    _activityQuery = v;
                    _activityPage = 0;
                  }),
                  style: TextStyle(fontSize: 13, color: AppPalette.textPrimary(context)),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: "Search action, customer, or who did it",
                    hintStyle: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
                    prefixIcon: const Icon(Icons.search_rounded, size: 19, color: AppColors.accent),
                    suffixIcon: _activityQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => setState(() {
                              _activitySearchController.clear();
                              _activityQuery = '';
                              _activityPage = 0;
                            }),
                          ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                chipFor(_activityRoleFilter == 'all', 'Everyone', () => _activityRoleFilter = 'all'),
                chipFor(_activityRoleFilter == 'admin', 'Admin', () => _activityRoleFilter = 'admin'),
                chipFor(_activityRoleFilter == 'staff', 'Staff', () => _activityRoleFilter = 'staff'),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                chipFor(_activityCategory == ActivityCategory.all, 'All actions', () => _activityCategory = ActivityCategory.all),
                chipFor(_activityCategory == ActivityCategory.bookings, 'Bookings', () => _activityCategory = ActivityCategory.bookings),
                chipFor(_activityCategory == ActivityCategory.rentals, 'Rentals', () => _activityCategory = ActivityCategory.rentals),
                chipFor(_activityCategory == ActivityCategory.customers, 'Customers', () => _activityCategory = ActivityCategory.customers),
                chipFor(_activityCategory == ActivityCategory.other, 'Other', () => _activityCategory = ActivityCategory.other),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                chipFor(_activityRange == 'all', 'Any time', () => _activityRange = 'all'),
                chipFor(_activityRange == 'today', 'Today', () => _activityRange = 'today'),
                chipFor(_activityRange == 'week', 'Last 7 days', () => _activityRange = 'week'),
                chipFor(_activityRange == 'month', 'Last 30 days', () => _activityRange = 'month'),
              ]),
              const SizedBox(height: 14),
              if (snapshot.connectionState == ConnectionState.waiting && all.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()))
              else if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      all.isEmpty
                          ? "No activity recorded yet. Actions you take from now on will show up here."
                          : "Nothing matches these filters — ${all.length} ${all.length == 1 ? 'entry is' : 'entries are'} hidden. Clear a filter or the search to see ${all.length == 1 ? 'it' : 'them'}.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppPalette.textMuted(context)),
                    ),
                  ),
                )
              else ...[
                if (hasActiveFilter)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      '${entries.length} of ${all.length} ${all.length == 1 ? 'entry' : 'entries'}',
                      style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
                    ),
                  ),
                ...pageEntries.map((e) => _activityRow(context, e)),
                PaginationBar(
                  page: _activityPage,
                  pageCount: PageWindow.pageCount(entries.length),
                  onPageChanged: (p) => setState(() => _activityPage = p),
                ),
                // The stream only loads the newest N entries; when it's hit
                // that cap there may be older ones, so offer to fetch more.
                if (all.length >= _activityLimit)
                  Center(
                    child: TextButton.icon(
                      onPressed: () => setState(() => _activityLimit += 300),
                      icon: const Icon(Icons.history_rounded, size: 17),
                      label: Text('Load older entries (showing newest $_activityLimit)'),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _activityRow(BuildContext context, ActivityLogEntry e) {
    final a = e.action.toLowerCase();
    final IconData icon;
    final Color color;
    if (a.contains('approved')) {
      icon = Icons.check_circle_rounded;
      color = AppColors.success;
    } else if (a.contains('rejected') || a.contains('cancelled')) {
      icon = Icons.cancel_rounded;
      color = const Color(0xFFDC2626);
    } else if (a.contains('deleted') || a.contains('voided')) {
      icon = Icons.delete_outline_rounded;
      color = const Color(0xFFDC2626);
    } else if (a.contains('rental')) {
      icon = Icons.camera_alt_rounded;
      color = const Color(0xFF3B82F6);
    } else if (a.contains('walk-in')) {
      icon = Icons.directions_walk_rounded;
      color = AppColors.accent;
    } else {
      icon = Icons.task_alt_rounded;
      color = AppColors.highlight;
    }
    final who = e.actorEmail.isNotEmpty ? e.actorEmail : 'Unknown';
    final role = e.actorRole == 'unknown' ? '' : ' (${e.actorRole})';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.soft,
        border: Border.all(color: AppPalette.divider(context).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.action, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                const SizedBox(height: 2),
                Text(e.targetSummary, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: AppPalette.textPrimary(context))),
                const SizedBox(height: 2),
                Text('$who$role · ${DateFormat('MMM d, h:mm a').format(e.createdAt)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: AppPalette.textMuted(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _posFilterBar(BuildContext context, List<String> staffEmails) {
    Widget chip(String value, String label) {
      final selected = _posPaymentFilter == value;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _posPaymentFilter = value),
        labelStyle: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppPalette.textPrimary(context)),
        selectedColor: AppColors.accent,
        backgroundColor: AppPalette.surface(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999), side: BorderSide.none),
        showCheckmark: false,
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        chip('all', 'All payments'),
        chip('cash', 'Cash'),
        chip('gcash', 'GCash'),
        if (staffEmails.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(999)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _posStaffFilter,
                isDense: true,
                icon: const Icon(Icons.expand_more_rounded, size: 16),
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context)),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All staff')),
                  ...staffEmails.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (v) => setState(() => _posStaffFilter = v ?? 'all'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _shiftClosingRow(BuildContext context, ShiftClosingRecord c) {
    final variance = c.variance;
    final color = variance == 0 ? AppColors.success : (variance > 0 ? const Color(0xFF3B82F6) : Colors.redAccent);
    final label = variance == 0 ? "Balanced" : (variance > 0 ? "Over by ₱${NumberFormat('#,##0').format(variance)}" : "Short by ₱${NumberFormat('#,##0').format(-variance)}");
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.divider(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.staffEmail.isEmpty ? 'Unknown staff' : c.staffEmail, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat('MMM d, h:mm a').format(c.closedAt)} · ${c.salesCount} sale${c.salesCount == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context)),
                ),
                if (c.notes.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(c.notes, style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppPalette.textMuted(context))),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
              const SizedBox(height: 2),
              Text('Counted ₱${NumberFormat('#,##0').format(c.countedCash)}', style: TextStyle(fontSize: 10.5, color: AppPalette.textMuted(context))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _posSaleRow(BuildContext context, PosTransactionRecord s) {
    final isCash = s.paymentMethod == 'cash';
    final itemsSummary = s.items.map((i) => i.quantity > 1 ? '${i.name} x${i.quantity}' : i.name).join(', ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.soft,
        border: Border.all(color: AppPalette.divider(context).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (isCash ? AppColors.success : const Color(0xFF3B82F6)).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCash ? Icons.payments_outlined : Icons.qr_code_2_rounded,
              size: 17,
              color: isCash ? AppColors.success : const Color(0xFF3B82F6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  itemsSummary.isNotEmpty ? itemsSummary : 'Sale',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
                ),
                const SizedBox(height: 2),
                Text(
                  '${s.staffEmail.isNotEmpty ? s.staffEmail : "Unknown staff"} · ${DateFormat('MMM d, h:mm a').format(s.createdAt)}'
                  '${s.referenceNote.isNotEmpty ? " · ${s.referenceNote}" : ""}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('₱${s.total}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: "Void sale",
            onPressed: () => _confirmVoidSale(context, s),
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFDC2626)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmVoidSale(BuildContext context, PosTransactionRecord s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Void this sale?"),
        content: Text(
          "This permanently removes the ₱${s.total} ${s.paymentMethod == 'cash' ? 'cash' : 'GCash'} sale from the log — there's no undo. "
          "Use this only to correct a mistaken entry.",
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text("Cancel")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text("Void Sale"),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await PosRepository.deleteTransaction(s.id);
      if (context.mounted) {
        TopToast.show(context, "Sale voided.");
      }
    } catch (e) {
      if (context.mounted) {
        TopToast.show(context, "Couldn't void sale: $e", kind: TopToastKind.error);
      }
    }
  }

  Widget _receiptLogRow(BuildContext context, BookingRecord b) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.soft,
        border: Border.all(color: AppPalette.divider(context).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: GestureDetector(
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: buildReceiptImage(b.receiptUrl, fit: BoxFit.contain),
                ),
              ),
              child: buildReceiptImage(
                b.receiptUrl,
                fit: BoxFit.cover,
                height: 44,
                width: 44,
                errorBuilder: (context, error, stack) => Container(
                  height: 44,
                  width: 44,
                  color: AppPalette.surface(context),
                  child: Icon(Icons.image_not_supported_outlined, size: 16, color: AppPalette.textMuted(context)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b.customerName.trim().isNotEmpty ? b.customerName : b.bookingRef,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
                ),
                const SizedBox(height: 2),
                Text(
                  '${b.packageName} · ${b.createdAt != null ? DateFormat('MMM d, yyyy').format(b.createdAt!) : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₱${b.totalPrice}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
              const SizedBox(height: 4),
              _StatusChip(status: b.status),
            ],
          ),
        ],
      ),
    );
  }

  /// The "Dashboard" section's main workspace: 4 live KPI cards, then a
  /// 2-column monitor (Live Queue & Hold Timers | Camera Rental Tracker)
  /// on desktop, stacked on mobile. Every number here comes straight from
  /// the same `BookingRepository`/`CameraRentalRepository` streams the
  /// rest of the admin app already uses — nothing here is placeholder data.
  Widget _buildDashboardHome(BuildContext context, {required bool isDesktop}) {
    return StreamBuilder<List<BookingRecord>>(
      stream: BookingRepository.watchAllBookings(),
      builder: (context, bookingSnapshot) {
        final bookings = bookingSnapshot.data ?? const <BookingRecord>[];
        return StreamBuilder<List<CameraRentalRecord>>(
          stream: CameraRentalRepository.watchAllRentals(),
          builder: (context, rentalSnapshot) {
            final rentals = rentalSnapshot.data ?? const <CameraRentalRecord>[];

            final today = DateTime.now();
            final sessionsToday = bookings
                .where((b) => b.status == 'confirmed' && b.date.year == today.year && b.date.month == today.month && b.date.day == today.day)
                .length;
            final activeHolds = bookings.where((b) => b.isAwaitingReceipt && (b.holdRemaining?.inSeconds ?? 0) > 0).toList()
              ..sort((a, b) => (a.holdRemaining ?? Duration.zero).compareTo(b.holdRemaining ?? Duration.zero));
            final pendingApprovals = bookings.where((b) => b.status == 'pending_confirmation').length;
            final gearOut = rentals.where((r) => !r.isReturned).toList()..sort((a, b) => a.dueAt.compareTo(b.dueAt));

            final monitorGrid = isDesktop
                ? IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _liveQueueMonitor(context, activeHolds, isDesktop: isDesktop)),
                        const SizedBox(width: 18),
                        Expanded(child: _rentalTracker(context, gearOut)),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      _liveQueueMonitor(context, activeHolds, isDesktop: isDesktop),
                      const SizedBox(height: 18),
                      _rentalTracker(context, gearOut),
                    ],
                  );

            return SingleChildScrollView(
              padding: isDesktop ? const EdgeInsets.fromLTRB(16, 14, 20, 20) : const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AdminOverviewHeader(
                    sessionsToday: sessionsToday,
                    activeHolds: activeHolds.length,
                    gearOut: gearOut.length,
                    pendingApprovals: pendingApprovals,
                    isDesktop: isDesktop,
                  ),
                  const SizedBox(height: 22),
                  _revenueTrendCard(context, bookings, isDesktop: isDesktop),
                  const SizedBox(height: 22),
                  monitorGrid,
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// "Revenue · last 7 days" card on the Dashboard home — the quick-glance
  /// version of the Financial Logs report (same `RevenueEntry` data, so
  /// the numbers match), with a shortcut into the full report.
  Widget _revenueTrendCard(BuildContext context, List<BookingRecord> bookings, {required bool isDesktop}) {
    return StreamBuilder<List<PosTransactionRecord>>(
      stream: PosRepository.watchAllTransactions(),
      builder: (context, snapshot) {
        final sales = snapshot.data ?? const <PosTransactionRecord>[];
        final entries = RevenueEntry.fromRecords(bookings, sales);
        final now = DateTime.now();
        final firstDay = DateTime(now.year, now.month, now.day - 6);
        final buckets = RevenueBuckets.daily(entries, firstDay, 7, label: (d) => DateFormat('E').format(d), showLabel: (_, __) => true);
        final total = buckets.fold<int>(0, (s, b) => s + b.amount);
        return RevenueChartCard(
          title: 'Revenue · last 7 days',
          subtitle: 'Online bookings + counter sales',
          total: total,
          chart: RevenueBarChart(buckets: buckets, height: isDesktop ? 180 : 160),
          trailing: TextButton(
            onPressed: () => _openFinancialLogs(context, isDesktop: isDesktop),
            style: TextButton.styleFrom(foregroundColor: AppColors.accent, padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: const Text('View report', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        );
      },
    );
  }

  void _openFinancialLogs(BuildContext context, {required bool isDesktop}) {
    if (isDesktop) {
      setState(() => _section = _AdminSection.financialLogs);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text("Financial Receipts/Logs")),
        body: _buildFinancialLogsPage(context, isDesktop: false),
      ),
    ));
  }

  /// Dedicated full-page version of the same live-hold monitor shown on
  /// the Dashboard, for when the admin wants just that list front and
  /// center (the "Live Queue & Timers" nav item).
  Widget _buildLiveQueuePage(BuildContext context, {required bool isDesktop}) {
    return StreamBuilder<List<BookingRecord>>(
      stream: BookingRepository.watchAllBookings(),
      builder: (context, snapshot) {
        final bookings = snapshot.data ?? const <BookingRecord>[];
        final activeHolds = bookings.where((b) => b.isAwaitingReceipt && (b.holdRemaining?.inSeconds ?? 0) > 0).toList()
          ..sort((a, b) => (a.holdRemaining ?? Duration.zero).compareTo(b.holdRemaining ?? Duration.zero));
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _liveQueueMonitor(context, activeHolds, expanded: true, isDesktop: isDesktop),
        );
      },
    );
  }

  /// Live Queue & Hold Timer Monitor card — one row per booking that's
  /// still holding a slot while the customer finishes checkout
  /// (`status == 'awaiting_receipt'`), each with a live mm:ss countdown to
  /// `holdExpiresAt`. "Approve" only lights up once a receipt has actually
  /// been attached; "Cancel Hold" always works and frees the slot early.
  Widget _liveQueueMonitor(BuildContext context, List<BookingRecord> holds, {bool expanded = false, required bool isDesktop}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.soft,
        border: Border.all(color: AppPalette.divider(context).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hourglass_top_rounded, size: 17, color: AppColors.highlight),
              const SizedBox(width: 8),
              Text("Live Queue & Hold Timers", style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
              const Spacer(),
              if (holds.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.highlight.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
                  child: Text('${holds.length} active', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.highlight)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "Slots being held while a customer finishes checkout — each auto-cancels if the 15-minute window lapses.",
            style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
          ),
          const SizedBox(height: 14),
          if (holds.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text("No active holds right now.", style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context))),
              ),
            )
          else
            ...(expanded ? holds : holds.take(4)).map((b) => _holdRow(context, b, isDesktop: isDesktop)),
        ],
      ),
    );
  }

  Widget _holdRow(BuildContext context, BookingRecord b, {required bool isDesktop}) {
    final canApprove = b.receiptUrl.isNotEmpty;
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          b.customerName.trim().isNotEmpty ? b.customerName : b.bookingRef,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
        ),
        const SizedBox(height: 2),
        Text(
          '${b.packageName} · ${canApprove ? "Receipt attached" : "Awaiting receipt"}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context)),
        ),
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HoldCountdown(booking: b),
        const SizedBox(width: 6),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: canApprove ? "Approve receipt" : "No receipt attached yet",
          onPressed: canApprove ? () => BookingRepository.updateStatus(b.id, 'confirmed') : null,
          icon: Icon(Icons.check_circle_rounded, size: 20, color: canApprove ? AppColors.success : AppPalette.textMuted(context).withValues(alpha: 0.4)),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: "Cancel hold",
          onPressed: () => BookingRepository.updateStatus(b.id, 'cancelled', rejectionReason: 'Hold cancelled by admin'),
          icon: const Icon(Icons.cancel_rounded, size: 20, color: Color(0xFFDC2626)),
        ),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(14)),
      child: isDesktop
          ? Row(children: [Expanded(child: info), actions])
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                info,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            ),
    );
  }

  /// Camera Rental Status Tracker card — every rental still out
  /// (`!isReturned`), with a live overdue/remaining readout against
  /// `dueAt` and a real "Check-In" button wired to `markReturned`.
  Widget _rentalTracker(BuildContext context, List<CameraRentalRecord> rentals) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.soft,
        border: Border.all(color: AppPalette.divider(context).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.camera_alt_rounded, size: 17, color: Color(0xFF3B82F6)),
              const SizedBox(width: 8),
              Text("Camera Rental Status", style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
              const Spacer(),
              if (rentals.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFF3B82F6).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                  child: Text('${rentals.length} out', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF3B82F6))),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text("Gear currently checked out and not yet returned.", style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
          const SizedBox(height: 14),
          if (rentals.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text("No gear out on rental right now.", style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context))),
              ),
            )
          else
            ...rentals.take(6).map((r) => _rentalRow(context, r)),
        ],
      ),
    );
  }

  Widget _rentalRow(BuildContext context, CameraRentalRecord r) {
    final overdue = r.isOverdue;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.cameraName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
                ),
                const SizedBox(height: 2),
                Text(
                  overdue
                      ? 'Overdue since ${DateFormat('MMM d, h:mm a').format(r.dueAt)}'
                      : 'Due back ${DateFormat('MMM d, h:mm a').format(r.dueAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: overdue ? const Color(0xFFDC2626) : AppPalette.textMuted(context)),
                ),
              ],
            ),
          ),
          if (overdue)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(color: const Color(0xFFDC2626).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999)),
              child: const Text("Overdue", style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
            ),
          OutlinedButton(
            onPressed: () => CameraRentalRepository.markReturned(r.id),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.accent),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: const Text("Check-In", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

/// Dashboard-style header for the desktop Bookings/overview pane: a
/// greeting line plus a row of live stat cards (colored icon chip + big
/// number + label), replacing the old plain "Bookings" title so the admin
/// home reads like an actual dashboard instead of a data table.
class _AdminOverviewHeader extends StatelessWidget {
  final int sessionsToday;
  final int activeHolds;
  final int gearOut;
  final int pendingApprovals;
  final bool isDesktop;

  const _AdminOverviewHeader({
    required this.sessionsToday,
    required this.activeHolds,
    required this.gearOut,
    required this.pendingApprovals,
    this.isDesktop = true,
  });

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Good morning";
    if (hour < 18) return "Good afternoon";
    return "Good evening";
  }

  @override
  Widget build(BuildContext context) {
    final email = AdminService.instance.currentEmail;
    final name = (email != null && email.contains('@')) ? email.split('@').first : 'Admin';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_greeting()}, $name',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold, letterSpacing: -0.4, color: AppPalette.textPrimary(context)),
        ),
        const SizedBox(height: 4),
        Text(
          "Here's what's happening with your studio today.",
          style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
        ),
        const SizedBox(height: 18),
        _buildStatCards(context),
      ],
    );
  }

  /// Desktop: a single row of 4 cards. Mobile: a 2x2 grid instead — 4
  /// `Expanded` cards squeezed into a narrow phone width would truncate
  /// labels like "Active hold timers" past readability.
  Widget _buildStatCards(BuildContext context) {
    final cards = [
      _AdminStatCard(icon: Icons.event_available_rounded, iconColor: AppColors.accent, value: '$sessionsToday', label: 'Sessions today'),
      _AdminStatCard(icon: Icons.hourglass_top_rounded, iconColor: AppColors.highlight, value: '$activeHolds', label: 'Active hold timers'),
      _AdminStatCard(icon: Icons.camera_alt_rounded, iconColor: const Color(0xFF3B82F6), value: '$gearOut', label: 'Gear out on rental'),
      _AdminStatCard(icon: Icons.fact_check_rounded, iconColor: AppColors.success, value: '$pendingApprovals', label: 'Pending approvals'),
    ];

    if (isDesktop) {
      return Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 14),
            Expanded(child: cards[i]),
          ],
        ],
      );
    }

    return Column(
      children: [
        Row(children: [Expanded(child: cards[0]), const SizedBox(width: 12), Expanded(child: cards[1])]),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: cards[2]), const SizedBox(width: 12), Expanded(child: cards[3])]),
      ],
    );
  }
}

/// One "icon chip + number + label" card used in [_AdminOverviewHeader]'s
/// stat row — same soft-card language as the rest of the app (rounded,
/// subtle shadow, hairline border) so it drops in without clashing.
class _AdminStatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _AdminStatCard({required this.icon, required this.iconColor, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.soft,
        border: Border.all(color: AppPalette.divider(context).withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
                ),
              ],
            ),
          ),
        ],
      ),
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
      await BookingRepository.updateStatus(b.id, 'confirmed');
      if (mounted) setState(() => _readIds.add(b.id));
    } catch (e) {
      if (mounted) {
        TopToast.show(context, e.toString().replaceFirst('Exception: ', ''), kind: TopToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline(BookingRecord b) async {
    setState(() => _busy = true);
    try {
      RefundDecision? refund;
      if (RefundDecisionDialog.needed(b)) {
        refund = await RefundDecisionDialog.show(context, b);
        if (refund == null) {
          if (mounted) setState(() => _busy = false);
          return;
        }
      }
      await BookingRepository.updateStatus(b.id, 'cancelled', rejectionReason: 'Declined from notifications', refund: refund);
      if (mounted) setState(() => _readIds.add(b.id));
    } catch (e) {
      if (mounted) {
        TopToast.show(context, e.toString().replaceFirst('Exception: ', ''), kind: TopToastKind.error);
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
    // On a phone the panel sits inside the centered popup, which already
    // rounds and clips it; on desktop it is the floating dropdown card.
    final radius = widget.isDesktop ? BorderRadius.circular(20) : BorderRadius.zero;
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
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
                  const SizedBox(height: 3),
                  Text(meta, style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
                  const SizedBox(height: 10),
                  trailing,
                ],
              ),
            ),
            if (unread)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
              ),
          ],
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

/// Persistent top header bar for the desktop admin shell: global search,
/// a live system-status badge, the notification bell, and a live clock —
/// a floating rounded card above every section.
class _AdminTopBar extends StatefulWidget {
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback onOpenNotifications;

  const _AdminTopBar({required this.onSearchSubmitted, required this.onOpenNotifications});

  @override
  State<_AdminTopBar> createState() => _AdminTopBarState();
}

class _AdminTopBarState extends State<_AdminTopBar> {
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
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: TextField(
                  controller: _searchController,
                  onSubmitted: widget.onSearchSubmitted,
                  style: TextStyle(fontSize: 13, color: AppPalette.textPrimary(context)),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: "Search by Booking Ref, Customer Name, or Camera Serial...",
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
            const Spacer(),
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
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
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

/// Live mm:ss countdown to a booking's `holdExpiresAt`, ticking every
/// second on its own so the parent list doesn't need to rebuild for it.
class _HoldCountdown extends StatefulWidget {
  final BookingRecord booking;
  const _HoldCountdown({required this.booking});

  @override
  State<_HoldCountdown> createState() => _HoldCountdownState();
}

class _HoldCountdownState extends State<_HoldCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.booking.holdRemaining ?? Duration.zero;
    final minutes = remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    final urgent = remaining.inSeconds <= 120;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (urgent ? const Color(0xFFDC2626) : AppColors.highlight).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 13, color: urgent ? const Color(0xFFDC2626) : AppColors.highlight),
          const SizedBox(width: 5),
          Text(
            '$minutes:$seconds',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: urgent ? const Color(0xFFDC2626) : AppColors.highlight),
          ),
        ],
      ),
    );
  }
}

/// Simple, honest placeholder for nav sections that don't have backing
/// data/logic yet (RFID Loyalty Rewards, Financial Receipts/Logs) — makes
/// clear the section exists in the nav but isn't a real feature yet,
/// instead of silently showing an empty page or fake numbers.
class _ComingSoonSection extends StatelessWidget {
  final IconData icon;
  final String title;

  const _ComingSoonSection({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.accentTint(0.12), shape: BoxShape.circle),
                child: Icon(icon, size: 28, color: AppColors.accent),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Persistent desktop sidebar — a floating, rounded maroon card. At rest it
/// is a slim icon-only rail; when the cursor is over it, it expands (over the
/// content, without pushing it) to show the labels, and collapses again when
/// the cursor leaves.
class _AdminSidebar extends StatefulWidget {
  /// Space the collapsed rail takes in the page layout (card + its margins).
  static const double railWidth = 88;
  static const double _collapsedCard = 68;
  static const double _expandedCard = 244;

  final _AdminSection section;
  final ValueChanged<_AdminSection> onSelectSection;
  final VoidCallback onLogout;
  final VoidCallback onOpenNotifications;

  const _AdminSidebar({
    required this.section,
    required this.onSelectSection,
    required this.onLogout,
    required this.onOpenNotifications,
  });

  @override
  State<_AdminSidebar> createState() => _AdminSidebarState();
}

class _AdminSidebarState extends State<_AdminSidebar> {
  static const _anim = Duration(milliseconds: 220);

  bool _hovering = false;
  // Keeps the sidebar open while the profile popup menu is showing (the
  // popup's barrier would otherwise count as the cursor leaving).
  bool _menuOpen = false;

  bool get _expanded => _hovering || _menuOpen;

  @override
  Widget build(BuildContext context) {
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
            width: expanded ? _AdminSidebar._expandedCard : _AdminSidebar._collapsedCard,
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
                // Header + menu scroll when the window is short; the profile
                // card below stays pinned to the bottom of the sidebar.
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 22, 6, 22),
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
                              Expanded(
                                child: AnimatedOpacity(
                                  duration: _anim,
                                  opacity: expanded ? 1 : 0,
                                  child: const Padding(
                                    padding: EdgeInsets.only(left: 11),
                                    child: Text(
                                      "Memoriae PhotoBooth",
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.clip,
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _navItem(context, icon: Icons.dashboard_rounded, label: "Dashboard", target: _AdminSection.dashboard),
                        _navItem(context, icon: Icons.event_note_rounded, label: "Booking Management", target: _AdminSection.bookings),
                        _navItem(context, icon: Icons.people_alt_rounded, label: "Customers", target: _AdminSection.customers),
                        _navItem(context, icon: Icons.hourglass_top_rounded, label: "Live Queue & Timers", target: _AdminSection.liveQueue),
                        _navItem(context, icon: Icons.camera_alt_rounded, label: "Camera Rental", target: _AdminSection.cameraRentals),
                        _navItem(context, icon: Icons.nfc_rounded, label: "RFID Loyalty Rewards", target: _AdminSection.loyalty),
                        _navItem(context, icon: Icons.receipt_long_rounded, label: "Financial Receipts/Logs", target: _AdminSection.financialLogs),
                        _navItem(context, icon: Icons.history_rounded, label: "Activity Log", target: _AdminSection.activityLog),
                        // "MORE" label when open, a thin divider when collapsed
                        // (same height either way so nothing jumps).
                        SizedBox(
                          height: 34,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: expanded
                                ? Padding(
                                    padding: const EdgeInsets.only(left: 22),
                                    child: Text(
                                      "MORE",
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.clip,
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: Colors.white.withValues(alpha: 0.5)),
                                    ),
                                  )
                                : Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 18), color: Colors.white.withValues(alpha: 0.22)),
                          ),
                        ),
                        _navItem(context, icon: Icons.calendar_month_rounded, label: "Calendar", target: _AdminSection.calendar),
                        _navItem(context, icon: Icons.photo_library_rounded, label: "Event Photos", target: _AdminSection.eventPhotos),
                        _navItem(context, icon: Icons.undo_rounded, label: "Refund Requests", target: _AdminSection.refundRequests),
                        _navItem(context, icon: Icons.star_rounded, label: "Feedback", target: _AdminSection.feedback),
                        _navItem(context, icon: Icons.chat_bubble_rounded, label: "Messages", target: _AdminSection.messages),
                        _navItem(context, icon: Icons.campaign_rounded, label: "Announcements", target: _AdminSection.announcements),
                        _navItem(context, icon: Icons.badge_rounded, label: "Staff", target: _AdminSection.staff),
                        _navItem(context, icon: Icons.sell_rounded, label: "Pricing", target: _AdminSection.pricing),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                // Pinned footer: the profile card. Tapping it opens a popup
                // menu with My Profile, Settings and Sign Out.
                _AdminProfileCard(
                  expanded: expanded,
                  highlighted: widget.section == _AdminSection.profile || widget.section == _AdminSection.settings,
                  onOpenProfile: () => widget.onSelectSection(_AdminSection.profile),
                  onOpenSettings: () => widget.onSelectSection(_AdminSection.settings),
                  onLogout: widget.onLogout,
                  onMenuOpenChanged: (open) {
                    if (mounted) setState(() => _menuOpen = open);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(BuildContext context, {required IconData icon, required String label, required _AdminSection target}) {
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

/// Profile card pinned to the bottom of the sidebar (avatar + email, tap for
/// a popup with My Profile, Settings and Sign Out). Shows just the avatar
/// while the sidebar is collapsed.
class _AdminProfileCard extends StatelessWidget {
  final bool expanded;
  final bool highlighted;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenSettings;
  final VoidCallback onLogout;
  final ValueChanged<bool> onMenuOpenChanged;
  const _AdminProfileCard({
    required this.expanded,
    required this.highlighted,
    required this.onOpenProfile,
    required this.onOpenSettings,
    required this.onLogout,
    required this.onMenuOpenChanged,
  });

  @override
  Widget build(BuildContext context) {
    final email = AdminService.instance.currentEmail ?? '';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : 'A';

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: highlighted ? 0.24 : 0.10),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Material(
        color: Colors.transparent,
        child: Builder(
          builder: (cardContext) => InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _openAccountMenu(cardContext),
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 220),
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
                  // Laid out at a fixed width and clipped, so it never
                  // overflows while the sidebar animates open or closed.
                  Expanded(
                    // Fixed height: OverflowBox sizes itself to its parent's
                    // constraints, which are unbounded vertically inside a Column.
                    child: SizedBox(
                      height: 38,
                      child: ClipRect(
                        child: OverflowBox(
                        alignment: Alignment.centerLeft,
                        minWidth: 0,
                        maxWidth: 170,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 220),
                          opacity: expanded ? 1 : 0,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      FutureBuilder<String>(
                                        future: AdminService.instance.currentDisplayName(),
                                        builder: (context, nameSnap) => Text(
                                          nameSnap.data ?? 'Admin',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                                        ),
                                      ),
                                      FutureBuilder<String>(
                                        future: AdminService.instance.currentRoleLabel(),
                                        builder: (context, snap) => Text(
                                          snap.data ?? 'Admin',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 10, color: Colors.white70),
                                        ),
                                      ),
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
    );
  }

  /// Popup above the profile card: My Profile, Settings, Sign Out.
  Future<void> _openAccountMenu(BuildContext cardContext) async {
    final box = cardContext.findRenderObject() as RenderBox;
    final overlay = Overlay.of(cardContext).context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final size = box.size;
    // 3 rows (48 each) + divider (16) + vertical padding (16), so the menu
    // opens upward just above the card instead of covering it.
    const menuHeight = 3 * 48.0 + 16 + 16;

    onMenuOpenChanged(true);
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
              Text("Sign Out", style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      );
    } finally {
      onMenuOpenChanged(false);
    }

    switch (choice) {
      case 'profile':
        onOpenProfile();
        break;
      case 'settings':
        onOpenSettings();
        break;
      case 'logout':
        onLogout();
        break;
    }
  }
}

/// Search box above the Bookings list — filters by customer, booking ID
/// or reference, or package name.
class _BookingSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _BookingSearchBar({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.soft,
        border: Border.all(color: AppPalette.divider(context).withValues(alpha: 0.5)),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontSize: 13, color: AppPalette.textPrimary(context)),
        decoration: InputDecoration(
          isDense: true,
          hintText: "Search by customer, ID or reference",
          hintStyle: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
          prefixIcon: const Icon(Icons.search_rounded, size: 19, color: AppColors.accent),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}

class _BookingList extends StatefulWidget {
  final List<BookingRecord> bookings;
  final String? selectedId;
  final ValueChanged<BookingRecord> onTap;
  final bool selectMode;
  final Set<String> selectedIds;
  final ValueChanged<String>? onToggleSelect;

  const _BookingList({
    required this.bookings,
    required this.selectedId,
    required this.onTap,
    this.selectMode = false,
    this.selectedIds = const {},
    this.onToggleSelect,
  });

  @override
  State<_BookingList> createState() => _BookingListState();
}

class _BookingListState extends State<_BookingList> {
  int _page = 0;

  // ── Package photo (what the customer booked) ────────────────────────────
  StreamSubscription<List<PricingItemRecord>>? _pricingSub;
  final Map<String, Uint8List> _photoBytes = {}; // package id -> decoded photo
  final Map<String, String> _photoUrlById = {}; // package id -> http(s) photo
  final Map<String, String> _idByName = {}; // lower-case name -> package id

  @override
  void initState() {
    super.initState();
    _pricingSub = PricingRepository.watchAllPricing().listen((items) {
      final bytes = <String, Uint8List>{};
      final urls = <String, String>{};
      final names = <String, String>{};
      for (final p in items) {
        if (p.imageUrl.isEmpty) continue;
        names[p.name.trim().toLowerCase()] = p.id;
        if (p.imageUrl.startsWith('data:')) {
          try {
            bytes[p.id] = base64Decode(p.imageUrl.substring(p.imageUrl.indexOf(',') + 1));
          } catch (_) {}
        } else if (p.imageUrl.startsWith('http')) {
          urls[p.id] = p.imageUrl;
        }
      }
      if (!mounted) return;
      setState(() {
        _photoBytes..clear()..addAll(bytes);
        _photoUrlById..clear()..addAll(urls);
        _idByName..clear()..addAll(names);
      });
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _pricingSub?.cancel();
    super.dispose();
  }

  /// Package id whose photo we can show for this booking: matches the
  /// booking's `packageId` first (survives a rename), then the saved name.
  String? _photoKeyFor(BookingRecord b) {
    bool has(String id) => _photoBytes.containsKey(id) || _photoUrlById.containsKey(id);
    if (b.packageId.isNotEmpty && has(b.packageId)) return b.packageId;
    final id = _idByName[b.packageName.trim().toLowerCase()];
    if (id != null && has(id)) return id;
    return null;
  }

  /// Leading visual for a booking card: the package photo with the
  /// customer's initial as a small badge, or the plain initial avatar when
  /// the package has no photo.
  Widget _leading(BuildContext context, BookingRecord b, String name) {
    final initialAvatar = CircleAvatar(
      radius: 20,
      backgroundColor: AppColors.accentTint(0.10),
      child: Text(name[0].toUpperCase(),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.accent)),
    );
    final key = _photoKeyFor(b);
    if (key == null) return initialAvatar;
    final fallback = Container(
      color: AppColors.accentTint(0.10),
      alignment: Alignment.center,
      child: Icon(Icons.photo_outlined, size: 20, color: AppPalette.textMuted(context)),
    );
    final Widget photo = _photoBytes.containsKey(key)
        ? Image.memory(_photoBytes[key]!, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, __, ___) => fallback)
        : Image.network(_photoUrlById[key]!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback);
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(borderRadius: BorderRadius.circular(14), child: photo),
          ),
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
                border: Border.all(color: AppPalette.cardBg(context), width: 2),
              ),
              child: Text(name[0].toUpperCase(),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookings = widget.bookings;
    _page = PageWindow.clamp(_page, bookings.length);
    final pageItems = PageWindow.slice(bookings, _page);

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: pageItems.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final b = pageItems[i];
              final isSelected = widget.selectMode ? widget.selectedIds.contains(b.id) : b.id == widget.selectedId;
              final initials = b.customerName.trim().isNotEmpty
                  ? b.customerName.trim().substring(0, 1).toUpperCase()
                  : b.packageName.trim().isNotEmpty
                      ? b.packageName.trim().substring(0, 1).toUpperCase()
                      : '?';
              return Material(
                color: isSelected ? AppColors.accentTint(0.08) : AppPalette.cardBg(context),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => widget.onTap(b),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: isSelected ? null : AppShadows.soft,
                      border: Border.all(color: isSelected ? AppColors.accent : AppPalette.divider(context).withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        if (widget.selectMode) ...[
                          if (b.status == 'completed')
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Tooltip(
                                message: "Completed bookings can't be deleted",
                                child: Icon(Icons.lock_outline_rounded, size: 20, color: Color(0xFF9CA3AF)),
                              ),
                            )
                          else
                            Checkbox(
                              value: isSelected,
                              activeColor: AppColors.accent,
                              onChanged: (_) => widget.onToggleSelect?.call(b.id),
                            ),
                          const SizedBox(width: 4),
                        ] else ...[
                          _leading(context, b, initials),
                          const SizedBox(width: 14),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (b.customerName.trim().isNotEmpty)
                                Text(
                                  b.customerName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppPalette.textMuted(context)),
                                ),
                              Text(b.packageName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                              const SizedBox(height: 4),
                              Text(
                                '${DateFormat('MMM d, yyyy').format(b.date)} · ${b.time}',
                                style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)),
                              ),
                              if (b.status == 'confirmed' && (b.acceptedByStaffName?.isNotEmpty ?? false)) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Accepted by ${b.acceptedByStaffName}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.accent),
                                ),
                              ],
                            ],
                          ),
                        ),
                        _StatusChip(status: b.status),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        PaginationBar(page: _page, pageCount: PageWindow.pageCount(bookings.length), onPageChanged: (p) => setState(() => _page = p)),
      ],
    );
  }
}

/// Shown in place of the normal header while bulk-select mode is active —
/// lets the admin pick several bookings and delete them in one go instead
/// of opening each one individually.
class _BulkSelectToolbar extends StatelessWidget {
  final int selectedCount;
  final int totalCount;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback? onDelete;
  final VoidCallback onCancel;

  const _BulkSelectToolbar({
    required this.selectedCount,
    required this.totalCount,
    required this.onSelectAll,
    required this.onClear,
    required this.onDelete,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final allSelected = selectedCount > 0 && selectedCount == totalCount;
    return Container(
      color: AppColors.accentTint(0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(
            '$selectedCount selected',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: allSelected ? onClear : onSelectAll,
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
            child: Text(allSelected ? "Clear" : "Select All", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          const Spacer(),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
            child: const Text("Cancel", style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: onDelete,
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent, padding: const EdgeInsets.symmetric(horizontal: 14)),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: Text("Delete ($selectedCount)", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  Color _color() {
    switch (status) {
      case 'confirmed':
        return const Color(0xFF2E7D32);
      case 'completed':
        return const Color(0xFF1565C0);
      case 'cancelled':
        return const Color(0xFF9E9E9E);
      case 'awaiting_receipt':
        return const Color(0xFF6A4FB6);
      default:
        return const Color(0xFFB07A2A);
    }
  }

  String _label() {
    switch (status) {
      case 'pending_confirmation':
        return 'pending approval';
      case 'cancelled':
        return 'rejected';
      case 'awaiting_receipt':
        return 'awaiting receipt';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
      child: Text(
        _label(),
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

/// Mobile-only: the detail pane pushed as its own screen instead of shown
/// side-by-side.
class _AdminBookingDetailScreen extends StatelessWidget {
  final BookingRecord booking;
  const _AdminBookingDetailScreen({required this.booking});

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
      body: _BookingDetailPane(booking: booking, onDeleted: () => Navigator.of(context).pop()),
    );
  }
}

class _BookingDetailPane extends StatefulWidget {
  final BookingRecord booking;
  final VoidCallback? onDeleted;
  const _BookingDetailPane({required this.booking, this.onDeleted});

  @override
  State<_BookingDetailPane> createState() => _BookingDetailPaneState();
}

class _BookingDetailPaneState extends State<_BookingDetailPane> {
  bool _updating = false;

  // The parent hands this pane a fixed snapshot, so it follows the live
  // booking itself — otherwise buttons like "Mark balance paid" or
  // "Mark refunded" would stay on screen after they've been used.
  StreamSubscription<List<BookingRecord>>? _liveSub;
  BookingRecord? _live;
  BookingRecord get _current => _live ?? widget.booking;

  @override
  void initState() {
    super.initState();
    _listenLive();
  }

  @override
  void didUpdateWidget(covariant _BookingDetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.booking.id != widget.booking.id) _listenLive();
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
    final reference = await RefundSentDialog.show(context, amount: _current.refundAmount);
    if (reference == null || !mounted) return;
    setState(() => _updating = true);
    try {
      await BookingRepository.markRefunded(_current.id, reference: reference);
      if (!mounted) return;
      TopToast.show(context, "Refund marked as sent.");
    } catch (e) {
      if (!mounted) return;
      TopToast.show(context, "Couldn't update refund: $e", kind: TopToastKind.error);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }
  bool _deleting = false;

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: AppColors.accent),
        title: const Text("Delete this booking?"),
        content: const Text(
          "This permanently removes the booking record — there's no undo. "
          "For a normal cancellation, use \"Reject\" instead so a record is kept.",
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text("Cancel")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await BookingRepository.deleteBooking(_current.id);
      if (!mounted) return;
      widget.onDeleted?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      TopToast.show(context, "Couldn't delete booking: $e", kind: TopToastKind.error);
    }
  }

  /// Confirms, then records that the customer paid what was left after
  /// their downpayment. The booking stream rebuilds this pane afterwards.
  Future<void> _markBalancePaid() async {
    final b = _current;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.payments_rounded, color: AppColors.accent),
        title: const Text("Mark balance as paid?"),
        content: Text(
          "Confirm you've received the remaining ₱${b.balanceDue} from this customer. "
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
      await BookingRepository.markBalancePaid(b.id);
      if (!mounted) return;
      TopToast.show(context, "Balance marked as paid.");
    } catch (e) {
      if (!mounted) return;
      TopToast.show(context, "Couldn't update payment: $e", kind: TopToastKind.error);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _setStatus(String status) async {
    RefundDecision? refund;
    if (status == 'cancelled' && RefundDecisionDialog.needed(_current)) {
      refund = await RefundDecisionDialog.show(context, _current);
      if (refund == null) return; // backed out — leave the booking as is
    }
    if (!mounted) return;
    setState(() => _updating = true);
    try {
      await BookingRepository.updateStatus(_current.id, status, refund: refund);
      if (mounted && status == 'confirmed') {
        TopToast.show(context, "Booking approved — that date is now locked for this customer.");
      }
    } on DoubleBookingException catch (e) {
      if (!mounted) return;
      _showDoubleBookingDialog(e.message);
    } catch (e) {
      if (!mounted) return;
      TopToast.show(context, "Couldn't update status: $e", kind: TopToastKind.error);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _openReschedule() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => RescheduleDialog(booking: _current),
    );
    if (done != true || !mounted) return;
    // The pane follows the live booking stream, so the new schedule appears
    // on its own — just confirm to the admin.
    TopToast.show(context, "Booking rescheduled — the customer has been notified and will see the new schedule.");
  }

  /// "Rescheduled from <old date · time> by <name>" so everyone can see the
  /// booking was moved, and why.
  Widget _rescheduledNote(BuildContext context, BookingRecord b) {
    const blue = Color(0xFF1565C0);
    final was = DateFormat('EEE, MMM d, yyyy').format(b.previousDate!) +
        ((b.previousTime ?? '').isEmpty ? '' : ' · ${b.previousTime}');
    final by = (b.rescheduledByStaffName ?? '').trim();
    final why = (b.rescheduleReason ?? '').trim();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
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

  /// A clash is worth more than a snackbar — it means the approval didn't
  /// happen, so it gets a dialog the admin has to acknowledge.
  void _showDoubleBookingDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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

  @override
  Widget build(BuildContext context) {
    final b = _current;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RefundStatusCard(booking: b, busy: _updating, onMarkRefunded: _markRefunded),
          if (b.wasRescheduled && b.previousDate != null) _rescheduledNote(context, b),
          _detailCard(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(b.packageName,
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                    ),
                    _StatusChip(status: b.status),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: AppPalette.divider(context)),
                const SizedBox(height: 4),
                _detailRow(context, Icons.calendar_today_rounded, "Date", DateFormat('EEEE, MMM d, yyyy').format(b.date)),
                _detailRow(context, Icons.schedule_rounded, "Time", b.time),
                _detailRow(context, Icons.place_rounded, "Location", b.location.isNotEmpty ? b.location : "Not specified"),
                _detailRow(context, Icons.hourglass_bottom_rounded, "Duration", b.duration),
                if (b.guests != null) _detailRow(context, Icons.groups_rounded, "Guests", '${b.guests}'),
                _detailRow(context, Icons.sell_rounded, "Package Price", '₱${b.price}'),
                if (b.addOnNames.isNotEmpty)
                  _detailRow(context, Icons.add_circle_outline_rounded, "Add-ons", '${b.addOnNames.join(", ")} (+₱${b.addOnsPrice})'),
                Divider(height: 20, color: AppPalette.divider(context)),
                _detailRow(context, Icons.payments_rounded, "Total", '₱${b.totalPrice}', emphasize: true),
                if (b.isDownpayment) ...[
                  _detailRow(context, Icons.savings_outlined, "Paid so far", '₱${b.paidAmount} (downpayment)'),
                  _detailRow(
                    context,
                    Icons.account_balance_wallet_outlined,
                    "Balance",
                    b.hasBalance ? '₱${b.balanceDue} — collect on event day' : 'Settled',
                    emphasize: b.hasBalance,
                  ),
                ],
                Divider(height: 20, color: AppPalette.divider(context)),
                _detailRow(context, Icons.badge_outlined, "Customer ID", b.userId),
                if (b.createdAt != null) _detailRow(context, Icons.event_available_rounded, "Booked", DateFormat('MMM d, yyyy h:mm a').format(b.createdAt!)),
                if (b.status == 'confirmed' && (b.acceptedByStaffName?.isNotEmpty ?? false))
                  _detailRow(
                    context,
                    Icons.verified_user_outlined,
                    "Accepted By",
                    b.acceptedAt != null
                        ? "${b.acceptedByStaffName} · ${DateFormat('MMM d, h:mm a').format(b.acceptedAt!)}"
                        : b.acceptedByStaffName!,
                  ),
                if (b.status == 'cancelled' && (b.rejectedByStaffName?.isNotEmpty ?? false))
                  _detailRow(
                    context,
                    Icons.person_off_outlined,
                    "Rejected By",
                    b.rejectedAt != null
                        ? "${b.rejectedByStaffName} · ${DateFormat('MMM d, h:mm a').format(b.rejectedAt!)}"
                        : b.rejectedByStaffName!,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _detailCard(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle(context, "Payment Receipt"),
                const SizedBox(height: 10),
                if (b.receiptUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: buildReceiptImage(
                      b.receiptUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stack) => Container(
                        height: 160,
                        color: AppPalette.surface(context),
                        alignment: Alignment.center,
                        child: Text("Couldn't load receipt image", style: TextStyle(color: AppPalette.textMuted(context))),
                      ),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      children: [
                        Icon(Icons.image_not_supported_outlined, size: 18, color: AppPalette.textMuted(context)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            b.receiptFileName.isNotEmpty ? "Customer attached \"${b.receiptFileName}\", but it didn't save correctly." : "No receipt on file.",
                            style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ..._receiptScanInfo(context, b),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _detailCard(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle(context, "Approval"),
                const SizedBox(height: 4),
                Text(
                  "Only a staff member can approve or reject a booking request.",
                  style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    // Only the actions that make sense for the current status.
                    if (b.status == 'pending_confirmation' || b.status == 'awaiting_receipt') ...[
                      _statusButton(context, "Approve", "confirmed", icon: Icons.check_circle_rounded, color: AppColors.accent, filled: true),
                      _statusButton(context, "Reject", "cancelled", icon: Icons.cancel_rounded, color: const Color(0xFFDC2626)),
                    ],
                    if (b.status == 'confirmed') ...[
                      // Only after the event's start time has passed.
                      if (eventHasStarted(b.date, b.time))
                        _statusButton(context, "Mark Completed", "completed", icon: Icons.task_alt_rounded, color: AppColors.success),
                      _statusButton(context, "Reject", "cancelled", icon: Icons.cancel_rounded, color: const Color(0xFFDC2626)),
                    ],
                    if (b.hasBalance && b.status != 'cancelled' && b.status != 'awaiting_receipt')
                      OutlinedButton.icon(
                        onPressed: _updating ? null : _markBalancePaid,
                        icon: const Icon(Icons.payments_rounded, size: 16),
                        label: Text("Mark balance paid (₱${b.balanceDue})"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFE08A00),
                          side: const BorderSide(color: Color(0xFFE08A00)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_current.status == 'completed')
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppPalette.surface(context),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, size: 18, color: AppPalette.textMuted(context)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "This booking is completed, so it's kept as a permanent record and can't be deleted.",
                    style: TextStyle(fontSize: 12, height: 1.35, color: AppPalette.textMuted(context)),
                  ),
                ),
              ],
            ),
          )
          else
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFDC2626)),
                    SizedBox(width: 6),
                    Text("Danger Zone", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "Permanently deletes this booking record — there's no undo. Use \"Reject\" above for a normal cancellation instead.",
                  style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _deleting ? null : _confirmDelete,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  icon: _deleting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.delete_outline, size: 16),
                  label: Text(_deleting ? "Deleting..." : "Delete Booking", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailCard(BuildContext context, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.soft,
        border: Border.all(color: AppPalette.divider(context).withValues(alpha: 0.5)),
      ),
      child: child,
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(text, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)));
  }

  Widget _detailRow(BuildContext context, IconData icon, String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: emphasize ? AppColors.accent : AppPalette.textMuted(context)),
          const SizedBox(width: 10),
          SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)))),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: emphasize ? 14 : 12,
                fontWeight: FontWeight.w700,
                color: emphasize ? AppColors.accent : AppPalette.textPrimary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusButton(BuildContext context, String label, String status, {required IconData icon, required Color color, bool filled = false}) {
    final isCurrent = _current.status == status;
    // A slot hold has no receipt to check yet, so there's nothing to accept
    // or mark done — it either turns into a real request or auto-rejects.
    final blockedByHold = _current.isAwaitingReceipt && (status == 'confirmed' || status == 'completed');
    final disabled = _updating || isCurrent || blockedByHold;
    final label2 = isCurrent ? "$label (current)" : label;

    if (filled) {
      return FilledButton.icon(
        onPressed: disabled ? null : () => _setStatus(status),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
        icon: Icon(icon, size: 16),
        label: Text(label2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      );
    }
    return OutlinedButton.icon(
      onPressed: disabled ? null : () => _setStatus(status),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: disabled ? 0.3 : 1)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

/// Opens the self-service "Change Password" dialog for the signed-in
/// admin. Requires their current password (Firebase needs a recent
/// sign-in before it allows a password change — see
/// `AdminService.changePassword`), a new password, and a matching
/// confirmation.
Future<void> _showAdminChangePasswordDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => const _AdminChangePasswordDialog(),
  );
}

class _AdminChangePasswordDialog extends StatefulWidget {
  const _AdminChangePasswordDialog();

  @override
  State<_AdminChangePasswordDialog> createState() => _AdminChangePasswordDialogState();
}

class _AdminChangePasswordDialogState extends State<_AdminChangePasswordDialog> {
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
      await AdminService.instance.changePassword(currentPassword: current, newPassword: next);
      if (!mounted) return;
      Navigator.of(context).pop();
      TopToast.show(context, "Password changed.");
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
}) {
  return _ReceiptImage(value: value, fit: fit, height: height, width: width, errorBuilder: errorBuilder);
}

class _ReceiptImage extends StatelessWidget {
  final String value;
  final BoxFit fit;
  final double? height;
  final double? width;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  const _ReceiptImage({required this.value, required this.fit, required this.height, required this.width, required this.errorBuilder});

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
    return Image.network(value, fit: fit, height: height, width: width, errorBuilder: errorBuilder);
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
                      TopToast.show(context, "Reference number copied");
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


/// True once the event's scheduled start (date + "h:mm AM/PM" time) has passed.
/// Returns false if the time string can't be parsed, so the button stays hidden.
bool eventHasStarted(DateTime date, String time) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$', caseSensitive: false).firstMatch(time.trim());
  if (m == null) return false;
  var hour = int.parse(m.group(1)!) % 12;
  if (m.group(3)!.toUpperCase() == 'PM') hour += 12;
  final start = DateTime(date.year, date.month, date.day, hour, int.parse(m.group(2)!));
  return !DateTime.now().isBefore(start);
}
