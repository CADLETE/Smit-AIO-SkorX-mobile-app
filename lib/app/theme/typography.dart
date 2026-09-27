import 'package:flutter/material.dart';

/// Organiser type: Plus Jakarta Sans for headlines and labels,
/// Barlow Condensed for scores (narrow tabular digits, like a stadium screen).
abstract final class SkorxType {
  static const family = 'BarlowCondensed';
  static const sans = 'PlusJakartaSans';

  /// Heavy headline, e.g. "Ready to play?". Sizes are the old scale, drawn
  /// a step smaller.
  static TextStyle headline(double size, {Color? color, FontWeight weight = FontWeight.w900}) => TextStyle(
        fontFamily: sans,
        fontSize: size * 0.72,
        fontWeight: FontWeight.w800,
        height: 1.1,
        letterSpacing: -0.5,
        color: color,
      );

  /// Upright numerals for scores and stats; tabular so digits don't jump.
  static TextStyle score(double size, {Color? color}) => TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: FontWeight.w800,
        height: 1,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: color,
      );

  /// Small tracked caps label, e.g. "LIVE NOW".
  static TextStyle label({Color? color, double size = 13}) => TextStyle(
        fontFamily: sans,
        fontSize: size * 0.82,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
        color: color,
      );
}
