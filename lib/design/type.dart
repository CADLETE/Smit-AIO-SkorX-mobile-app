import 'package:flutter/material.dart';

/// SkorX type. Plus Jakarta Sans carries titles, labels and reading text;
/// Barlow Condensed is kept for scoreboard numbers, where its narrow tabular
/// digits read like a stadium screen. Sizes passed in are the old scale and
/// are drawn a step smaller, so every screen tightens up together.
abstract final class SxType {
  static const display = 'BarlowCondensed';
  static const sans = 'PlusJakartaSans';
  static const _tabular = [FontFeature.tabularFigures()];

  /// Rating, live score: 64–88.
  static TextStyle hero(double size, Color color) => TextStyle(
        fontFamily: display,
        fontSize: size * 0.9,
        fontWeight: FontWeight.w800,
        height: 0.9,
        letterSpacing: -1,
        fontFeatures: _tabular,
        color: color,
      );

  /// Scores and stat numbers.
  static TextStyle number(double size, Color color, {FontWeight weight = FontWeight.w700}) => TextStyle(
        fontFamily: display,
        fontSize: size,
        fontWeight: weight,
        height: 1,
        fontFeatures: _tabular,
        color: color,
      );

  /// Screen and card titles: tight, heavy sans.
  static TextStyle title(Color color, {double size = 32}) => TextStyle(
        fontFamily: sans,
        fontSize: size * 0.74,
        fontWeight: FontWeight.w800,
        height: 1.12,
        letterSpacing: -0.4,
        color: color,
      );

  /// Small tracked caps: section labels, status words.
  static TextStyle label(Color color, {double size = 12, FontWeight weight = FontWeight.w700}) => TextStyle(
        fontFamily: sans,
        fontSize: size * 0.84,
        fontWeight: weight,
        height: 1.2,
        letterSpacing: 0.9,
        color: color,
      );

  /// WON / LOST: the one italic in the system.
  static TextStyle verdict(double size, Color color) => TextStyle(
        fontFamily: display,
        fontSize: size,
        fontWeight: FontWeight.w800,
        fontStyle: FontStyle.italic,
        height: 1,
        letterSpacing: 0.6,
        color: color,
      );

  static TextStyle heading(Color color, {double size = 17}) => TextStyle(
        fontFamily: sans,
        fontSize: size * 0.9,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.2,
        color: color,
      );

  static TextStyle body(Color color, {double size = 15}) => TextStyle(
        fontFamily: sans,
        fontSize: size * 0.92,
        fontWeight: FontWeight.w500,
        height: 1.45,
        color: color,
      );

  static TextStyle caption(Color color, {double size = 13}) => TextStyle(
        fontFamily: sans,
        fontSize: size * 0.92,
        fontWeight: FontWeight.w500,
        height: 1.35,
        color: color,
      );
}
