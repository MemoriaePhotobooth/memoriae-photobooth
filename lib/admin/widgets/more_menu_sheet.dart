import '../../shared/app_modal.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../theme/theme_controller.dart';

/// One tile inside the "More" sheet.
class MoreMenuItem {
  final IconData icon;
  final String label;

  /// Highlights the tile (accent fill) — used for the section currently open.
  final bool selected;

  /// Called AFTER the sheet has closed, so it's safe to setState / navigate.
  final VoidCallback onTap;

  const MoreMenuItem({required this.icon, required this.label, required this.onTap, this.selected = false});
}

/// A titled group of tiles (e.g. "Operations", "Records").
class MoreMenuGroup {
  final String title;
  final List<MoreMenuItem> items;
  const MoreMenuGroup({required this.title, required this.items});
}

/// Phone-only replacement for the long sidebar: the bottom nav keeps just a
/// few primary tabs plus a "More" tab, and "More" opens this grid sheet with
/// every other section, plus the account actions (dark mode, sign out) that
/// used to crowd the header.
Future<void> showMoreMenuSheet(
  BuildContext context, {
  required List<MoreMenuGroup> groups,
  required VoidCallback onLogout,
}) {
  // Opens as a centered popup (not a sheet stuck to the bottom edge), so
  // it appears right where the person is looking.
  return showAppModal<void>(
    context,
    maxWidth: 520,
    builder: (_) => _MoreMenuSheet(groups: groups, onLogout: onLogout),
  );
}

class _MoreMenuSheet extends StatelessWidget {
  final List<MoreMenuGroup> groups;
  final VoidCallback onLogout;

  const _MoreMenuSheet({required this.groups, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppPalette.bg(context),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "Menu",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context)),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 22),
                    color: AppPalette.textMuted(context),
                    tooltip: "Close",
                  ),
                ],
              ),
            ),
            // Scrolls on short screens (landscape / small phones) instead of
            // overflowing.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final g in groups) ...[
                      _buildGroup(context, g),
                      const SizedBox(height: 16),
                    ],
                    _buildFooter(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroup(BuildContext context, MoreMenuGroup group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            group.title.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppPalette.textMuted(context)),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 10.0;
            const columns = 3;
            // floor() so rounding can never push the 3rd tile onto a new row.
            final tileWidth = ((constraints.maxWidth - gap * (columns - 1)) / columns).floorToDouble();
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final item in group.items) SizedBox(width: tileWidth, child: _buildTile(context, item)),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildTile(BuildContext context, MoreMenuItem item) {
    final selected = item.selected;
    return Material(
      color: selected ? AppColors.accent : AppPalette.surface(context),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.of(context).pop();
          item.onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 24, color: selected ? Colors.white : AppColors.accent),
              const SizedBox(height: 8),
              // Fixed 2-line height so tiles in a row stay the same size
              // whether the label wraps or not.
              SizedBox(
                height: 30,
                child: Center(
                  child: Text(
                    item.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : AppPalette.textPrimary(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Row(
      children: [
        Expanded(
          // Stays open when toggled so the label/icon flip in place.
          child: ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeController.mode,
            builder: (context, _, __) {
              final dark = ThemeController.isDark;
              return _footerButton(
                context,
                icon: dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                label: dark ? "Light mode" : "Dark mode",
                color: AppPalette.textPrimary(context),
                onTap: () => ThemeController.setDark(!dark),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _footerButton(
            context,
            icon: Icons.logout,
            label: "Sign out",
            color: const Color(0xFFDC2626),
            onTap: () {
              Navigator.of(context).pop();
              onLogout();
            },
          ),
        ),
      ],
    );
  }

  Widget _footerButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppPalette.surface(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
