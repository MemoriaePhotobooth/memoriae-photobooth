import 'package:flutter/material.dart';

/// Design tokens (Memoriae maroon):
///   accent     = maroon sampled from the logo
///   onAccent   = text/icon colour that sits ON the accent (white)
///   forest*    = the dark maroon-black backgrounds (name kept from the first pass)
class AppColors {
  AppColors._();

  /// Maroon brand accent (buttons, active tab, highlights).
  static const Color accent = Color(0xFF6E1B1E);

    static const Color onAccent = Colors.white;

  /// Accent used for TEXT on light backgrounds.
  static const Color accentOnLight = Color(0xFF6E1B1E);

  static const Color forest900 = Color(0xFF0D0607);
  static const Color forest800 = Color(0xFF1A0A0B);
  static const Color forest700 = Color(0xFF2A0D0F);
  static const Color forest600 = Color(0xFF3A1214);
  static const Color forestGlow = Color(0xFF3A1214);

  static const Color brandCream = Color(0xFFFBF4E8);

  static const Color surfaceGrey = Color(0xFFF4F4F4);
  static const Color stone900 = Color(0xFF1A1A1A);
  static const Color stone500 = Color(0xFF78716C);
  static const Color stone400 = Color(0xFFA8A29E);
  static const Color stone200 = Color(0xFFE7E5E4);
  static const Color border = Color(0xFFD1D1D1);
  static const Color success = Color(0xFF22C55E);

  /// Secondary highlight (kept for screens that used the old gold block).
  static const Color highlight = Color(0xFFE0B24C);

  static Color accentTint(double opacity) => accent.withValues(alpha: opacity);

  /// Accent for TEXT: lighter maroon tint on dark backgrounds.
  static Color accentText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFFE57F84) : accent;
}

class AppShadows {
  AppShadows._();

  static List<BoxShadow> soft = [
    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 4)),
  ];

  static List<BoxShadow> card = [
    BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8)),
  ];

  static List<BoxShadow> phone = [
    BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 60, offset: const Offset(0, 20)),
  ];

  static List<BoxShadow> accentGlow = [
    BoxShadow(color: AppColors.accent.withValues(alpha: 0.30), blurRadius: 24, offset: const Offset(0, 12)),
  ];

  static List<BoxShadow> accentGlowSmall = [
    BoxShadow(color: AppColors.accent.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 8)),
  ];
}

/// Shared gradients for the dark green screens.
class AppGradients {
  AppGradients._();

  /// Page background: a soft green glow at the top fading into near-black.
  static const LinearGradient page = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.forestGlow, AppColors.forest800, AppColors.forest900],
    stops: [0.0, 0.38, 1.0],
  );

  /// Hero / feature card.
  static const LinearGradient card = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8A2429), Color(0xFF3A1214)],
  );
}
