import 'package:flutter/material.dart';
import '../theme/app_palette.dart';

/// Round back button (white circle, soft shadow, chevron) used across the
/// user app. By default it just goes back; pass [onPressed] to override.
///
/// In an AppBar use `leading: const CircleBackButton.appBar()` together
/// with `leadingWidth: CircleBackButton.appBarLeadingWidth`.
class CircleBackButton extends StatelessWidget {
  const CircleBackButton({super.key, this.onPressed, this.tooltip = 'Back'}) : _inAppBar = false;
  const CircleBackButton.appBar({super.key, this.onPressed, this.tooltip = 'Back'}) : _inAppBar = true;

  static const double appBarLeadingWidth = 68;

  final VoidCallback? onPressed;
  final String tooltip;
  final bool _inAppBar;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final button = Tooltip(
      message: tooltip,
      child: Material(
        color: AppPalette.cardBg(context),
        shape: const CircleBorder(),
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.6 : 0.35),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed ?? () => Navigator.of(context).maybePop(),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            child: Icon(Icons.chevron_left_rounded, size: 30, color: AppPalette.textPrimary(context)),
          ),
        ),
      ),
    );
    if (!_inAppBar) return button;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(padding: const EdgeInsets.only(left: 16), child: button),
    );
  }
}
