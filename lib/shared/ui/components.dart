import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';
import '../../app/theme/typography.dart';
import '../../design/fx.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../format.dart';

/// Ink on lime: the navy that reads on the primary fill in both themes.
const limeInk = Color(0xFF0B1C33);

/// Whether the system asked for less motion. Every animation in the app
/// checks this and jumps to its end state instead.
bool reduceMotion(BuildContext context) => MediaQuery.of(context).disableAnimations;

/// Squeezes under the finger and springs back, so taps feel physical.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.onTap, this.haptic = false});

  final Widget child;
  final VoidCallback? onTap;
  final bool haptic;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (widget.onTap != null && _down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.lightImpact();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _down && !reduceMotion(context) ? 0.955 : 1,
        duration: _down ? const Duration(milliseconds: 110) : const Duration(milliseconds: 420),
        curve: _down ? Curves.easeOut : Curves.elasticOut,
        child: widget.child,
      ),
    );
  }
}

enum SkxButtonKind { primary, secondary, ghost, danger }

/// The one button family. Primary is lime with a soft glow: one per screen.
class SkxButton extends StatelessWidget {
  const SkxButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = SkxButtonKind.primary,
    this.busy = false,
    this.height = 56,
    this.expand = true,
  });

  const SkxButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.height = 52,
    this.expand = true,
  }) : kind = SkxButtonKind.secondary;

  const SkxButton.ghost({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 48,
    this.expand = false,
  })  : kind = SkxButtonKind.ghost,
        busy = false;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final SkxButtonKind kind;
  final bool busy;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final sx = context.sx;
    final enabled = onPressed != null && !busy;
    final (Color fill, Color ink, Color? border) = switch (kind) {
      SkxButtonKind.primary => (colors.lime, sx.onVolt, null),
      SkxButtonKind.secondary => (sx.surface.withValues(alpha: sx.isDark ? 0.7 : 1), colors.text, sx.cardEdge),
      SkxButtonKind.ghost => (Colors.transparent, colors.cyan, null),
      SkxButtonKind.danger => (colors.live.withValues(alpha: 0.12), colors.live, colors.live.withValues(alpha: 0.4)),
    };
    final primary = kind == SkxButtonKind.primary;

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: ink))
        else ...[
          if (icon != null) ...[Icon(icon, color: ink, size: 19), const SizedBox(width: SkorxSpace.sm)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: SxType.sans,
                color: ink,
                fontWeight: primary ? FontWeight.w800 : FontWeight.w700,
                fontSize: primary ? 15.5 : 14.5,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: enabled ? onPressed : null,
        haptic: primary,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled || busy ? 1 : 0.45,
          child: _shine(
            primary && enabled,
            Container(
              height: height - 2,
              padding: const EdgeInsets.symmetric(horizontal: SkorxSpace.lg),
              decoration: BoxDecoration(
                color: primary ? null : fill,
                gradient: primary ? sx.brand : null,
                borderRadius: BorderRadius.circular(Sx.radius),
                border: border == null ? null : Border.all(color: border),
                boxShadow: primary && enabled ? sx.glowOf(sx.voltFill, strength: 0.9) : null,
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

Widget _shine(bool on, Widget child) => on ? SxShine(child: child) : child;

/// Surface card with the standard radius and hairline border. Tappable when
/// [onTap] is set.
class SkxCard extends StatelessWidget {
  const SkxCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(SkorxSpace.lg),
    this.color,
    this.borderColor,
    this.gradient,
    this.radius = SkorxRadius.lg,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final Gradient? gradient;
  final double radius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final sx = context.sx;
    final plain = gradient == null && color == null;
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: plain ? sx.card : gradient,
        borderRadius: BorderRadius.circular(radius + 4),
        border: Border.all(color: borderColor ?? sx.cardEdge),
        boxShadow: sx.cardShadow,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Pressable(onTap: onTap, child: card),
    );
  }
}

enum SkxTone { live, success, warning, info, brand, neutral }

Color toneColor(BuildContext context, SkxTone tone) {
  final colors = context.skorx.colors;
  return switch (tone) {
    SkxTone.live => colors.live,
    SkxTone.success => colors.success,
    SkxTone.warning => colors.warning,
    SkxTone.info => colors.cyan,
    SkxTone.brand => colors.limeText,
    SkxTone.neutral => colors.textMuted,
  };
}

/// Small status label: always a word (and optionally an icon), never colour alone.
class SkxPill extends StatelessWidget {
  const SkxPill(this.label, {super.key, this.tone = SkxTone.neutral, this.icon, this.solid = false});

  final String label;
  final SkxTone tone;
  final IconData? icon;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(context, tone);
    final ink = solid ? (tone == SkxTone.brand ? limeInk : Colors.white) : color;
    final fill = solid ? (tone == SkxTone.brand ? context.skorx.colors.lime : color) : color.withValues(alpha: 0.14);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SkorxSpace.sm + 2, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(20),
        border: solid ? null : Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: ink), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SkorxType.label(color: ink, size: 12).copyWith(letterSpacing: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// ▲ +32 / ▼ −12, tinted. Reads as text for screen readers.
class DeltaBadge extends StatelessWidget {
  const DeltaBadge(this.delta, {super.key, this.suffix, this.size = 13, this.filled = true});

  final int delta;
  final String? suffix;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final color = delta > 0 ? colors.success : delta < 0 ? colors.live : colors.textMuted;
    final text = Text.rich(
      TextSpan(children: [
        if (delta != 0)
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(
              delta > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: size + 1,
              color: color,
            ),
          ),
        TextSpan(text: signed(delta), style: SkorxType.score(size + 2, color: color)),
        if (suffix != null)
          TextSpan(text: '  $suffix', style: TextStyle(fontSize: size - 1, color: colors.textMuted)),
      ]),
    );
    return Semantics(
      label: '${delta >= 0 ? 'up' : 'down'} ${delta.abs()}${suffix == null ? '' : ' $suffix'}',
      excludeSemantics: true,
      child: filled && suffix == null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: SkorxSpace.sm, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(SkorxRadius.sm),
              ),
              child: text,
            )
          : text,
    );
  }
}

/// Big number over a tracked caps label.
class StatBlock extends StatelessWidget {
  const StatBlock({
    super.key,
    required this.value,
    required this.label,
    this.color,
    this.labelColor,
    this.size = 30,
    this.align = CrossAxisAlignment.start,
  });

  final String value;
  final String label;
  final Color? color;
  final Color? labelColor;
  final double size;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: align,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: SkorxType.score(size, color: color ?? colors.text)),
          ),
          const SizedBox(height: 3),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SkorxType.label(color: labelColor ?? colors.textMuted, size: 11),
          ),
        ],
      ),
    );
  }
}

/// Italic display title for a section, with an optional action on the right.
class SkxSectionTitle extends StatelessWidget {
  const SkxSectionTitle(this.title, {super.key, this.action, this.onAction, this.trailing, this.padding});

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    return Padding(
      padding: padding ?? const EdgeInsets.only(top: SkorxSpace.xl, bottom: SkorxSpace.md),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            margin: const EdgeInsets.only(right: SkorxSpace.sm),
            decoration: BoxDecoration(gradient: context.sx.brand, borderRadius: BorderRadius.circular(2)),
          ),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title,
                  style: TextStyle(fontFamily: SxType.sans, fontSize: 16.5, fontWeight: FontWeight.w800, color: colors.text)),
            ),
          ),
          ?trailing,
          if (action != null)
            Semantics(
              button: true,
              label: '$action, $title',
              excludeSemantics: true,
              child: InkWell(
                onTap: onAction,
                borderRadius: BorderRadius.circular(SkorxRadius.sm),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: SkorxSpace.sm),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(action!,
                            style: TextStyle(
                                fontFamily: SxType.sans, fontSize: 13, fontWeight: FontWeight.w700, color: colors.cyan)),
                        Icon(Icons.chevron_right_rounded, size: 16, color: colors.cyan),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Big italic screen title used by every tab, with room for actions.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.eyebrow, this.actions = const []});

  final String title;
  final String? eyebrow;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: SkorxSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(eyebrow!.toUpperCase(), style: SkorxType.label(color: colors.textMuted, size: 12)),
                  const SizedBox(height: 4),
                ],
                Semantics(
                  header: true,
                  child: Text(title, style: SkorxType.headline(38, color: colors.text)),
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Round icon button with a 48 px target, for headers.
class SkxIconButton extends StatelessWidget {
  const SkxIconButton({super.key, required this.icon, required this.label, required this.onTap, this.badge = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Shows a small dot, e.g. unread notifications.
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: context.sx.surface.withValues(alpha: context.sx.isDark ? 0.6 : 0.9),
            shape: BoxShape.circle,
            border: Border.all(color: context.sx.cardEdge),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 22, color: colors.text),
              if (badge)
                Positioned(
                  top: 11,
                  right: 12,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      gradient: context.sx.heat,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.surface, width: 1.5),
                      boxShadow: context.sx.glowOf(colors.live),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Filter chip, 40 px tall with a 48 px touch target.
class SkxChip extends StatelessWidget {
  const SkxChip({super.key, required this.label, required this.selected, required this.onTap, this.icon, this.count});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final sx = context.sx;
    final ink = selected ? sx.onVolt : colors.text;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: SkorxSpace.md + 2),
            decoration: BoxDecoration(
              color: selected ? null : sx.surface.withValues(alpha: sx.isDark ? 0.55 : 0.9),
              gradient: selected ? sx.brand : null,
              borderRadius: BorderRadius.circular(SkorxRadius.xl),
              border: Border.all(color: selected ? Colors.transparent : sx.cardEdge),
              boxShadow: selected ? sx.glowOf(sx.voltFill, strength: 0.6) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 16, color: ink), const SizedBox(width: 6)],
                Text(label, style: TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 13)),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Text('$count', style: TextStyle(color: ink.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A horizontal, edge-to-edge row of chips that scrolls.
class SkxChipBar extends StatelessWidget {
  const SkxChipBar({super.key, required this.children, this.gutter = SkorxSpace.lg});

  final List<Widget> children;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: gutter),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: SkorxSpace.sm),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }
}

/// Section switcher: a pill track with the selected segment raised.
class SkxSegmented<T> extends StatelessWidget {
  const SkxSegmented({super.key, required this.segments, required this.selected, required this.onChanged});

  final List<(T, String)> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final sx = context.sx;
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: sx.surface.withValues(alpha: sx.isDark ? 0.6 : 0.9),
        borderRadius: BorderRadius.circular(SkorxRadius.xl),
        border: Border.all(color: sx.cardEdge),
      ),
      child: Row(
        children: [
          for (final (value, label) in segments)
            Expanded(
              child: Semantics(
                button: true,
                selected: value == selected,
                label: label,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (value != selected) {
                      HapticFeedback.selectionClick();
                      onChanged(value);
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: value == selected ? sx.brand : null,
                      borderRadius: BorderRadius.circular(SkorxRadius.xl),
                      boxShadow: value == selected ? sx.glowOf(sx.voltFill, strength: 0.5) : null,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: value == selected ? FontWeight.w800 : FontWeight.w600,
                        color: value == selected ? sx.onVolt : colors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SkxSearchField extends StatefulWidget {
  const SkxSearchField({super.key, required this.hint, required this.onChanged, this.initial = ''});

  final String hint;
  final ValueChanged<String> onChanged;
  final String initial;

  @override
  State<SkxSearchField> createState() => _SkxSearchFieldState();
}

class _SkxSearchFieldState extends State<SkxSearchField> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      onChanged: (v) {
        setState(() {});
        widget.onChanged(v);
      },
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: TextStyle(color: colors.textMuted),
        prefixIcon: Icon(Icons.search_rounded, color: colors.textMuted),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _controller.clear();
                  setState(() {});
                  widget.onChanged('');
                },
              ),
        fillColor: context.sx.surface.withValues(alpha: context.sx.isDark ? 0.7 : 1),
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SkorxRadius.xl),
          borderSide: BorderSide(color: context.sx.cardEdge),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SkorxRadius.xl),
          borderSide: BorderSide(color: context.sx.cardEdge),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SkorxRadius.xl),
          borderSide: BorderSide(color: context.sx.blue, width: 1.5),
        ),
      ),
    );
  }
}

/// Initials in a circle, with an optional brand ring. Photos arrive with the
/// profile photo API.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({super.key, required this.name, this.size = 48, this.ring = false, this.highlight = false});

  final String name;
  final double size;
  final bool ring;

  /// Tints the fill, e.g. the signed-in player in a leaderboard.
  final bool highlight;

  static const ringGradient =
      SweepGradient(colors: [Color(0xFF4DD8F0), Color(0xFFC7EA3A), Color(0xFF3BA0F0), Color(0xFF4DD8F0)]);

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final avatar = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: highlight ? colors.lime.withValues(alpha: 0.18) : null,
        gradient: highlight
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  for (final x in sxTileColors(context.sx, name.codeUnits.fold(0, (a, b) => a + b)))
                    x.withValues(alpha: context.sx.isDark ? 0.5 : 0.28),
                ],
              ),
      ),
      child: Text(
        initials(name),
        style: TextStyle(
          fontFamily: SxType.sans,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w800,
          color: highlight ? colors.limeText : colors.text,
        ),
      ),
    );
    if (!ring) return avatar;
    return Container(
      padding: EdgeInsets.all(size * 0.05 + 1),
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: ringGradient),
      child: Container(
        padding: EdgeInsets.all(size * 0.03),
        decoration: BoxDecoration(shape: BoxShape.circle, color: colors.background),
        child: avatar,
      ),
    );
  }
}

/// Grey placeholder block. Shimmers unless the system asks for less motion.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 16, this.radius = SkorxRadius.sm});

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _shimmer.stop();
    } else if (!_shimmer.isAnimating) {
      _shimmer.repeat();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _shimmer,
        builder: (_, _) {
          final t = _shimmer.value;
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: LinearGradient(
                begin: Alignment(-1.5 + 3 * t, 0),
                end: Alignment(-0.5 + 3 * t, 0),
                colors: [
                  colors.surfaceMuted,
                  Color.lerp(colors.surfaceInteractive, context.sx.blue, 0.2)!,
                  colors.surfaceMuted,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A card-shaped skeleton, for lists that are loading.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.height = 120, this.lines = 3});

  final double height;
  final int lines;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: SkxCard(
        child: SizedBox(
          height: height - 2 * SkorxSpace.lg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Skeleton(width: 90, height: 12),
              for (var i = 0; i < lines - 1; i++) Skeleton(width: i.isEven ? 220 : 160, height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Something failed. Says it plainly, offers the one thing to do.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry, this.compact = false});

  final String message;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    return Semantics(
      liveRegion: true,
      child: SkxCard(
        padding: EdgeInsets.all(compact ? SkorxSpace.lg : SkorxSpace.xl),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: colors.live.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(Icons.wifi_tethering_error_rounded, color: colors.live, size: 22),
            ),
            const SizedBox(width: SkorxSpace.md),
            Expanded(child: Text(message, style: TextStyle(color: colors.text, height: 1.35))),
            const SizedBox(width: SkorxSpace.sm),
            SkxButton.ghost(label: 'Retry', icon: Icons.refresh_rounded, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

/// A friendly, designed empty state: what goes here and what to do next.
class SkxEmpty extends StatelessWidget {
  const SkxEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    return SkxCard(
      padding: EdgeInsets.all(compact ? SkorxSpace.lg : SkorxSpace.xl),
      child: Column(
        children: [
          SizedBox(
            width: compact ? 72 : 96,
            height: compact ? 56 : 76,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                SxIconTile(icon: icon, size: compact ? 48 : 60, solid: true, colors: [context.sx.blue, context.sx.cyan]),
                Positioned(right: 0, top: -2, child: SxBall(size: compact ? 20 : 28)),
              ],
            ),
          ),
          const SizedBox(height: SkorxSpace.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: -0.2),
          ),
          if (message != null) ...[
            const SizedBox(height: SkorxSpace.xs),
            Text(message!, textAlign: TextAlign.center, style: TextStyle(color: colors.textMuted, height: 1.35)),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: SkorxSpace.lg),
            SkxButton.secondary(label: actionLabel!, onPressed: onAction, expand: false, height: 48),
          ],
        ],
      ),
    );
  }
}

/// Renders an [AsyncValue] with the standard loading and error treatment.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.value,
    required this.data,
    required this.onRetry,
    this.loading,
    this.errorMessage = "We couldn't load this. Check your connection and try again.",
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback onRetry;
  final Widget? loading;
  final String errorMessage;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: data,
      loading: () => loading ?? const SkeletonCard(),
      error: (_, _) => ErrorState(message: errorMessage, onRetry: onRetry),
    );
  }
}

/// Icon + caps label + value, for fact grids (date, venue, fee…).
class InfoTile extends StatelessWidget {
  const InfoTile({super.key, required this.icon, required this.label, required this.value, this.valueColor});

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SxIconTile(icon: icon, size: 36, colors: sxTileColors(context.sx, label.length)),
          const SizedBox(width: SkorxSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: SkorxType.label(color: colors.textMuted, size: 10.5)),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: valueColor ?? colors.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A group of list rows in one card, e.g. a settings section.
class SkxGroup extends StatelessWidget {
  const SkxGroup({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: SkorxSpace.xs, top: SkorxSpace.xl, bottom: SkorxSpace.sm),
            child: Semantics(
              header: true,
              child: Text(title!.toUpperCase(), style: SkorxType.label(color: colors.textMuted, size: 12)),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            gradient: context.sx.card,
            borderRadius: BorderRadius.circular(SkorxRadius.lg + 4),
            border: Border.all(color: context.sx.cardEdge),
            boxShadow: context.sx.cardShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, child) in children.indexed) ...[
                if (i > 0) Divider(indent: 64, color: colors.border.withValues(alpha: 0.6)),
                child,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One row in a [SkxGroup].
class SkxRow extends StatelessWidget {
  const SkxRow({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.labelColor,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? labelColor;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SkorxSpace.lg, vertical: SkorxSpace.md),
          child: Row(
            children: [
              SxIconTile(
                icon: icon,
                size: 36,
                colors: iconColor != null
                    ? [iconColor!, Color.lerp(iconColor!, Colors.black, 0.2)!]
                    : sxTileColors(context.sx, label.codeUnits.fold(0, (a, b) => a + b)),
              ),
              const SizedBox(width: SkorxSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: labelColor ?? colors.text),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!, style: TextStyle(color: colors.textMuted, fontSize: 12.5)),
                      ),
                  ],
                ),
              ),
              ?trailing,
              if (trailing == null && showChevron && onTap != null)
                Icon(Icons.chevron_right_rounded, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sticky bottom area for a screen's primary action, above the safe area.
class BottomCtaBar extends StatelessWidget {
  const BottomCtaBar({super.key, required this.child, this.leading});

  final Widget child;

  /// e.g. the price, to the left of the button.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.sx.surface.withValues(alpha: 0.94),
        border: Border(top: BorderSide(color: context.sx.cardEdge)),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: context.sx.isDark ? 0.4 : 0.08), blurRadius: 24)],
      ),
      padding: EdgeInsets.fromLTRB(
        SkorxSpace.lg,
        SkorxSpace.md,
        SkorxSpace.lg,
        SkorxSpace.md + MediaQuery.paddingOf(context).bottom,
      ),
      child: leading == null
          ? child
          : Row(
              children: [
                leading!,
                const SizedBox(width: SkorxSpace.lg),
                Expanded(child: child),
              ],
            ),
    );
  }
}

/// Back that also works on a screen opened directly (restored or deep link),
/// where there is nothing to pop: it goes to [fallback] instead.
class SkxBackButton extends StatelessWidget {
  const SkxBackButton({super.key, required this.fallback, this.onDark = false});

  final String fallback;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    return Semantics(
      button: true,
      label: 'Back',
      excludeSemantics: true,
      child: Pressable(
        onTap: () => context.canPop() ? context.pop() : context.go(fallback),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: onDark ? Colors.black.withValues(alpha: 0.35) : context.sx.surface.withValues(alpha: 0.7),
            border: Border.all(color: onDark ? Colors.white.withValues(alpha: 0.15) : context.sx.cardEdge),
          ),
          child: Icon(Icons.arrow_back_rounded, color: onDark ? Colors.white : colors.text, size: 22),
        ),
      ),
    );
  }
}

/// A plain full-screen page with a back button and an italic title.
class DetailScaffold extends StatelessWidget {
  const DetailScaffold({
    super.key,
    required this.title,
    required this.fallback,
    required this.body,
    this.actions = const [],
    this.bottom,
  });

  final String title;
  final String fallback;
  final Widget body;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        automaticallyImplyLeading: false,
        titleSpacing: SkorxSpace.lg,
        title: Row(
          children: [
            SkxBackButton(fallback: fallback),
            const SizedBox(width: SkorxSpace.md),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SkorxType.headline(27, color: colors.text, weight: FontWeight.w800),
              ),
            ),
          ],
        ),
        actions: [...actions, const SizedBox(width: SkorxSpace.sm)],
      ),
      body: body,
      bottomNavigationBar: bottom,
    );
  }
}

/// A short confirmation at the bottom of the screen.
void showSkxToast(BuildContext context, String message, {IconData icon = Icons.check_circle_rounded}) {
  final colors = context.skorx.colors;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 2400),
        content: Row(
          children: [
            Icon(icon, color: colors.success, size: 20),
            const SizedBox(width: SkorxSpace.md),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

/// A check that draws itself in a lime disc, for confirmations.
class SuccessMark extends StatelessWidget {
  const SuccessMark({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final still = reduceMotion(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: still ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutBack,
      builder: (_, t, _) => Transform.scale(
        scale: 0.6 + 0.4 * t.clamp(0, 1.2),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: context.sx.brand,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: colors.lime.withValues(alpha: 0.5 * t.clamp(0, 1)), blurRadius: 40)],
          ),
          child: CustomPaint(painter: _CheckPainter(progress: t.clamp(0, 1).toDouble(), color: limeInk)),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.28, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.67)
      ..lineTo(size.width * 0.73, size.height * 0.37);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * progress),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.08
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress || old.color != color;
}

/// Counts up to [value] the first time it is shown.
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, required this.style, this.duration = const Duration(milliseconds: 900)});

  final int value;
  final TextStyle style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return Text('$value', style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: value * 0.85, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text('${v.round()}', style: style),
    );
  }
}
