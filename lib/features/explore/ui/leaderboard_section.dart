import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../../player/data/player_repository.dart';
import '../../subscription/data/plans.dart';
import '../../subscription/subscription_controller.dart';
import '../../subscription/ui/pro_widgets.dart';

/// How many of the top players the hub shows before "Full rankings".
const _topCount = 5;

/// The Explore hub's Leaderboards: pick a scope and format, see who is on
/// top and where you sit, one tap from the full rankings.
class ExploreLeaderboards extends ConsumerStatefulWidget {
  const ExploreLeaderboards({super.key});

  @override
  ConsumerState<ExploreLeaderboards> createState() => _ExploreLeaderboardsState();
}

class _ExploreLeaderboardsState extends ConsumerState<ExploreLeaderboards> {
  RankScope _scope = RankScope.city;
  PlayCategory _cat = PlayCategory.doubles;

  void _openFull() => context.push('/player/rankings?scope=${_scope.name}&format=${_cat.name}');

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final board = ref.watch(leaderboardProvider((scope: _scope, category: _cat, gender: 'All', age: 'All')));
    return Column(
      key: const Key('explore-leaderboards'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SxSection('Leaderboards', action: 'Full rankings', onAction: _openFull),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final s in RankScope.values)
                Padding(
                  padding: const EdgeInsets.only(right: Sx.s8),
                  child: SxChip(
                    key: Key('leaderScope-${s.name}'),
                    label: s.label,
                    selected: s == _scope,
                    onTap: () => setState(() => _scope = s),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Sx.s12),
        if (!ref.watch(canAccessProvider(ProFeature.leaderboard)))
          const ProLockedPanel(
            feature: ProFeature.leaderboard,
            message: 'The top players in every scope and format, and where you sit among them.',
            compact: true,
          )
        else
          SxBlock(
            padding: const EdgeInsets.fromLTRB(Sx.s16, Sx.s12, Sx.s16, Sx.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FormatSwitch(selected: _cat, onSelect: (p) => setState(() => _cat = p)),
                const SizedBox(height: Sx.s8),
                switch (board) {
                  AsyncData(:final value) when value.isEmpty => const Padding(
                      padding: EdgeInsets.symmetric(vertical: Sx.s8),
                      child: EmptyBlock(
                        icon: Icons.leaderboard_outlined,
                        title: 'No rankings yet',
                        message: 'Leaderboards appear once rated matches are played here.',
                        compact: true,
                      ),
                    ),
                  AsyncData(:final value) => _Board(entries: value),
                  AsyncError() => Padding(
                      padding: const EdgeInsets.symmetric(vertical: Sx.s16),
                      child: Text('Could not load rankings. Pull to refresh.',
                          textAlign: TextAlign.center, style: SxType.caption(c.inkMuted)),
                    ),
                  _ => const SkeletonList(rows: _topCount, rowHeight: 48),
                },
                Divider(height: Sx.s16, color: c.line),
                Semantics(
                  button: true,
                  label: 'See the full ${_scope.label} ${_cat.label} rankings',
                  excludeSemantics: true,
                  child: Tappable(
                    key: const Key('leaderFull'),
                    onTap: _openFull,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Sx.s8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text('See full ${_scope.label.toLowerCase()} rankings',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SxType.caption(c.isDark ? c.cyan : c.blue, size: 13)
                                    .copyWith(fontWeight: FontWeight.w700)),
                          ),
                          Icon(Icons.chevron_right_rounded, size: 18, color: c.isDark ? c.cyan : c.blue),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Singles / Doubles / Mixed, small enough to sit inside the board.
class _FormatSwitch extends StatelessWidget {
  const _FormatSwitch({required this.selected, required this.onSelect});

  final PlayCategory selected;
  final ValueChanged<PlayCategory> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          for (final p in PlayCategory.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: p == selected,
                label: p.label,
                excludeSemantics: true,
                child: GestureDetector(
                  key: Key('leaderFormat-${p.name}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(p),
                  child: AnimatedContainer(
                    duration: Sx.medium,
                    curve: Curves.easeOutCubic,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: p == selected ? c.brand : null,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(p.label,
                        style: TextStyle(
                          fontFamily: SxType.sans,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: p == selected ? c.onVolt : c.inkMuted,
                        )),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The top few, then the signed-in player's own place if they are further
/// down.
class _Board extends StatelessWidget {
  const _Board({required this.entries});

  final List<LeaderboardEntry> entries;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final top = entries.take(_topCount).toList();
    final me = entries.where((e) => e.isMe).firstOrNull;
    final showMe = me != null && !top.contains(me);
    return Column(
      children: [
        for (final (i, e) in top.indexed) ...[
          if (i > 0) Divider(height: 1, color: c.line),
          _Row(entry: e),
        ],
        if (showMe) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Sx.s4),
            child: Text('· · ·', style: SxType.label(c.inkFaint)),
          ),
          _Row(entry: me),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry});

  final LeaderboardEntry entry;

  static const _medals = [Color(0xFFF2C94C), Color(0xFFB8C2CC), Color(0xFFCD8A4A)];

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final e = entry;
    final medal = e.rank <= 3 ? _medals[e.rank - 1] : null;
    return PlayerTap(
      name: e.isMe ? 'You' : e.name,
      child: Container(
        key: Key('leaderRow-${e.rank}'),
        height: 56,
        padding: EdgeInsets.symmetric(horizontal: e.isMe ? Sx.s8 : 0),
        decoration: e.isMe
            ? BoxDecoration(
                color: c.voltFill.withValues(alpha: c.isDark ? 0.14 : 0.18),
                borderRadius: BorderRadius.circular(Sx.radiusSm),
              )
            : null,
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: medal != null
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: medal, shape: BoxShape.circle),
                        child: Text('${e.rank}', style: SxType.number(14, const Color(0xFF1A1A1A), weight: FontWeight.w800)),
                      ),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('${e.rank}', style: SxType.number(16, c.inkMuted, weight: FontWeight.w800)),
                    ),
            ),
            SxAvatar(name: e.name, size: 34),
            const SizedBox(width: Sx.s12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.isMe ? '${e.name} (you)' : e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SxType.heading(c.ink, size: 14.5)
                          .copyWith(fontWeight: e.isMe ? FontWeight.w800 : FontWeight.w600)),
                  Text('${e.city} · ${e.winRate}% wins',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted, size: 12)),
                ],
              ),
            ),
            const SizedBox(width: Sx.s8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(ratingText(e.rating), style: SxType.number(17, c.ink, weight: FontWeight.w800)),
                if (e.change != 0)
                  Text('${e.change > 0 ? '▲' : '▼'} ${e.change.abs()}',
                      style: SxType.caption(e.change > 0 ? c.volt : c.inkMuted, size: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
