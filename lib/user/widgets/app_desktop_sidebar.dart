import 'package:flutter/material.dart';
import 'app_bottom_nav.dart';
import '../theme/app_colors.dart';

/// Desktop counterpart to [AppBottomNav] — a persistent left rail instead
/// of a floating pill, shown once the window is wide enough (see
/// `AppLayoutShell`'s breakpoint). Shares [kAppTabs] with the mobile nav so
/// the two can never list different tabs.
class AppDesktopSidebar extends StatelessWidget {
  final int currentIndex;

  const AppDesktopSidebar({super.key, required this.currentIndex});

  void _handleTap(BuildContext context, int index) {
    if (index == currentIndex) return;
    Navigator.of(context).pushReplacementNamed(kAppTabs[index].route);
  }

  @override
  Widget build(BuildContext context) {
    // Solid brand-maroon rail instead of a flat grey/dark panel — same
    // accent used everywhere else in the app, so the sidebar reads as
    // "branded chrome" rather than a plain system panel.
    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.accent, Color.lerp(AppColors.accent, Colors.black, 0.18)!],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(4, 0))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt, color: AppColors.accent, size: 16),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    "Memoriae",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.3),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          ...List.generate(kAppTabs.length, (i) {
            final tab = kAppTabs[i];
            final isActive = i == currentIndex;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Material(
                color: isActive ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _handleTap(context, i),
                  splashColor: Colors.white.withValues(alpha: 0.15),
                  highlightColor: Colors.white.withValues(alpha: 0.08),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: Row(
                      children: [
                        Icon(tab.icon, size: 18, color: isActive ? AppColors.accent : Colors.white.withValues(alpha: 0.75)),
                        const SizedBox(width: 12),
                        Text(
                          tab.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                            color: isActive ? AppColors.accent : Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              "© Memoriae Photobooth",
              style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.55)),
            ),
          ),
        ],
      ),
    );
  }
}
