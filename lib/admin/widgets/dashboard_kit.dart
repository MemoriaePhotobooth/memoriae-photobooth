import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Top header row for a role dashboard: an initials avatar + "Welcome
/// back" eyebrow + title on the left, small icon actions + the Memoriae
/// logo badge on the right. A direct port of `HomeScreen._buildHeader`
/// from the customer app, generalized so staff/admin can reuse it
/// instead of a plain `AppBar`.
class DashboardHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String initials;
  final List<Widget> actions;
  final VoidCallback? onAvatarTap;

  /// The cream Memoriae badge at the far right. Phone layouts turn this off
  /// to give the title room (the logo already lives in the desktop sidebar).
  final bool showLogo;

  const DashboardHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.initials,
    this.actions = const [],
    this.onAvatarTap,
    this.showLogo = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              InkWell(
                customBorder: const CircleBorder(),
                onTap: onAvatarTap,
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle, boxShadow: AppShadows.accentGlowSmall),
                  child: Text(initials, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(eyebrow, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context), letterSpacing: -0.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        ...actions,
        if (showLogo)
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: AppColors.brandCream, borderRadius: BorderRadius.circular(16)),
            child: Image.asset('assets/images/memoriae_logo.webp', fit: BoxFit.contain),
          ),
      ],
    );
  }
}

/// Small circular icon-button used in [DashboardHeader]'s action slot,
/// styled to sit comfortably next to the logo badge instead of a plain
/// `AppBar` icon.
class DashboardHeaderAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Widget? badge;

  /// Space to the right of the button. Pass 0 on the last action when the
  /// header has no logo badge after it, so it lines up with the page padding.
  final double trailingGap;

  const DashboardHeaderAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badge,
    this.trailingGap = 8,
  });

  @override
  Widget build(BuildContext context) {
    final button = Container(
      width: 44,
      height: 44,
      margin: EdgeInsets.only(right: trailingGap),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(16)),
      child: Icon(icon, size: 19, color: AppPalette.textPrimary(context)),
    );
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: badge == null ? button : Stack(clipBehavior: Clip.none, children: [button, Positioned(right: 4, top: 4, child: badge!)]),
      ),
    );
  }
}

/// Gradient "hero" banner, a direct port of the customer app's
/// `_buildHeroBanner` / login-screen hero (accent gradient, watermark
/// icon, pill eyebrow, bold title, muted subtitle) — used at the top of
/// the staff/admin dashboard instead of a plain section title so the
/// role apps read as the same product as the customer app.
class DashboardHeroBanner extends StatelessWidget {
  final IconData watermarkIcon;
  final String pillLabel;
  final String title;
  final String subtitle;
  final List<Widget>? stats;

  const DashboardHeroBanner({
    super.key,
    required this.watermarkIcon,
    required this.pillLabel,
    required this.title,
    required this.subtitle,
    this.stats,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accent, Color(0xFF9A3236)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppShadows.accentGlow,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -18,
            child: Icon(watermarkIcon, size: 100, color: Colors.white.withValues(alpha: 0.08)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
                child: Text(pillLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)),
              ),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.4)),
              const SizedBox(height: 6),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
              if (stats != null) ...[
                const SizedBox(height: 16),
                Row(children: stats!),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One number+label chip for [DashboardHeroBanner]'s `stats` row.
class HeroStat extends StatelessWidget {
  final String value;
  final String label;
  const HeroStat({super.key, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.75))),
        ],
      ),
    );
  }
}
