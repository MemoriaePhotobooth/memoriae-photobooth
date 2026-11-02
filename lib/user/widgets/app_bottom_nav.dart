import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

class AppTabDef {
  final String route;
  final String label;
  final IconData icon;
  const AppTabDef({required this.route, required this.label, required this.icon});
}

/// Port of the `TABS` array. Order/index maps 1:1 to [AppBottomNav.currentIndex]
/// and to `AppDesktopSidebar`'s selected index — both navs share this list so
/// they can never drift out of sync.
const List<AppTabDef> kAppTabs = [
  AppTabDef(route: "/", label: "Home", icon: Icons.home),
  AppTabDef(route: "/book", label: "Book", icon: Icons.calendar_today),
  AppTabDef(route: "/rent", label: "Rent", icon: Icons.camera),
  AppTabDef(route: "/calendar", label: "Calendar", icon: Icons.calendar_month),
  AppTabDef(route: "/announcements", label: "News", icon: Icons.campaign),
  AppTabDef(route: "/messages", label: "Messages", icon: Icons.chat_bubble),
  AppTabDef(route: "/profile", label: "Profile", icon: Icons.person),
  AppTabDef(route: "/bookings", label: "My Bookings", icon: Icons.receipt_long),
];

/// A tab shown directly on the mobile pill. [tabIndex] points into
/// [kAppTabs]; the icons here are the softer outlined/filled pair used only
/// by the mobile nav (the desktop sidebar keeps the icons from [kAppTabs]).
class _MobileTab {
  final int tabIndex;
  final IconData icon;
  final IconData activeIcon;
  const _MobileTab(this.tabIndex, this.icon, this.activeIcon);
}

const List<_MobileTab> _kMobileTabs = [
  _MobileTab(0, Icons.home_outlined, Icons.home_rounded),
  _MobileTab(1, Icons.calendar_today_outlined, Icons.calendar_today_rounded),
  _MobileTab(2, Icons.photo_camera_outlined, Icons.photo_camera_rounded),
  _MobileTab(3, Icons.calendar_month_outlined, Icons.calendar_month_rounded),
  _MobileTab(5, Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded),
  _MobileTab(7, Icons.receipt_long_outlined, Icons.receipt_long_rounded),
  _MobileTab(6, Icons.person_outline_rounded, Icons.person_rounded),
];

/// Mobile floating pill nav: icon-only circles for every tab (News lives on
/// the dashboard, so it is not shown here), the active one filled with the
/// brand accent. Circles shrink to fit narrow screens.
///
/// Meant to be layered as a floating overlay — see `AppLayoutShell`.
class AppBottomNav extends StatelessWidget {
  final int currentIndex;

  const AppBottomNav({super.key, required this.currentIndex});

  void _goTo(BuildContext context, int index) {
    if (index == currentIndex) return;
    Navigator.of(context).pushReplacementNamed(kAppTabs[index].route);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppPalette.navGlass(context),
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.06),
                    ),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.14), blurRadius: 32, offset: const Offset(0, 12)),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = (constraints.maxWidth / _kMobileTabs.length).clamp(34.0, 48.0);
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final tab in _kMobileTabs)
                            _NavCircle(
                              label: kAppTabs[tab.tabIndex].label,
                              icon: tab.icon,
                              activeIcon: tab.activeIcon,
                              isActive: tab.tabIndex == currentIndex,
                              size: size,
                              onTap: () => _goTo(context, tab.tabIndex),
                            ),
                        ],
                      );
                    },
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

class _NavCircle extends StatelessWidget {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool isActive;
  final double size;
  final VoidCallback onTap;

  const _NavCircle({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.isActive,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 600),
      child: Semantics(
        button: true,
        selected: isActive,
        label: label,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            splashColor: AppColors.accent.withValues(alpha: 0.15),
            highlightColor: AppColors.accent.withValues(alpha: 0.08),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? AppColors.accent : Colors.transparent,
                boxShadow: isActive ? AppShadows.accentGlowSmall : null,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOutBack,
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  isActive ? activeIcon : icon,
                  key: ValueKey<bool>(isActive),
                  size: size * 0.46,
                  color: isActive
                      ? AppColors.onAccent
                      : (isDark ? Colors.white.withValues(alpha: 0.62) : AppPalette.textSecondary(context)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
