import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shared/format.dart';
import 'fx.dart';
import 'ball_loader.dart';
import 'tokens.dart';
import 'type.dart';

// ─── The net line ────────────────────────────────────────────────────────

/// The SkorX brand line: a hairline with a short solid centre mark, the way
/// a net splits a pickleball court. Every match is drawn across one.
class NetLine extends StatelessWidget {
  const NetLine({super.key, this.vertical = false, this.color, this.markColor, this.thickness = 1});

  final bool vertical;
  final Color? color;
  final Color? markColor;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return ExcludeSemantics(
      child: CustomPaint(
        size: vertical ? Size(8, double.infinity) : const Size(double.infinity, 8),
        painter: _NetPainter(
          vertical: vertical,
          line: color ?? c.line,
          mark: markColor ?? c.inkMuted,
          thickness: thickness,
        ),
      ),
    );
  }
}

class _NetPainter extends CustomPainter {
  _NetPainter({required this.vertical, required this.line, required this.mark, required this.thickness});

  final bool vertical;
  final Color line;
  final Color mark;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = line
      ..strokeWidth = thickness;
    final m = Paint()
      ..color = mark
      ..strokeWidth = thickness + 2
      ..strokeCap = StrokeCap.round;
    if (vertical) {
      final x = size.width / 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
      final c = size.height / 2;
      canvas.drawLine(Offset(x, c - 6), Offset(x, c + 6), m);
    } else {
      final y = size.height / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      final c = size.width / 2;
      canvas.drawLine(Offset(c - 8, y), Offset(c + 8, y), m);
    }
  }

  @override
  bool shouldRepaint(_NetPainter old) =>
      old.line != line || old.mark != mark || old.vertical != vertical || old.thickness != thickness;
}

// ─── Status language ─────────────────────────────────────────────────────

enum SxState {
  live('LIVE'),
  upcoming('UPCOMING'),
  won('WON'),
  lost('LOST'),
  completed('COMPLETED'),
  cancelled('CANCELLED'),
  registered('REGISTERED');

  const SxState(this.word);
  final String word;
}

Color stateColor(SxColors c, SxState s) => switch (s) {
      SxState.live => c.live,
      SxState.upcoming || SxState.registered => c.info,
      SxState.won => c.volt,
      SxState.lost || SxState.completed => c.inkMuted,
      SxState.cancelled => c.inkFaint,
    };

/// The shape half of a status: still readable in grayscale.
class StateGlyph extends StatelessWidget {
  const StateGlyph(this.state, {super.key, this.size = 8, this.color});

  final SxState state;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? stateColor(context.sx, state);
    if (state == SxState.live) return LivePulse(size: size, color: color);
    return CustomPaint(size: Size.square(size), painter: _GlyphPainter(state, color));
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.state, this.color);

  final SxState state;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final w = s.width;
    switch (state) {
      case SxState.live:
        canvas.drawCircle(Offset(w / 2, w / 2), w / 2, fill);
      case SxState.upcoming:
        canvas.drawCircle(Offset(w / 2, w / 2), w / 2 - 0.75, stroke);
      case SxState.won:
        canvas.drawPath(
            Path()
              ..moveTo(w / 2, 0)
              ..lineTo(w, w)
              ..lineTo(0, w)
              ..close(),
            fill);
      case SxState.lost:
        canvas.drawPath(
            Path()
              ..moveTo(0.75, 0.75)
              ..lineTo(w - 0.75, 0.75)
              ..lineTo(w / 2, w - 0.75)
              ..close(),
            stroke);
      case SxState.completed:
        canvas.drawRect(Rect.fromLTWH(0, 0, w, w), fill);
      case SxState.cancelled:
        canvas.drawLine(Offset(0, w / 2), Offset(w, w / 2), stroke..strokeWidth = 2);
      case SxState.registered:
        canvas.drawPath(
            Path()
              ..moveTo(w / 2, 0)
              ..lineTo(w, w / 2)
              ..lineTo(w / 2, w)
              ..lineTo(0, w / 2)
              ..close(),
            fill);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.state != state || old.color != color;
}

/// Shape + word, no pill: "▲ WON", "● LIVE".
class StateMark extends StatelessWidget {
  const StateMark(this.state, {super.key, this.word, this.size = 12});

  final SxState state;

  /// Overrides the default word, e.g. "STARTS IN 28 MIN".
  final String? word;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = stateColor(context.sx, state);
    final text = word ?? state.word;
    return Semantics(
      label: text.toLowerCase(),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StateGlyph(state, size: size * 0.66, color: color),
          SizedBox(width: size * 0.5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SxType.label(color, size: size).copyWith(
                decoration: state == SxState.cancelled ? TextDecoration.lineThrough : null,
                decorationColor: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The live dot. Pulses unless the system asks for less motion.
class LivePulse extends StatefulWidget {
  const LivePulse({super.key, this.size = 8, this.color});

  final double size;
  final Color? color;

  @override
  State<LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<LivePulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (sxReduceMotion(context)) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.sx.live;
    final s = widget.size;
    return SizedBox.square(
      dimension: s,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(painter: _PulsePainter(_c.value, color)),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    if (t > 0) {
      canvas.drawCircle(c, r * (1 + t * 1.3), Paint()..color = color.withValues(alpha: 0.35 * (1 - t)));
    }
    canvas.drawCircle(c, r, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.t != t || old.color != color;
}

/// A frosted tag on a hero card: "● LIVE · GAME 2".
class SxHeroTag extends StatelessWidget {
  const SxHeroTag({super.key, required this.text, this.icon, this.live = false, this.highlight = false});

  final String text;
  final IconData? icon;
  final bool live;

  /// Volt, for the one thing that is about to happen.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final fg = highlight ? c.onVolt : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: live ? SxColors.dark.heat : null,
        color: live ? null : (highlight ? c.voltFill : Colors.white.withValues(alpha: 0.16)),
        borderRadius: BorderRadius.circular(20),
        boxShadow: live ? c.glowOf(SxColors.dark.live) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[const LivePulse(size: 7, color: Colors.white), const SizedBox(width: 6)],
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 5)],
          Flexible(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.label(fg, size: 12.5)),
          ),
        ],
      ),
    );
  }
}

// ─── Actions ─────────────────────────────────────────────────────────────

enum SxButtonKind { primary, secondary, quiet }

class SxButton extends StatelessWidget {
  const SxButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = SxButtonKind.primary,
    this.icon,
    this.busy = false,
    this.expand = true,
    this.height = 54,
  });

  const SxButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = true,
    this.height = 50,
  }) : kind = SxButtonKind.secondary;

  const SxButton.quiet({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.height = 44,
  })  : kind = SxButtonKind.quiet,
        busy = false;

  final String label;
  final VoidCallback? onPressed;
  final SxButtonKind kind;
  final IconData? icon;
  final bool busy;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final enabled = onPressed != null && !busy;
    final (bg, fg, border) = switch (kind) {
      SxButtonKind.primary => (c.primaryFill, c.onPrimary, null),
      SxButtonKind.secondary => (c.surface.withValues(alpha: c.isDark ? 0.7 : 1), c.ink, c.cardEdge),
      SxButtonKind.quiet => (Colors.transparent, c.ink, null),
    };
    final primary = kind == SxButtonKind.primary;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          BallLoader(color: fg, width: 38, label: '$label, working')
        else ...[
          if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: Sx.s8)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: SxType.sans,
                color: fg,
                fontSize: kind == SxButtonKind.quiet ? 14 : 15,
                fontWeight: primary ? FontWeight.w800 : FontWeight.w700,
                letterSpacing: -0.1,
                decoration: kind == SxButtonKind.quiet ? TextDecoration.underline : null,
                decorationColor: fg.withValues(alpha: 0.4),
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
      child: Opacity(
        opacity: enabled || busy ? 1 : 0.4,
        child: Tappable(
          onTap: enabled ? onPressed : null,
          radius: Sx.radius,
          haptic: primary,
          child: _maybeShine(
            primary && enabled,
            Container(
              height: height - 2,
              padding: EdgeInsets.symmetric(horizontal: kind == SxButtonKind.quiet ? Sx.s8 : Sx.s24),
              decoration: BoxDecoration(
                color: primary ? null : bg,
                gradient: primary ? c.brand : null,
                borderRadius: BorderRadius.circular(Sx.radius),
                border: border == null ? null : Border.all(color: border),
                boxShadow: primary && enabled ? c.glowOf(c.voltFill, strength: 0.9) : null,
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

Widget _maybeShine(bool on, Widget child) => on ? SxShine(child: child) : child;

/// Press feedback without Material ink: a springy squeeze.
class Tappable extends StatefulWidget {
  const Tappable({super.key, required this.child, required this.onTap, this.radius = Sx.radius, this.haptic = false});

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final bool haptic;

  @override
  State<Tappable> createState() => _TappableState();
}

class _TappableState extends State<Tappable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: () {
        if (widget.haptic) HapticFeedback.selectionClick();
        widget.onTap!();
      },
      child: AnimatedOpacity(
        duration: Sx.fast,
        opacity: _down ? 0.85 : 1,
        child: AnimatedScale(
          duration: _down ? const Duration(milliseconds: 110) : const Duration(milliseconds: 420),
          curve: _down ? Curves.easeOut : Curves.elasticOut,
          scale: _down && !sxReduceMotion(context) ? 0.955 : 1,
          child: widget.child,
        ),
      ),
    );
  }
}

/// A round 44×44 icon action, optionally with an unread dot.
class SxIconAction extends StatelessWidget {
  const SxIconAction({super.key, required this.icon, required this.label, required this.onTap, this.dot = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      button: true,
      label: dot ? '$label, unread' : label,
      excludeSemantics: true,
      child: Tappable(
        onTap: onTap,
        radius: 22,
        child: SizedBox.square(
          dimension: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.surface.withValues(alpha: c.isDark ? 0.6 : 0.9),
                  border: Border.all(color: c.cardEdge),
                ),
              ),
              Icon(icon, size: 20, color: c.ink),
              if (dot)
                Positioned(
                  top: 7,
                  right: 7,
                  child: SxPop(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        gradient: c.heat,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.canvas, width: 2),
                        boxShadow: c.glowOf(c.live),
                      ),
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

/// Filter chip: outline when off, ink fill when on.
class SxChip extends StatelessWidget {
  const SxChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final fg = selected ? c.onVolt : c.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Tappable(
        onTap: onTap,
        radius: 20,
        child: AnimatedContainer(
          duration: Sx.medium,
          curve: Curves.easeOutCubic,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? null : c.surface.withValues(alpha: c.isDark ? 0.55 : 0.9),
            gradient: selected ? c.brand : null,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? Colors.transparent : c.cardEdge),
            boxShadow: selected ? c.glowOf(c.voltFill, strength: 0.6) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 6)],
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: SxType.sans, color: fg, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Structure ───────────────────────────────────────────────────────────

/// Centres content at up to [Sx.maxContent] on wide screens.
class SxWidth extends StatelessWidget {
  const SxWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: Sx.maxContent), child: child),
      );
}

/// A tab page's big title, with actions on the right.
class SxTitleBar extends StatelessWidget {
  const SxTitleBar({super.key, required this.title, this.actions = const [], this.leading});

  final String title;
  final List<Widget> actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s12, Sx.s8, Sx.s8),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: Sx.s12)],
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: SxType.title(c.ink, size: 36), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Top bar for detail screens: back, optional small title, actions.
class SxBackBar extends StatelessWidget {
  const SxBackBar({super.key, this.title, this.actions = const [], this.onBack});

  final String? title;
  final List<Widget> actions;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: Sx.s8),
          SxIconAction(
            key: const Key('back'),
            icon: Icons.arrow_back_rounded,
            label: 'Back',
            onTap: onBack ?? () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: Sx.s4),
          Expanded(
            child: title == null
                ? const SizedBox()
                : Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SxType.heading(c.ink, size: 17),
                  ),
          ),
          ...actions,
          const SizedBox(width: Sx.s8),
        ],
      ),
    );
  }
}

/// Section label with an optional link: "RECENT RESULT ·············· ALL".
class SxSection extends StatelessWidget {
  const SxSection(this.title, {super.key, this.action, this.onAction, this.padding});

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Padding(
      padding: padding ?? const EdgeInsets.only(bottom: Sx.s12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            margin: const EdgeInsets.only(right: Sx.s8),
            decoration: BoxDecoration(gradient: c.brand, borderRadius: BorderRadius.circular(2)),
          ),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: SxType.heading(c.ink, size: 18).copyWith(fontWeight: FontWeight.w800)),
            ),
          ),
          if (action != null)
            Semantics(
              button: true,
              label: action,
              excludeSemantics: true,
              child: Tappable(
                onTap: onAction,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Sx.s4),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                    decoration: BoxDecoration(
                      color: c.blue.withValues(alpha: c.isDark ? 0.16 : 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(action!, style: SxType.caption(c.isDark ? c.cyan : c.blue, size: 13)
                            .copyWith(fontWeight: FontWeight.w700)),
                        Icon(Icons.chevron_right_rounded, size: 16, color: c.isDark ? c.cyan : c.blue),
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

/// A raised block. Used only where it groups something tappable.
class SxBlock extends StatelessWidget {
  const SxBlock({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(Sx.s16), this.color, this.semanticLabel});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final box = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        gradient: color == null ? c.card : null,
        borderRadius: BorderRadius.circular(Sx.radiusLg),
        border: Border.all(color: c.cardEdge),
        boxShadow: c.cardShadow,
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Tappable(onTap: onTap, radius: Sx.radiusLg, child: box),
    );
  }
}

/// A plain list row: icon, label, optional value, chevron.
class SxRow extends StatelessWidget {
  const SxRow({
    super.key,
    required this.label,
    this.icon,
    this.value,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.danger = false,
  });

  final String label;
  final IconData? icon;
  final String? value;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final ink = danger ? c.live : c.ink;
    return Semantics(
      button: onTap != null,
      label: [label, ?value, ?subtitle].join(', '),
      excludeSemantics: trailing == null,
      child: Tappable(
        onTap: onTap,
        radius: 0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Sx.s12),
            child: Row(
              children: [
                if (icon != null) ...[
                  SxIconTile(
                    icon: icon!,
                    size: 36,
                    colors: danger ? [c.live, Color.lerp(c.live, Colors.black, 0.25)!] : sxTileColors(c, label.codeUnits.fold(0, (a, b) => a + b)),
                  ),
                  const SizedBox(width: Sx.s12),
                ],
                Expanded(
                  flex: value == null ? 1 : 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: SxType.heading(ink, size: 16).copyWith(fontWeight: FontWeight.w600)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: SxType.caption(c.inkMuted)),
                      ],
                    ],
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: Sx.s16),
                  Expanded(
                    flex: 3,
                    child: Text(value!,
                        textAlign: TextAlign.end,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SxType.body(c.inkMuted, size: 14)),
                  ),
                ],
                if (trailing != null) ...[const SizedBox(width: Sx.s8), trailing!],
                if (onTap != null && trailing == null) ...[
                  const SizedBox(width: Sx.s4),
                  Icon(Icons.chevron_right_rounded, color: c.inkFaint),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rows separated by hairlines.
class SxRows extends StatelessWidget {
  const SxRows({super.key, required this.children, this.title});

  final List<Widget> children;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) SxSection(title!, padding: const EdgeInsets.only(bottom: Sx.s12)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Sx.s16),
          decoration: BoxDecoration(
            gradient: c.card,
            borderRadius: BorderRadius.circular(Sx.radiusLg),
            border: Border.all(color: c.cardEdge),
            boxShadow: c.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: c.line.withValues(alpha: 0.6), indent: 48),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Underline tabs with optional counts: "LIVE 1   UPCOMING 2   RESULTS".
class SxTabs<T> extends StatelessWidget {
  const SxTabs({super.key, required this.tabs, required this.selected, required this.onSelect});

  final List<(T, String, int?)> tabs;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      width: double.infinity,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s4, Sx.gutter, Sx.s8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: c.surface.withValues(alpha: c.isDark ? 0.6 : 0.9),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: c.cardEdge),
          ),
          child: Row(
          children: [
            for (final (value, label, count) in tabs)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Semantics(
                  button: true,
                  selected: value == selected,
                  label: count == null ? label : '$label, $count',
                  excludeSemantics: true,
                  child: GestureDetector(
                    key: Key('tab-$label'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(value),
                    child: _TabLabel(label: label, count: count, selected: value == selected, live: label == 'Live'),
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

class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.label, required this.count, required this.selected, required this.live});

  final String label;
  final int? count;
  final bool selected;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final ink = selected ? c.onVolt : c.inkMuted;
    return AnimatedContainer(
      duration: Sx.medium,
      curve: Curves.easeOutCubic,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        gradient: selected ? c.brand : null,
        borderRadius: BorderRadius.circular(20),
        boxShadow: selected ? c.glowOf(c.voltFill, strength: 0.5) : null,
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[LivePulse(size: 7, color: c.live), const SizedBox(width: 6)],
          Text(label, style: TextStyle(fontFamily: SxType.sans, fontSize: 13, fontWeight: FontWeight.w700, color: ink)),
          if (count != null && count! > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected ? c.onVolt.withValues(alpha: 0.14) : c.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$count', style: SxType.number(13, selected ? c.onVolt : c.ink)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Initials in a circle until photos come from the API.
class SxAvatar extends StatelessWidget {
  const SxAvatar({super.key, required this.name, this.size = 40, this.ring = false});

  final String name;
  final double size;

  /// A volt ring marks the signed-in player.
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final pair = sxTileColors(c, name.codeUnits.fold(0, (a, b) => a + b));
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ring ? 2.5 : 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: ring ? SweepGradient(colors: [c.voltFill, c.cyan, c.blue, c.voltFill]) : null,
        boxShadow: ring ? c.glowOf(c.blue, strength: 0.6) : null,
      ),
      child: Container(
        padding: EdgeInsets.all(ring ? 2 : 0),
        decoration: BoxDecoration(color: c.canvas, shape: BoxShape.circle),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [for (final x in pair) x.withValues(alpha: c.isDark ? 0.55 : 0.3)],
            ),
          ),
          child: Text(
            initials(name),
            style: TextStyle(
              fontFamily: SxType.sans,
              fontSize: size * 0.34,
              fontWeight: FontWeight.w800,
              color: c.isDark ? Colors.white : c.ink,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Empty, loading, error ───────────────────────────────────────────────

/// What a screen shows before there is anything in it: what it is for, and
/// one thing to do.
class EmptyBlock extends StatelessWidget {
  const EmptyBlock({super.key, required this.title, required this.message, this.icon, this.action, this.compact = false});

  final String title;
  final String message;
  final IconData? icon;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? Sx.s24 : Sx.s48),
      child: Column(
        children: [
          if (icon != null) ...[
            SizedBox(
              width: 120,
              height: 96,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  SxIconTile(icon: icon!, size: 72, solid: true, colors: [c.blue, c.cyan]),
                  const Positioned(right: 4, top: -4, child: SxBall(size: 34)),
                ],
              ),
            ),
            const SizedBox(height: Sx.s16),
          ],
          Text(title, textAlign: TextAlign.center, style: SxType.title(c.ink, size: 28)),
          const SizedBox(height: Sx.s8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(message, textAlign: TextAlign.center, style: SxType.body(c.inkMuted)),
          ),
          if (action != null) ...[const SizedBox(height: Sx.s24), action!],
        ],
      ),
    );
  }
}

class ErrorBlock extends StatelessWidget {
  const ErrorBlock({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmptyBlock(
        icon: Icons.wifi_off_rounded,
        title: "Couldn't load",
        message: message,
        compact: true,
        action: SxButton.secondary(label: 'Try again', expand: false, onPressed: onRetry),
      );
}

/// A shimmering placeholder block. Still under reduced motion.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 16, this.width, this.radius = 8});

  final double height;
  final double? width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (sxReduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 + _c.value * 2 - 0.6, -0.3),
              end: Alignment(-1 + _c.value * 2 + 0.6, 0.3),
              colors: [c.surfaceAlt, Color.lerp(c.surfaceAlt, c.blue, 0.2)!, c.surfaceAlt],
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder rows while a list loads.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 4, this.rowHeight = 72});

  final int rows;
  final double rowHeight;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Loading',
        child: Column(
          children: [
            for (var i = 0; i < rows; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: Sx.s12),
                child: Skeleton(height: rowHeight, radius: Sx.radius),
              ),
          ],
        ),
      );
}

// ─── Sheets ──────────────────────────────────────────────────────────────

/// Keeps a sheet's content above the on-screen keyboard: it rises with the
/// keyboard, and its scroll view brings the focused field into view. The
/// content inside sees no keyboard inset, so a sheet that already pads for
/// the keyboard is never lifted twice.
class SxKeyboardSafe extends StatelessWidget {
  const SxKeyboardSafe({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedPadding(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: MediaQuery.removeViewInsets(context: context, removeBottom: true, child: child),
      );
}

Future<T?> showSxSheet<T>(BuildContext context, {required WidgetBuilder builder, bool scrollable = true}) {
  final c = context.sx;
  return showModalBottomSheet<T>(
    context: context,
    // Above the tab bar, which would otherwise cover the sheet's last row.
    useRootNavigator: true,
    isScrollControlled: scrollable,
    useSafeArea: true,
    backgroundColor: c.surface,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: Sx.maxContent),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Sx.radiusLg))),
    builder: (context) => SxKeyboardSafe(child: builder(context)),
  );
}

// ─── Numbers ─────────────────────────────────────────────────────────────

/// "▲ 18" / "▼ 9". Up is volt, down is muted: a loss is not an alarm.
class RatingDelta extends StatelessWidget {
  const RatingDelta(this.delta, {super.key, this.size = 15});

  final int delta;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final up = delta >= 0;
    final color = delta == 0 ? c.inkMuted : (up ? c.volt : c.inkMuted);
    return Semantics(
      label: 'Rating ${delta >= 0 ? 'up' : 'down'} ${delta.abs()}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (delta != 0) ...[
            StateGlyph(up ? SxState.won : SxState.lost, size: size * 0.5, color: color),
            SizedBox(width: size * 0.25),
          ],
          Text(signed(delta), style: SxType.number(size, color, weight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// A number that counts up once when first shown.
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, required this.style});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (sxReduceMotion(context)) return Text('$value', style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: math.max(0, value - 60).toDouble(), end: value.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text('${v.round()}', style: style),
    );
  }
}
