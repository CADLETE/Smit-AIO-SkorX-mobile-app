import 'package:flutter/material.dart';

import '../features/matches/data/match.dart';
import '../shared/format.dart';
import 'tokens.dart';
import 'player_dp.dart';
import 'type.dart';
import 'widgets.dart';

SxState matchState(Match m) => switch (m.status) {
      MatchStatus.live => SxState.live,
      MatchStatus.upcoming => SxState.upcoming,
      MatchStatus.cancelled => SxState.cancelled,
      MatchStatus.completed => m.involvesMe ? (m.won ? SxState.won : SxState.lost) : SxState.completed,
    };

/// "Starts in 28 min" when soon, else null.
String? startsIn(Match m, DateTime now) {
  if (!m.isUpcoming) return null;
  final mins = m.scheduledAt.difference(now).inMinutes;
  if (mins < 0 || mins > 60) return null;
  return mins <= 1 ? 'STARTING NOW' : 'STARTS IN $mins MIN';
}

/// The SkorX match row: verdict or time on the left, both sides across the
/// net in the middle, games in columns on the right. Readable in under a
/// second: the verdict word, the volt edge and the bright winning numbers
/// all say the same thing.
class MatchRow extends StatelessWidget {
  const MatchRow({super.key, required this.match, required this.onTap, this.showContext = true, this.now});

  final Match match;
  final VoidCallback onTap;

  /// Tournament · round · date line. Off inside a tournament hub.
  final bool showContext;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = match;
    final won = m.isCompleted && m.involvesMe && m.won;
    final clock = now ?? DateTime.now();

    final left = switch (m.status) {
      MatchStatus.completed || MatchStatus.cancelled => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Verdict(match: m),
            if (showContext) ...[
              const SizedBox(height: 2),
              Text(_shortDay(m.playedAt, clock), style: SxType.label(context.sx.inkFaint, size: 10.5)),
            ],
          ],
        ),
      MatchStatus.live => const _Verdict.live(),
      MatchStatus.upcoming => _TimeBlock(m.scheduledAt),
    };

    // Round first (the most telling), then where it belongs. The date sits
    // under the verdict, so it is never the part that gets cut off.
    final contextLine = [
      if (m.tournament != null) m.tournament!.round else m.kind.label,
      if (showContext) m.tournament?.name ?? m.venue,
      if (m.isUpcoming) ?m.court,
    ].whereType<String>().toSet().join(' · ');

    return Semantics(
      button: true,
      label: _describe(m),
      excludeSemantics: true,
      child: Tappable(
        onTap: onTap,
        radius: 0,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The edge: volt for a win, red for live, nothing otherwise.
              Container(
                width: 3,
                margin: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: won ? c.brand : (m.isLive ? c.heat : null),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: won ? c.glowOf(c.voltFill, strength: 0.5) : null,
                ),
              ),
              const SizedBox(width: Sx.s12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Sx.s16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(width: 58, child: left),
                          Expanded(child: _Sides(match: m)),
                          const SizedBox(width: Sx.s12),
                          if (m.isCompleted || m.isLive) _GameColumns(match: m),
                          if (m.isUpcoming) Icon(Icons.chevron_right_rounded, color: c.inkFaint),
                        ],
                      ),
                      if (contextLine.isNotEmpty || (m.ratingChange != null && m.involvesMe)) ...[
                        const SizedBox(height: Sx.s8),
                        Padding(
                          padding: const EdgeInsets.only(left: 58),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  m.isCancelled && m.cancelReason != null ? m.cancelReason! : contextLine,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: SxType.caption(c.inkMuted, size: 12.5),
                                ),
                              ),
                              if (m.ratingChange != null && m.involvesMe) ...[
                                const SizedBox(width: Sx.s12),
                                RatingDelta(m.ratingChange!, size: 14),
                              ],
                            ],
                          ),
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

/// "TODAY", "YDAY", "24 SEP".
String _shortDay(DateTime d, DateTime now) => switch (daysBetween(d, now)) {
      0 => 'TODAY',
      1 => 'YDAY',
      _ => '${d.day} ${monthsShort[d.month - 1].toUpperCase()}',
    };

String _describe(Match m) {
  final who = '${sideLabel(m.mine)} versus ${m.opponentKnown ? sideLabel(m.theirs) : m.theirsPlaceholder ?? 'to be decided'}';
  final games = m.games.map((g) => '${g.$1} ${g.$2}').join(', ');
  return switch (m.status) {
    MatchStatus.completed => '${m.involvesMe ? (m.won ? 'Won' : 'Lost') : 'Completed'}, $who, $games. ${m.stageLabel}',
    MatchStatus.live => 'Live, $who, game ${m.live?.number ?? ''}, ${m.live?.mine ?? ''} to ${m.live?.theirs ?? ''}',
    MatchStatus.upcoming => 'Upcoming, ${time12(m.scheduledAt)}, $who, ${m.stageLabel}',
    MatchStatus.cancelled => 'Cancelled, $who',
  };
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.match}) : live = false;
  const _Verdict.live()
      : match = null,
        live = true;

  final Match? match;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    if (live) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [LivePulse(size: 7, color: c.live), const SizedBox(width: 5), Text('LIVE', style: SxType.label(c.live, size: 13))],
        ),
      );
    }
    final m = match!;
    if (m.isCancelled) return Text('—', style: SxType.verdict(22, c.inkFaint));
    if (!m.involvesMe) return Text('FT', style: SxType.label(c.inkMuted, size: 13));
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: m.won ? c.brand : null,
        color: m.won ? null : c.surfaceAlt,
        boxShadow: m.won ? c.glowOf(c.voltFill, strength: 0.6) : null,
      ),
      child: Text(m.won ? 'W' : 'L', style: SxType.verdict(20, m.won ? c.onVolt : c.inkMuted)),
    );
  }
}

class _TimeBlock extends StatelessWidget {
  const _TimeBlock(this.at);

  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final t = time12(at).split(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(t.first, style: SxType.number(20, c.ink, weight: FontWeight.w800)),
        Text(t.last, style: SxType.label(c.inkMuted, size: 11)),
      ],
    );
  }
}

/// Both sides, split by the net.
class _Sides extends StatelessWidget {
  const _Sides({required this.match});

  final Match match;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = match;
    final mineWon = m.isCompleted && m.won;
    final theirsWon = m.isCompleted && !m.won;
    TextStyle side(bool winner, bool me) => TextStyle(
          fontSize: 15,
          height: 1.2,
          fontWeight: winner || (me && !m.isCompleted) ? FontWeight.w700 : FontWeight.w500,
          color: m.isCompleted && !winner ? c.inkMuted : c.ink,
        );
    Widget row(List<String> names, TextStyle style, [String? placeholder]) => Row(
          children: [
            PlayerTap(
              name: names.length == 1 ? names.first : '',
              child: SideDps(names: names, size: 20, edge: c.surface),
            ),
            const SizedBox(width: Sx.s8),
            Flexible(child: SideNames(names: names, style: style, placeholder: placeholder)),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(m.mine, side(mineWon, m.involvesMe)),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 2),
          child: SizedBox(height: 2, width: 56, child: NetLine()),
        ),
        row(m.theirs, side(theirsWon, false), m.theirsPlaceholder),
      ],
    );
  }
}

/// Games as columns: the winning number of each game in ink, the other faint.
class _GameColumns extends StatelessWidget {
  const _GameColumns({required this.match});

  final Match match;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = match;
    final cols = <(int, int, bool)>[
      for (final g in m.games) (g.$1, g.$2, false),
      if (m.live != null) (m.live!.mine, m.live!.theirs, true),
    ];
    Widget n(int v, bool bright, bool live) => SizedBox(
          width: 24,
          child: Text(
            '$v',
            textAlign: TextAlign.right,
            style: SxType.number(18, live ? c.live : (bright ? c.ink : c.inkFaint), weight: bright ? FontWeight.w800 : FontWeight.w600),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (a, b, live) in cols)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Column(
              children: [
                n(a, live || a > b, live),
                const SizedBox(height: 4),
                n(b, live || b > a, live),
              ],
            ),
          ),
      ],
    );
  }
}

/// The match detail scoreboard: both sides across the net, game by game,
/// and the overall result in big numbers.
class Scoreboard extends StatelessWidget {
  const Scoreboard({super.key, required this.match});

  final Match match;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = match;
    final games = [
      for (final g in m.games) (g.$1, g.$2, false),
      if (m.live != null) (m.live!.mine, m.live!.theirs, true),
    ];
    final showOverall = m.isCompleted || m.isLive;

    Widget sideRow(List<String> names, bool mine, String? placeholder) {
      final winner = m.isCompleted && (mine ? m.won : !m.won);
      final nameColor = m.isCompleted && !winner ? c.inkMuted : c.ink;
      return Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (names.isEmpty)
                  Text(placeholder ?? 'To be decided', style: SxType.heading(c.inkMuted).copyWith(fontStyle: FontStyle.italic))
                else
                  for (final n in names)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: PlayerTag(
                        name: n,
                        size: 26,
                        style: SxType.heading(nameColor, size: 17).copyWith(fontWeight: winner ? FontWeight.w700 : FontWeight.w500),
                      ),
                    ),
              ],
            ),
          ),
          for (final (a, b, live) in games)
            SizedBox(
              width: 38,
              child: Text(
                '${mine ? a : b}',
                textAlign: TextAlign.center,
                style: SxType.number(
                  26,
                  live ? c.live : ((mine ? a > b : b > a) ? c.ink : c.inkFaint),
                  weight: FontWeight.w800,
                ),
              ),
            ),
          if (showOverall) ...[
            const SizedBox(width: Sx.s8),
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: winner ? c.voltFill : Colors.transparent,
                borderRadius: BorderRadius.circular(Sx.radiusSm),
                border: winner ? null : Border.all(color: c.line),
              ),
              child: Text(
                '${mine ? m.gamesWon : m.gamesLost}',
                style: SxType.number(26, winner ? c.onVolt : c.inkMuted, weight: FontWeight.w800),
              ),
            ),
          ],
        ],
      );
    }

    return Semantics(
      label: _describe(m),
      excludeSemantics: true,
      child: Column(
        children: [
          if (games.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: Sx.s8),
              child: Row(
                children: [
                  const Spacer(),
                  for (var i = 0; i < games.length; i++)
                    SizedBox(
                      width: 38,
                      child: Text('G${i + 1}',
                          textAlign: TextAlign.center, style: SxType.label(games[i].$3 ? c.live : c.inkFaint, size: 11)),
                    ),
                  if (showOverall) ...[
                    const SizedBox(width: Sx.s8),
                    SizedBox(width: 44, child: Text('GAMES', textAlign: TextAlign.center, style: SxType.label(c.inkFaint, size: 10))),
                  ],
                ],
              ),
            ),
          sideRow(m.mine, true, null),
          const Padding(padding: EdgeInsets.symmetric(vertical: Sx.s12), child: SizedBox(height: 8, child: NetLine())),
          sideRow(m.theirs, false, m.theirsPlaceholder),
        ],
      ),
    );
  }
}

/// The live score, big, across the net: Home's Now card and the Live tab.
class LiveScore extends StatelessWidget {
  const LiveScore({super.key, required this.match});

  final Match match;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final live = match.live!;
    Widget side(List<String> names, int points, bool serving, int games) => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SideDps(names: names, size: 38, edge: Colors.white.withValues(alpha: 0.9)),
            const SizedBox(width: Sx.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: SideNames(names: names, style: SxType.heading(c.ink, size: 18))),
                      if (serving) ...[
                        const SizedBox(width: Sx.s8),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(color: c.voltFill, shape: BoxShape.circle),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('$games ${games == 1 ? 'game' : 'games'}', style: SxType.caption(c.inkMuted)),
                ],
              ),
            ),
            Text('$points', style: SxType.hero(56, c.ink)),
          ],
        );
    return Semantics(
      label: 'Live score, game ${live.number}: ${sideLabel(match.mine)} ${live.mine}, ${sideLabel(match.theirs)} ${live.theirs}',
      excludeSemantics: true,
      child: Column(
        children: [
          side(match.mine, live.mine, live.myServe == true, match.gamesWon),
          const Padding(padding: EdgeInsets.symmetric(vertical: Sx.s8), child: SizedBox(height: 8, child: NetLine())),
          side(match.theirs, live.theirs, live.myServe == false, match.gamesLost),
        ],
      ),
    );
  }
}
