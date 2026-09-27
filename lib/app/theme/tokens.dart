import 'package:flutter/material.dart';

/// SkorX design tokens, shared with the web app (MOBILE-APP-BRIEF.md section 4).
/// Dark is the hero look; light mode uses darker "ink" variants so neon lime
/// and cyan are never used as text on white.
class SkorxColors {
  const SkorxColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceElevated,
    required this.surfaceInteractive,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.blue,
    required this.cyan,
    required this.navy,
    required this.lime,
    required this.limeText,
    required this.live,
    required this.success,
    required this.warning,
  });

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceElevated;
  final Color surfaceInteractive;
  final Color border;
  final Color text;
  final Color textMuted;
  final Color blue;
  final Color cyan;
  final Color navy;
  final Color lime;

  /// Lime that is safe to use for text on this background.
  final Color limeText;
  final Color live;
  final Color success;

  /// Closing soon, few spots left, pending.
  final Color warning;

  static const dark = SkorxColors(
    background: Color(0xFF060A10),
    surface: Color(0xFF0D131C),
    surfaceMuted: Color(0xFF131A24),
    surfaceElevated: Color(0xFF131A26),
    surfaceInteractive: Color(0xFF182130),
    border: Color(0xFF1F2A3A),
    text: Color(0xFFF2F5F9),
    textMuted: Color(0xFF8B96A5),
    blue: Color(0xFF3BA0F0),
    cyan: Color(0xFF4DD8F0),
    navy: Color(0xFF0F1D30),
    lime: Color(0xFFC7EA3A),
    limeText: Color(0xFFD7F062),
    live: Color(0xFFFB7185),
    success: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
  );

  static const light = SkorxColors(
    background: Color(0xFFF5F7FA),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF6F8FA),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceInteractive: Color(0xFFEEF3F9),
    border: Color(0xFFDDE4EC),
    text: Color(0xFF0B1C33),
    textMuted: Color(0xFF5B6778),
    blue: Color(0xFF1E7FE0),
    cyan: Color(0xFF2BC4E0),
    navy: Color(0xFF0B1C33),
    lime: Color(0xFFC7EA3A),
    limeText: Color(0xFF6F8F00),
    live: Color(0xFFE11D48),
    success: Color(0xFF059669),
    warning: Color(0xFFB45309),
  );
}

/// Radii used across the app.
abstract final class SkorxRadius {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 22.0;
  static const xl = 28.0;
}

/// Spacing scale, in logical pixels.
abstract final class SkorxSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}
