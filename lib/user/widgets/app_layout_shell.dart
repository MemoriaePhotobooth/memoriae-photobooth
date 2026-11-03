import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'app_bottom_nav.dart';
import 'app_desktop_sidebar.dart';
import 'chatbot_bubble.dart';
import 'offline_banner.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Port of `AppLayout`.
///
/// React Router's `<Outlet/>` renders whichever nested route matched;
/// Flutter has no direct equivalent, so [child] plays that role — pass in
/// whichever tab screen's content should appear here. [currentIndex] is
/// forwarded to [AppBottomNav] / [AppDesktopSidebar] the same way `BottomNav`
/// derives its active tab from the current URL via `NavLink`.
///
/// Responsive behavior: a single `LayoutBuilder` breakpoint (matching the
/// one used by the Admin/Staff dashboards) decides the chrome. Below
/// [_desktopBreakpoint] this is the mobile experience — content capped at a
/// phone-ish width, floating pill nav overlaid at the bottom. At or above
/// it, this switches to a desktop experience — a persistent left sidebar
/// instead of the floating nav, and a wider (but still capped, so text
/// doesn't stretch edge-to-edge on ultrawide monitors) content column.
class AppLayoutShell extends StatelessWidget {
  final Widget child;
  final int currentIndex;

  static const double _desktopBreakpoint = 900;

  const AppLayoutShell(
      {super.key, required this.child, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    // Index 5 = Messages. The chatbot button is hidden on this tab: the
    // customer is already in the real chat with staff.
    final onMessages = currentIndex == 5;
    // System Back from any tab other than Home returns to the dashboard
    // instead of leaving the app (tabs replace each other, so there is no
    // previous route to pop to).
    return PopScope(
      // On Home, Back doesn't exit right away: it asks for confirmation first.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (currentIndex != 0) {
          Navigator.of(context).pushReplacementNamed('/');
          return;
        }
        final exit = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => Dialog(
            backgroundColor: AppPalette.cardBg(dialogContext),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.accentTint(0.10),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.logout_rounded, color: AppColors.accent, size: 26),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Exit app?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppPalette.textPrimary(dialogContext),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Are you sure you want to close Memoriae?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: AppPalette.textSecondary(dialogContext),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(dialogContext).pop(false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.accentText(dialogContext),
                              side: BorderSide(color: AppColors.accentText(dialogContext)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: const Text('Stay', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(dialogContext).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: AppColors.onAccent,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: const Text('Exit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        if (exit == true) {
          SystemNavigator.pop();
        }
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppPalette.bg(context),
          gradient: Theme.of(context).brightness == Brightness.dark ? AppGradients.page : null,
        ),
        child: Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Colors.transparent
            : (currentIndex == 0 ? AppPalette.groupedBg(context) : AppPalette.bg(context)),
        body: SafeArea(
          child: Column(
            children: [
              const OfflineBanner(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop =
                        constraints.maxWidth >= _desktopBreakpoint;
                    if (isDesktop) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppDesktopSidebar(currentIndex: currentIndex),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 900),
                                    child: child,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (!onMessages)
                            const ChatbotBubble(
                                fabBottom: 24,
                                panelBottom: 24,
                                right: 24),
                        ],
                      );
                    }
                    return Stack(
                      children: [
                        // Bottom padding keeps content clear of the floating nav.
                        // maxWidth only kicks in on wide windows below the desktop
                        // breakpoint so cards don't stretch edge-to-edge there; on
                        // phone-width screens this is a no-op.
                        Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 640),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 96),
                              child: child,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: AppBottomNav(currentIndex: currentIndex),
                        ),
                        // Raised above the floating nav; the open panel sits low and
                        // covers the nav while chatting.
                        if (!onMessages)
                          ChatbotBubble(
                              fabBottom: 104,
                              panelBottom: 12,
                              // On wide windows the content column is centered
                              // and capped at 640, so keep the chat button
                              // inside it rather than at the far screen edge.
                              right: 16 + (constraints.maxWidth > 640 ? (constraints.maxWidth - 640) / 2 : 0.0)),
                      ],
                    );
                  },
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
