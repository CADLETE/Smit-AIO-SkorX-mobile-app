import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// SkorX design tokens, drawn only from the brand kit (the logo): deep navy,
/// volt lime (the ball), SkorX blue and cyan (the X), and white. Live red and
/// caution amber are status colours, never decoration. Gradients mix brand
/// colours only.
@immutable
class SxColors extends ThemeExtension<SxColors> {
  const SxColors({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.surfaceAlt,
    required this.line,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.volt,
    required this.voltFill,
    required this.onVolt,
    required this.live,
    required this.info,
    required this.caution,
    required this.primaryFill,
    required this.onPrimary,
    required this.blue,
    required this.cyan,
    required this.deep,
    required this.olive,
    required this.glow,
  });

  final Brightness brightness;

  /// The page.
  final Color canvas;

  /// Raised blocks and sheets.
  final Color surface;

  /// Inputs, pressed states, chart tracks.
  final Color surfaceAlt;

  /// Hairlines and the net line.
  final Color line;
  final Color ink;
  final Color inkMuted;

  /// Losing scores, disabled, placeholders.
  final Color inkFaint;

  /// Wins, the player's side, the brand accent. Safe as text on [canvas].
  final Color volt;

  /// Volt as a fill (buttons, badges, bars).
  final Color voltFill;
  final Color onVolt;

  /// LIVE, and nothing else.
  final Color live;

  /// Upcoming, registered, links.
  final Color info;

  /// Closing soon, few spots left.
  final Color caution;

  /// The one primary button per screen: volt in dark, ink in light.
  final Color primaryFill;
  final Color onPrimary;

  /// SkorX blue: the X in the wordmark.
  final Color blue;

  /// SkorX cyan, the lighter end of the X.
  final Color cyan;

  /// Navy-blue, the dark end of hero gradients (the logo's outline).
  final Color deep;

  /// The shaded side of the volt ball.
  final Color olive;

  /// Strength of coloured glows and ambient light (higher in dark).
  final double glow;

  bool get isDark => brightness == Brightness.dark;

  /// The primary action: the volt ball, lit from the top left.
  LinearGradient get brand => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.lerp(voltFill, Colors.white, 0.22)!, voltFill, Color.lerp(voltFill, olive, 0.45)!],
      );

  /// Hero cards: navy into SkorX blue into cyan, like the wordmark's X.
  LinearGradient get hero => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [deep, blue, Color.lerp(cyan, blue, 0.3)!],
        stops: const [0, 0.62, 1],
      );

  /// Live things.
  LinearGradient get heat => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.lerp(live, Colors.white, 0.12)!, Color.lerp(live, Colors.black, 0.18)!],
      );

  /// Cool accent: cyan into blue.
  LinearGradient get cool => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [cyan, blue],
      );

  /// A raised card: a faint top-left sheen over the surface.
  LinearGradient get card => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [Color.lerp(surface, blue, 0.08)!, surface]
            : [surface, Color.lerp(surface, blue, 0.03)!],
      );

  /// Hairline around raised cards.
  Color get cardEdge => isDark ? const Color(0x1FFFFFFF) : line;

  /// Soft shadow under raised cards.
  List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: isDark ? const Color(0x66000000) : deep.withValues(alpha: 0.08),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];

  /// A coloured glow under something that should draw the eye.
  List<BoxShadow> glowOf(Color color, {double strength = 1}) => [
        BoxShadow(color: color.withValues(alpha: 0.35 * glow * strength), blurRadius: 28, offset: const Offset(0, 10)),
      ];


  static const dark = SxColors(
    brightness: Brightness.dark,
    canvas: Color(0xFF060A10),
    surface: Color(0xFF0D131C),
    surfaceAlt: Color(0xFF131A26),
    line: Color(0xFF1F2A3A),
    ink: Color(0xFFF2F5F9),
    inkMuted: Color(0xFF8B96A5),
    inkFaint: Color(0xFF56606E),
    volt: Color(0xFFD4F53C),
    voltFill: Color(0xFFD4F53C),
    onVolt: Color(0xFF09121E),
    live: Color(0xFFFB7185),
    info: Color(0xFF4DB3F5),
    caution: Color(0xFFFBBF24),
    primaryFill: Color(0xFFD4F53C),
    onPrimary: Color(0xFF09121E),
    blue: Color(0xFF3BA0F0),
    cyan: Color(0xFF4DD8F0),
    deep: Color(0xFF0F2A4A),
    olive: Color(0xFF9DB52A),
    glow: 1,
  );

  static const light = SxColors(
    brightness: Brightness.light,
    canvas: Color(0xFFF5F7FA),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEEF3F9),
    line: Color(0xFFDDE4EC),
    ink: Color(0xFF0B1C33),
    inkMuted: Color(0xFF5B6778),
    inkFaint: Color(0xFFA3ADBA),
    volt: Color(0xFF6F8F00),
    voltFill: Color(0xFFC7EA3A),
    onVolt: Color(0xFF0B1C33),
    live: Color(0xFFE11D48),
    info: Color(0xFF1E7FE0),
    caution: Color(0xFFB45309),
    primaryFill: Color(0xFFC7EA3A),
    onPrimary: Color(0xFF0B1C33),
    blue: Color(0xFF1E7FE0),
    cyan: Color(0xFF0EA5E0),
    deep: Color(0xFF0F2A4A),
    olive: Color(0xFF8AA320),
    glow: 0.7,
  );

  /// The same palette for content drawn on a [hero] gradient: white ink,
  /// translucent white lines and surfaces.
  SxColors onHero() {
    const white = Color(0xFFFFFFFF);
    return SxColors(
      brightness: Brightness.dark,
      canvas: deep,
      surface: white.withValues(alpha: 0.12),
      surfaceAlt: white.withValues(alpha: 0.18),
      line: white.withValues(alpha: 0.28),
      ink: white,
      inkMuted: white.withValues(alpha: 0.78),
      inkFaint: white.withValues(alpha: 0.5),
      volt: SxColors.dark.volt,
      voltFill: SxColors.dark.voltFill,
      onVolt: SxColors.dark.onVolt,
      live: white,
      info: white,
      caution: SxColors.dark.caution,
      primaryFill: SxColors.dark.primaryFill,
      onPrimary: SxColors.dark.onPrimary,
      blue: blue,
      cyan: cyan,
      deep: deep,
      olive: olive,
      glow: glow,
    );
  }

  @override
  SxColors copyWith() => this;

  @override
  SxColors lerp(SxColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return SxColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      canvas: l(canvas, other.canvas),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      line: l(line, other.line),
      ink: l(ink, other.ink),
      inkMuted: l(inkMuted, other.inkMuted),
      inkFaint: l(inkFaint, other.inkFaint),
      volt: l(volt, other.volt),
      voltFill: l(voltFill, other.voltFill),
      onVolt: l(onVolt, other.onVolt),
      live: l(live, other.live),
      info: l(info, other.info),
      caution: l(caution, other.caution),
      primaryFill: l(primaryFill, other.primaryFill),
      onPrimary: l(onPrimary, other.onPrimary),
      blue: l(blue, other.blue),
      cyan: l(cyan, other.cyan),
      deep: l(deep, other.deep),
      olive: l(olive, other.olive),
      glow: glow + (other.glow - glow) * t,
    );
  }
}

extension SxContext on BuildContext {
  SxColors get sx => Theme.of(this).extension<SxColors>() ?? SxColors.dark;
}

/// 4-pt spacing.
abstract final class Sx {
  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0;
  static const s20 = 20.0;
  static const s24 = 24.0;
  static const s32 = 32.0;
  static const s48 = 48.0;

  /// Page gutter.
  static const gutter = 20.0;

  /// Gap between sections of a screen.
  static const section = 32.0;

  /// Content never grows wider than this (tablet, web).
  static const maxContent = 640.0;

  static const radius = 18.0;
  static const radiusSm = 12.0;
  static const radiusLg = 26.0;

  static const fast = Duration(milliseconds: 160);
  static const medium = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 520);
}

bool sxReduceMotion(BuildContext context) => MediaQuery.of(context).disableAnimations;

/// Looping decoration (ambient light, shine, floating graphics) never runs
/// under `flutter test`, where it would keep pumpAndSettle from settling.
final bool _loopsAllowed = kIsWeb || !Platform.environment.containsKey('FLUTTER_TEST');

/// Whether looping decoration should run here.
bool sxAmbientMotion(BuildContext context) => _loopsAllowed && !sxReduceMotion(context);
