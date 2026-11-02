import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// One tab definition for [GlassBottomNav].
class NavTabItem {
  final IconData icon;
  final IconData? activeIcon;
  final String label;
  const NavTabItem({required this.icon, required this.label, this.activeIcon});
}

/// The trailing "More" tab. Dashboards append it after their 4 primary tabs
/// and open `showMoreMenuSheet` when it's tapped (instead of switching
/// section) — that's how every other section stays reachable on a phone
/// without cramming 6-7 tabs into the pill.
const NavTabItem kMoreNavTab = NavTabItem(
  icon: Icons.grid_view_outlined,
  activeIcon: Icons.grid_view_rounded,
  label: "More",
);

/// Floating glass pill nav bar, styled to match the customer app's
/// `AppBottomNav` (blurred glass background, accent glow bubble on the
/// active tab). Unlike the customer app's version — which drives
/// `react-router`-style named routes — this one is index-based so it can
/// drive the staff dashboard's internal `_section` state instead.
class GlassBottomNav extends StatelessWidget {
  final List<NavTabItem> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const GlassBottomNav({super.key, required this.tabs, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppPalette.navGlass(context),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.08 : 0.6)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 40, offset: const Offset(0, 10)),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(tabs.length, (i) {
                      final tab = tabs[i];
                      final isActive = i == currentIndex;
                      // Expanded so every tab gets an equal share of the
                      // pill — 7 tabs no longer overflow on narrow phones.
                      return Expanded(
                        child: _NavTab(
                          label: tab.label,
                          icon: isActive ? (tab.activeIcon ?? tab.icon) : tab.icon,
                          isActive: isActive,
                          onTap: () => onTap(i),
                        ),
                      );
                    }),
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

class _NavTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _NavTab({required this.label, required this.icon, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isActive ? AppColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isActive
                      ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 6))]
                      : null,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isActive ? Colors.white : const Color(0xFF9CA3AF),
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isActive ? AppColors.accent : const Color(0xFF9CA3AF),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
