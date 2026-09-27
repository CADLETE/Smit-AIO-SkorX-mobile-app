import 'package:flutter/material.dart';

import '../../design/fx.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import 'tokens.dart';

/// Which workspace the theme is for. Player is personal and energetic
/// (cyan/blue); organizer is operational (lime/blue).
enum WorkspaceAccent { player, operations }

/// Builds the app theme. The two workspaces share every token except the
/// accent, so they read as one product with different emphasis.
ThemeData buildSkorxTheme({required Brightness brightness, required WorkspaceAccent accent}) {
  final colors = brightness == Brightness.dark ? SkorxColors.dark : SkorxColors.light;
  // The Player workspace is drawn with the SkorX player design system
  // (docs/PLAYER-APP.md §3); organiser keeps its tokens.
  final sx = brightness == Brightness.dark ? SxColors.dark : SxColors.light;
  final isOps = accent == WorkspaceAccent.operations;
  final primary = colors.blue;
  // Accent used for the active navigation indicator and highlights.
  final highlight = isOps ? colors.lime : colors.cyan;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: Colors.white,
    secondary: highlight,
    onSecondary: colors.navy,
    tertiary: colors.limeText,
    onTertiary: colors.navy,
    error: colors.live,
    onError: Colors.white,
    surface: colors.surface,
    onSurface: colors.text,
    onSurfaceVariant: colors.textMuted,
    surfaceContainerLowest: colors.background,
    surfaceContainerLow: colors.surfaceMuted,
    surfaceContainer: colors.surface,
    surfaceContainerHigh: colors.surfaceElevated,
    surfaceContainerHighest: colors.surfaceInteractive,
    outline: colors.border,
    outlineVariant: colors.border,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: SxType.sans,
    // Every route paints the ambient backdrop (SxPageTransitions), so
    // scaffolds are see-through.
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: isOps ? colors.background : sx.canvas,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: SxPageTransitions(),
        TargetPlatform.iOS: SxPageTransitions(),
        TargetPlatform.macOS: SxPageTransitions(),
        TargetPlatform.windows: SxPageTransitions(),
        TargetPlatform.linux: SxPageTransitions(),
        TargetPlatform.fuchsia: SxPageTransitions(),
      },
    ),
    extensions: [SkorxThemeExtension(colors: colors, highlight: highlight, accent: accent), sx],
  );

  final text = base.textTheme.apply(bodyColor: colors.text, displayColor: colors.text);

  final theme = base.copyWith(
    textTheme: text.copyWith(
      displayLarge: text.displayLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.5, fontSize: 48),
      headlineLarge: text.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8, fontSize: 26),
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6, fontSize: 23),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4, fontSize: 20),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3, fontSize: 18),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 15),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 13),
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w500),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 13.5, fontWeight: FontWeight.w500),
      bodySmall: text.bodySmall?.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.1, fontSize: 14),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      titleTextStyle: TextStyle(fontFamily: SxType.sans, fontSize: 18, fontWeight: FontWeight.w800, color: colors.text),
      foregroundColor: colors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: colors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SkorxRadius.lg),
        side: BorderSide(color: colors.border),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surface,
      indicatorColor: highlight.withValues(alpha: 0.18),
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? colors.text : colors.textMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: states.contains(WidgetState.selected) ? highlight : colors.textMuted),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // Same as the SkxButton primary: lime with navy ink.
        backgroundColor: colors.lime,
        foregroundColor: const Color(0xFF0B1C33),
        disabledBackgroundColor: colors.lime.withValues(alpha: 0.3),
        disabledForegroundColor: const Color(0xFF0B1C33).withValues(alpha: 0.5),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SkorxRadius.md)),
        textStyle: const TextStyle(fontFamily: SxType.sans, fontSize: 15, fontWeight: FontWeight.w800),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: isOps ? colors.surfaceElevated : sx.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SkorxRadius.xl)),
      titleTextStyle: TextStyle(fontFamily: SxType.sans, fontSize: 19, fontWeight: FontWeight.w800, color: colors.text),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: colors.border),
      labelStyle: const TextStyle(fontFamily: SxType.sans, fontWeight: FontWeight.w700, fontSize: 13),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: highlight),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: colors.border),
        foregroundColor: colors.text,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SkorxRadius.md)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: SkorxSpace.lg, vertical: SkorxSpace.lg),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SkorxRadius.md),
        borderSide: BorderSide(color: colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SkorxRadius.md),
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SkorxRadius.md),
        borderSide: BorderSide(color: primary, width: 2),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.surfaceInteractive,
      contentTextStyle: TextStyle(color: colors.text, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SkorxRadius.md)),
      insetPadding: const EdgeInsets.fromLTRB(SkorxSpace.lg, 0, SkorxSpace.lg, 96),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? colors.navy : colors.textMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? colors.lime : colors.surfaceInteractive,
      ),
      trackOutlineColor: WidgetStateProperty.all(colors.border),
    ),
    dividerTheme: DividerThemeData(color: colors.border, thickness: 1, space: 1),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(SkorxRadius.xl)),
      ),
    ),
  );
  if (isOps) return theme;
  return theme.copyWith(
    textTheme: theme.textTheme.apply(bodyColor: sx.ink, displayColor: sx.ink),
    appBarTheme: theme.appBarTheme.copyWith(backgroundColor: sx.canvas, foregroundColor: sx.ink),
    dividerTheme: DividerThemeData(color: sx.line, thickness: 1, space: 1),
    bottomSheetTheme: theme.bottomSheetTheme.copyWith(backgroundColor: sx.surface, dragHandleColor: sx.line),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: sx.primaryFill,
        foregroundColor: sx.onPrimary,
        disabledBackgroundColor: sx.surfaceAlt,
        disabledForegroundColor: sx.inkFaint,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Sx.radius)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? sx.onVolt : sx.inkMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? sx.voltFill : sx.surfaceAlt,
      ),
      trackOutlineColor: WidgetStateProperty.all(sx.line),
    ),
    snackBarTheme: theme.snackBarTheme.copyWith(
      backgroundColor: sx.ink,
      contentTextStyle: TextStyle(color: sx.canvas, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      fillColor: sx.surface,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sx.radius),
        borderSide: BorderSide(color: sx.line),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sx.radius),
        borderSide: BorderSide(color: sx.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sx.radius),
        borderSide: BorderSide(color: sx.ink, width: 1.5),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: sx.ink),
  );
}

/// Tokens that Material's ColorScheme has no slot for.
class SkorxThemeExtension extends ThemeExtension<SkorxThemeExtension> {
  const SkorxThemeExtension({required this.colors, required this.highlight, required this.accent});

  final SkorxColors colors;
  final Color highlight;
  final WorkspaceAccent accent;

  @override
  SkorxThemeExtension copyWith({SkorxColors? colors, Color? highlight, WorkspaceAccent? accent}) =>
      SkorxThemeExtension(
        colors: colors ?? this.colors,
        highlight: highlight ?? this.highlight,
        accent: accent ?? this.accent,
      );

  @override
  SkorxThemeExtension lerp(SkorxThemeExtension? other, double t) {
    if (other == null) return this;
    return SkorxThemeExtension(
      colors: t < 0.5 ? colors : other.colors,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      accent: t < 0.5 ? accent : other.accent,
    );
  }
}

extension SkorxThemeContext on BuildContext {
  SkorxThemeExtension get skorx => Theme.of(this).extension<SkorxThemeExtension>()!;
}
