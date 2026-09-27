import 'package:flutter/material.dart';

import '../features/matches/data/journey.dart';
import '../shared/format.dart';
import 'tokens.dart';
import 'type.dart';
import 'widgets.dart';

/// The player's path through a tournament, drawn along the net line: done
/// rounds are filled, the one being played pulses, rounds to come are
/// rings, rounds after a knockout are struck through.
class JourneyRail extends StatelessWidget {
  const JourneyRail({super.key, required this.journey, required this.onOpenMatch, this.now});

  final TournamentJourney journey;
  final ValueChanged<String> onOpenMatch;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final steps = journey.steps;
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _StepRow(
            step: steps[i],
            first: i == 0,
            last: i == steps.length - 1,
            // The line up to a node is solid once the player has reached it.
            reachedBelow: i < steps.length - 1 && _reached(steps[i + 1].state),
            now: now ?? DateTime.now(),
            onTap: steps[i].match == null ? null : () => onOpenMatch(steps[i].match!.id),
          ),
      ],
    );
  }

  static bool _reached(JourneyState s) =>
      s == JourneyState.done || s == JourneyState.won || s == JourneyState.lost || s == JourneyState.live;
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.first,
    required this.last,
    required this.reachedBelow,
    required this.now,
    this.onTap,
  });

  final JourneyStep step;
  final bool first;
  final bool last;
  final bool reachedBelow;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final s = step.state;
    final (word, wordColor) = switch (s) {
      JourneyState.done => ('DONE', c.inkMuted),
      JourneyState.won => ('WON', c.volt),
      JourneyState.lost => ('LOST', c.inkMuted),
      JourneyState.live => ('LIVE', c.live),
      JourneyState.next => ('NEXT', c.info),
      JourneyState.ahead => ('', c.inkFaint),
      JourneyState.out => ('', c.inkFaint),
    };
    final emphasis = s == JourneyState.live || s == JourneyState.next;
    final titleColor = switch (s) {
      JourneyState.ahead || JourneyState.out => c.inkFaint,
      _ => c.ink,
    };
    final when = step.when;
    final whenText = when == null
        ? null
        : (s == JourneyState.next || s == JourneyState.ahead)
            ? '${relativeDay(when, now)} · ${time12(when)}'
            : relativeDay(when, now);

    return Semantics(
      button: onTap != null,
      label: [step.title, if (word.isNotEmpty) word.toLowerCase(), ?step.detail, ?whenText].join(', '),
      excludeSemantics: true,
      child: Tappable(
        onTap: onTap,
        radius: 0,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 28,
                child: CustomPaint(
                  painter: _RailPainter(
                    state: s,
                    first: first,
                    last: last,
                    reachedAbove: s != JourneyState.ahead && s != JourneyState.next && s != JourneyState.out,
                    reachedBelow: reachedBelow,
                    c: c,
                  ),
                  child: s == JourneyState.live
                      ? Align(alignment: const Alignment(0, -0.62), child: LivePulse(size: 12, color: c.live))
                      : null,
                ),
              ),
              const SizedBox(width: Sx.s12),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: Sx.s12, bottom: last ? Sx.s12 : Sx.s24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              step.title.toUpperCase(),
                              style: SxType.title(titleColor, size: emphasis ? 24 : 20).copyWith(
                                decoration: s == JourneyState.out ? TextDecoration.lineThrough : null,
                                decorationColor: c.inkFaint,
                              ),
                            ),
                          ),
                          if (word.isNotEmpty) Text(word, style: SxType.label(wordColor, size: 13)),
                          if (onTap != null) Icon(Icons.chevron_right_rounded, size: 20, color: c.inkFaint),
                        ],
                      ),
                      if (step.detail != null || whenText != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          [?step.detail, ?whenText].join(' · '),
                          style: SxType.caption(s == JourneyState.ahead || s == JourneyState.out ? c.inkFaint : c.inkMuted),
                        ),
                      ],
                    ],
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

class _RailPainter extends CustomPainter {
  _RailPainter({
    required this.state,
    required this.first,
    required this.last,
    required this.reachedAbove,
    required this.reachedBelow,
    required this.c,
  });

  final JourneyState state;
  final bool first;
  final bool last;
  final bool reachedAbove;
  final bool reachedBelow;
  final SxColors c;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    const nodeY = 22.0;
    final solid = Paint()
      ..color = c.ink
      ..strokeWidth = 2;
    final faint = Paint()
      ..color = c.line
      ..strokeWidth = 2;
    if (!first) canvas.drawLine(Offset(x, 0), Offset(x, nodeY - 7), reachedAbove ? solid : faint);
    if (!last) canvas.drawLine(Offset(x, nodeY + 7), Offset(x, size.height), reachedBelow ? solid : faint);

    final center = Offset(x, nodeY);
    switch (state) {
      case JourneyState.done:
        canvas.drawCircle(center, 6, Paint()..color = c.ink);
      case JourneyState.won:
        canvas.drawCircle(center, 8, Paint()..color = c.voltFill);
        final tick = Paint()
          ..color = c.onVolt
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        canvas.drawPath(
          Path()
            ..moveTo(x - 3.5, nodeY)
            ..lineTo(x - 1, nodeY + 2.5)
            ..lineTo(x + 3.5, nodeY - 2.5),
          tick,
        );
      case JourneyState.lost:
        canvas.drawCircle(center, 7, Paint()..color = c.canvas);
        canvas.drawCircle(
            center,
            7,
            Paint()
              ..color = c.inkMuted
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
      case JourneyState.live:
        break; // The pulsing dot is a child widget.
      case JourneyState.next:
        canvas.drawCircle(center, 8, Paint()..color = c.canvas);
        canvas.drawCircle(
            center,
            8,
            Paint()
              ..color = c.info
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5);
      case JourneyState.ahead:
      case JourneyState.out:
        canvas.drawCircle(center, 5, Paint()..color = c.canvas);
        canvas.drawCircle(
            center,
            5,
            Paint()
              ..color = c.line
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.state != state || old.c != c || old.reachedAbove != reachedAbove || old.reachedBelow != reachedBelow;
}

/// The journey in one line of nodes, for cards: ● ● ○ ◌ ◌.
class JourneyStrip extends StatelessWidget {
  const JourneyStrip({super.key, required this.journey});

  final TournamentJourney journey;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final steps = journey.steps;
    return ExcludeSemantics(
      child: SizedBox(
        height: 14,
        child: Row(
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0)
                Expanded(
                  child: Container(
                    height: 2,
                    color: JourneyRail._reached(steps[i].state) ? c.ink : c.line,
                  ),
                ),
              _dot(c, steps[i].state),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dot(SxColors c, JourneyState s) => switch (s) {
        JourneyState.live => LivePulse(size: 10, color: c.live),
        JourneyState.won => _circle(10, c.voltFill, null),
        JourneyState.done => _circle(8, c.ink, null),
        JourneyState.lost => _circle(10, c.canvas, c.inkMuted),
        JourneyState.next => _circle(10, c.canvas, c.info),
        _ => _circle(8, c.canvas, c.line),
      };

  Widget _circle(double size, Color fill, Color? border) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: border == null ? null : Border.all(color: border, width: 2),
        ),
      );
}
