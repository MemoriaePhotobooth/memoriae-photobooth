import 'package:flutter/material.dart';

/// Design tokens:
///   accent = "#6E1B1E" (sampled from the Memoriae logo)
///   background grey = "#F4F4F4"
class AppColors {
  AppColors._();

  /// Sampled directly from the Memoriae logo artwork.
  static const Color accent = Color(0xFF6E1B1E);
  static const Color brandCream = Color(0xFFFBF4E8);
  static const Color highlight = Color(0xFFE0B24C);

  static const Color surfaceGrey = Color(0xFFF4F4F4);
  static const Color stone900 = Color(0xFF1A1A1A);
  static const Color stone500 = Color(0xFF78716C);
  static const Color stone400 = Color(0xFFA8A29E);
  static const Color stone200 = Color(0xFFE7E5E4);
  static const Color border = Color(0xFFD1D1D1);
  static const Color success = Color(0xFF22C55E);

  static Color accentTint(double opacity) => accent.withValues(alpha: opacity);
}

class AppShadows {
  AppShadows._();

  static List<BoxShadow> soft = [
    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 4)),
  ];

  static List<BoxShadow> card = [
    BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 24, offset: const Offset(0, 8)),
  ];

  static List<BoxShadow> phone = [
    BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 60, offset: const Offset(0, 20)),
  ];

  static List<BoxShadow> accentGlow = [
    BoxShadow(color: AppColors.accent.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 12)),
  ];

  static List<BoxShadow> accentGlowSmall = [
    BoxShadow(color: AppColors.accent.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 8)),
  ];
}