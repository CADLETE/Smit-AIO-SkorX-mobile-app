import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../../tournaments/ui/tournament_banner.dart';
import '../data/match.dart';
import '../data/match_feed.dart';

/// "Today 7:30 PM", "Sat 27 Sep 9:00 AM".
String _when(DateTime d, DateTime now) {
  final day = daysBetween(now, d);
  final label = switch (day) {
    0 => 'Today',
    1 => 'Tomorrow',
    -1 => 'Yesterday',
    _ => '${weekdaysShort[d.weekday - 1]} ${d.day} ${monthsShort[d.month - 1]}',
  };
  return '$label ${time12(d)}';
}

/// A match anywhere on SkorX, told neutrally: both sides, the score, where,
/// and what it belongs to. The card opens the match; a name opens the
/// player; the tournament tag opens the tournament.
class MatchCard extends StatelessWidget {
  const MatchCard({super.key, required this.match, this.now});

  final Match match;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = match;
    final clock = now ?? DateTime.now();
    final aWon = m.isCompleted && m.won;
    final bWon = m.isCompleted && !m.won;

    final status = switch (m.status) {
      MatchStatus.live => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LivePulse(size: 7, color: c.live),
            const SizedBox(width: 6),
            Flexible(
              child: Text('LIVE${m.live == null ? '' : ' · GAME ${m.live!.number}'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.label(c.live, size: 12.5)),
            ),
          ],
        ),
      MatchStatus.upcoming => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StateGlyph(SxState.upcoming, size: 8, color: c.info),
            const SizedBox(width: 6),
            Flexible(
              child: Text(_when(m.scheduledAt, clock).toUpperCase(),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.label(c.info, size: 12)),
            ),
          ],
        ),
      _ => Text('FINAL · ${_when(m.playedAt, clock).split(' ').take(m.playedAt.day == clock.day ? 1 : 3).join(' ').toUpperCase()}',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.label(c.inkMuted, size: 12)),
    };

    final place = [?m.place?.city, ?m.venue].join(' · ');
    final detail = [
      if (m.tournament != null) m.tournament!.round else m.format.label,
      if (m.tournament != null) m.format.label,
      if (!m.isCompleted) ?m.court,
    ].join(' · ');

    return Semantics(
      button: true,
      label: _describe(m, clock),
      child: Tappable(
        key: Key('match-${m.id}'),
        onTap: () => context.push('/player/matches/${m.id}'),
        radius: Sx.radius + 2,
        child: Container(
          padding: const EdgeInsets.fromLTRB(Sx.s16, Sx.s12, Sx.s12, Sx.s12),
          decoration: BoxDecoration(
            gradient: c.card,
            borderRadius: BorderRadius.circular(Sx.radius + 2),
            border: Border.all(color: m.isLive ? c.live.withValues(alpha: 0.45) : c.cardEdge),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(flex: 2, child: status),
                  const SizedBox(width: Sx.s8),
                  Expanded(flex: 3, child: ContextTag(match: m)),
                ],
              ),
              const SizedBox(height: Sx.s12),
              _SideLine(
                names: m.mine,
                games: [for (final g in m.games) g.$1],
                opponent: [for (final g in m.games) g.$2],
                live: m.live?.mine,
                winner: aWon,
                dimmed: bWon,
              ),
              const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: SizedBox(height: 6, child: NetLine())),
              _SideLine(
                names: m.theirs,
                games: [for (final g in m.games) g.$2],
                live: m.live?.theirs,
                winner: bWon,
                dimmed: aWon,
                placeholder: m.theirsPlaceholder,
                opponent: [for (final g in m.games) g.$1],
              ),
              const SizedBox(height: Sx.s12),
              Row(
                children: [
                  Icon(Icons.place_outlined, size: 14, color: c.inkFaint),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      [place, detail].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SxType.caption(c.inkMuted, size: 12.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _describe(Match m, DateTime now) {
    final who = '${sideLabel(m.mine)} versus ${m.opponentKnown ? sideLabel(m.theirs) : m.theirsPlaceholder ?? 'to be decided'}';
    final games = m.games.map((g) => '${g.$1} ${g.$2}').join(', ');
    final where = [?m.venue, ?m.place?.city].join(', ');
    return switch (m.status) {
      MatchStatus.live => 'Live, $who, ${m.live?.mine ?? ''} to ${m.live?.theirs ?? ''}. $where',
      MatchStatus.upcoming => 'Upcoming, ${_when(m.scheduledAt, now)}, $who. $where',
      _ => 'Final, $who, $games. $where',
    };
  }
}

/// The tournament a match belongs to (tap to open it), or CASUAL.
class ContextTag extends StatelessWidget {
  const ContextTag({super.key, required this.match});

  final Match match;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final t = match.tournament;
    if (t == null) {
      return Align(alignment: Alignment.centerRight, child: Text('CASUAL', style: SxType.label(c.inkFaint, size: 11.5)));
    }
    final ink = c.isDark ? c.cyan : c.blue;
    return Align(
      alignment: Alignment.centerRight,
      child: Semantics(
        button: true,
        label: 'Open ${t.name}',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.push('/player/tournament/${t.id}?view=matches'),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 3, 4, 3),
            decoration: BoxDecoration(color: c.blue.withValues(alpha: c.isDark ? 0.16 : 0.08), borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.emoji_events_outlined, size: 13, color: ink),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: SxType.caption(ink, size: 12).copyWith(fontWeight: FontWeight.w700)),
                ),
                Icon(Icons.chevron_right_rounded, size: 14, color: ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SideLine extends StatelessWidget {
  const _SideLine({
    required this.names,
    required this.games,
    required this.live,
    required this.winner,
    required this.dimmed,
    required this.opponent,
    this.placeholder,
  });

  final List<String> names;
  final List<int> games;
  final int? live;
  final bool winner;
  final bool dimmed;
  final String? placeholder;

  /// The other side's games, to tell which of ours were won.
  final List<int> opponent;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final style = SxType.heading(dimmed ? c.inkMuted : c.ink, size: 16).copyWith(fontWeight: winner ? FontWeight.w800 : FontWeight.w600);
    return Row(
      children: [
        PlayerTap(name: names.length == 1 ? names.first : '', child: SideDps(names: names, size: 24, edge: c.surface)),
        const SizedBox(width: Sx.s8),
        Flexible(child: SideNames(names: names, style: style, placeholder: placeholder)),
        if (winner) ...[
          const SizedBox(width: 6),
          StateGlyph(SxState.won, size: 7, color: c.volt),
        ],
        const Spacer(),
        for (final (i, g) in games.indexed)
          SizedBox(
            width: 26,
            child: Text(
              '$g',
              textAlign: TextAlign.right,
              style: SxType.number(19, _bright(i, g) ? c.ink : c.inkFaint, weight: _bright(i, g) ? FontWeight.w800 : FontWeight.w600),
            ),
          ),
        if (live != null)
          Container(
            margin: const EdgeInsets.only(left: 8),
            width: 34,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(color: c.live.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Text('$live', style: SxType.number(20, c.live, weight: FontWeight.w800)),
          ),
      ],
    );
  }

  /// A game this side won is drawn bright.
  bool _bright(int i, int g) => i < opponent.length && g > opponent[i];
}

/// A live match in the Live now strip: the score first.
class LiveMatchCard extends StatelessWidget {
  const LiveMatchCard({super.key, required this.match, this.width = 272});

  final Match match;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = match;
    Widget side(List<String> names, int points, bool serving) => Row(
          children: [
            SideDps(names: names, size: 22, edge: c.surface),
            const SizedBox(width: Sx.s8),
            Expanded(child: SideNames(names: names, style: SxType.heading(c.ink, size: 15))),
            if (serving) Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(color: c.voltFill, shape: BoxShape.circle)),
            Text('$points', style: SxType.number(28, c.ink, weight: FontWeight.w800)),
          ],
        );
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        label: 'Live, ${sideLabel(m.mine)} ${m.live?.mine} versus ${sideLabel(m.theirs)} ${m.live?.theirs}, ${m.contextLabel}',
        child: Tappable(
          key: Key('live-${m.id}'),
          onTap: () => context.push('/player/matches/${m.id}'),
          radius: Sx.radius + 2,
          child: Container(
            padding: const EdgeInsets.all(Sx.s12),
            decoration: BoxDecoration(
              gradient: c.card,
              borderRadius: BorderRadius.circular(Sx.radius + 2),
              border: Border.all(color: c.live.withValues(alpha: 0.5)),
              boxShadow: c.glowOf(c.live, strength: 0.35),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    LivePulse(size: 7, color: c.live),
                    const SizedBox(width: 6),
                    Text('LIVE · G${m.live?.number ?? 1}', style: SxType.label(c.live, size: 12)),
                    const Spacer(),
                    Flexible(
                      child: Text([?m.place?.city, ?m.court].join(' · '),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted, size: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: Sx.s12),
                side(m.mine, m.live?.mine ?? 0, m.live?.myServe == true),
                const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: SizedBox(height: 6, child: NetLine())),
                side(m.theirs, m.live?.theirs ?? 0, m.live?.myServe == false),
                const Spacer(),
                Text(
                  m.tournament == null ? 'Casual · ${m.venue ?? ''}' : '${m.tournament!.name} · ${m.tournament!.round}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SxType.caption(c.inkMuted, size: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A tournament with matches: its banner and how many are live, coming up
/// and done. Opens the tournament's matches.
class TournamentActivityCard extends StatelessWidget {
  const TournamentActivityCard({super.key, required this.activity, this.width});

  final TournamentActivity activity;

  /// Fixed width in a strip; null to fill the row.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final t = activity;
    Widget count(String label, int n, Color color, {bool live = false}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (live && n > 0) ...[LivePulse(size: 6, color: c.live), const SizedBox(width: 4)],
                  Text('$n', style: SxType.number(22, n == 0 ? c.inkFaint : color, weight: FontWeight.w800)),
                ],
              ),
              Text(label, maxLines: 1, style: SxType.label(c.inkMuted, size: 10.5)),
            ],
          ),
        );
    final card = Semantics(
      button: true,
      label: '${t.name}, ${t.place.city}: ${t.live} live, ${t.upcoming} upcoming, ${t.completed} completed',
      excludeSemantics: true,
      child: Tappable(
        key: Key('activity-${t.id}'),
        onTap: () => context.push('/player/tournament/${t.id}?view=matches'),
        radius: Sx.radius + 2,
        child: Container(
          decoration: BoxDecoration(
            gradient: c.card,
            borderRadius: BorderRadius.circular(Sx.radius + 2),
            border: Border.all(color: c.cardEdge),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TournamentBanner(
                id: t.id,
                name: t.name,
                height: 84,
                radius: Sx.radius + 1,
                child: t.live > 0 ? const Positioned(left: Sx.s12, top: Sx.s12, child: BannerTag(text: 'LIVE', live: true)) : null,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Sx.s12, Sx.s12, Sx.s12, Sx.s12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 16)),
                    const SizedBox(height: 2),
                    Text('${t.place.label} · ${dateRange(t.start, t.end)}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted, size: 12)),
                    const SizedBox(height: Sx.s12),
                    Row(
                      children: [
                        count('LIVE', t.live, c.live, live: true),
                        count('UPCOMING', t.upcoming, c.info),
                        count('DONE', t.completed, c.ink),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return width == null ? card : SizedBox(width: width, child: card);
  }
}

/// The foot of a paged list: skeleton rows that ask for the next page as
/// soon as they are built, which is when the list scrolls near its end.
/// Give it a key that changes per page (the item count).
class LoadMoreTrigger extends StatefulWidget {
  const LoadMoreTrigger({super.key, required this.onLoad, this.rows = 2, this.rowHeight = 72});

  final VoidCallback onLoad;
  final int rows;
  final double rowHeight;

  @override
  State<LoadMoreTrigger> createState() => _LoadMoreTriggerState();
}

class _LoadMoreTriggerState extends State<LoadMoreTrigger> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onLoad();
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Sx.s8),
        child: SkeletonList(rows: widget.rows, rowHeight: widget.rowHeight),
      );
}

/// Placeholder while match cards load.
class MatchCardSkeleton extends StatelessWidget {
  const MatchCardSkeleton({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Loading matches',
        child: Column(
          children: [
            for (var i = 0; i < count; i++)
              Container(
                margin: const EdgeInsets.only(bottom: Sx.s12),
                padding: const EdgeInsets.all(Sx.s16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Sx.radius + 2),
                  border: Border.all(color: context.sx.cardEdge),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [Skeleton(height: 12, width: 90), Spacer(), Skeleton(height: 12, width: 110)]),
                    SizedBox(height: Sx.s16),
                    Row(children: [Skeleton(height: 24, width: 24, radius: 12), SizedBox(width: Sx.s8), Skeleton(height: 14, width: 140), Spacer(), Skeleton(height: 18, width: 50)]),
                    SizedBox(height: Sx.s12),
                    Row(children: [Skeleton(height: 24, width: 24, radius: 12), SizedBox(width: Sx.s8), Skeleton(height: 14, width: 120), Spacer(), Skeleton(height: 18, width: 50)]),
                    SizedBox(height: Sx.s16),
                    Skeleton(height: 10, width: 200),
                  ],
                ),
              ),
          ],
        ),
      );
}
