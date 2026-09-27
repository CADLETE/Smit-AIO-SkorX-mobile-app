import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../data/player_stats.dart';

/// Where a player's full stats live.
String playerStatsPath(String id) => '/player/players/${Uri.encodeComponent(id)}';

/// Where two players' head-to-head lives.
String headToHeadPath(String a, String b) => '${playerStatsPath(a)}/vs/${Uri.encodeComponent(b)}';

/// Tapping any player (a picture, a name) opens this: who they are and how
/// they play, readable in a few seconds, with the way to their full stats.
Future<void> showPlayerQuickView(BuildContext context, String nameOrId) {
  HapticFeedback.selectionClick();
  return showSxSheet<void>(context, builder: (sheet) => PlayerQuickView(player: nameOrId, host: context));
}

class PlayerQuickView extends ConsumerWidget {
  const PlayerQuickView({super.key, required this.player, required this.host});

  /// A name from a match, or a player id.
  final String player;

  /// The screen the sheet was opened from, which navigation goes through.
  final BuildContext host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = ref.watch(playerCardProvider(player));
    return SingleChildScrollView(
      key: const Key('playerQuickView'),
      padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
      child: AnimatedSwitcher(
        duration: Sx.medium,
        child: switch (card) {
          AsyncData(value: (final profile, final stats)) => _Card(profile: profile, stats: stats, host: host),
          AsyncError() => ErrorBlock(message: 'This player did not load.', onRetry: () => ref.invalidate(playerCardProvider(player))),
          _ => const _CardSkeleton(),
        },
      ),
    );
  }
}

class _Card extends ConsumerWidget {
  const _Card({required this.profile, required this.stats, required this.host});

  final PlayerProfile profile;
  final PlayerStats stats;
  final BuildContext host;

  void _open(BuildContext context, String path) {
    Navigator.of(context).pop();
    GoRouter.of(host).push(path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final p = profile;
    final s = stats.career;
    final h2h = p.isMe ? null : ref.watch(headToHeadProvider(('me', p.id))).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlayerHeader(profile: p),
        const SizedBox(height: Sx.s24),
        Row(
          children: [
            Expanded(child: Stat(value: '${s.played}', label: 'Matches', size: 30)),
            Expanded(child: Stat(value: s.winRate == null ? '—' : '${s.winRate}%', label: 'Win %', size: 30)),
            Expanded(
              child: Stat(
                value: p.points?.toString() ?? '—',
                label: 'SkorX Points',
                size: 30,
                color: p.points == null ? null : c.volt,
              ),
            ),
          ],
        ),
        if (s.played > 0) ...[
          const SizedBox(height: Sx.s16),
          RecordBar(wins: s.wins, losses: s.losses, height: 6),
          const SizedBox(height: Sx.s8),
          Text('${s.wins} won · ${s.losses} lost', style: SxType.caption(c.inkMuted, size: 12.5)),
          const SizedBox(height: Sx.s20),
          FormatTiles(formats: stats.formats),
          const SizedBox(height: Sx.s20),
          Row(
            children: [
              Text('FORM', style: SxType.label(c.inkMuted, size: 12)),
              const SizedBox(width: Sx.s12),
              Expanded(child: FormStrip(form: stats.form.take(5).toList())),
              if (stats.streakLabel != null) Text('Streak ${stats.streakLabel}', style: SxType.label(c.inkMuted, size: 12)),
            ],
          ),
        ] else ...[
          const SizedBox(height: Sx.s16),
          Text(
            p.isMe ? 'Play your first match to start your SkorX record.' : 'No finished matches on SkorX yet.',
            style: SxType.body(c.inkMuted),
          ),
        ],
        if (h2h != null && h2h.played > 0) ...[
          const SizedBox(height: Sx.s20),
          SxBlock(
            key: const Key('quickViewHeadToHead'),
            padding: const EdgeInsets.symmetric(horizontal: Sx.s16, vertical: Sx.s12),
            semanticLabel: 'You against ${p.name}: ${h2h.aWins} wins, ${h2h.bWins} losses. Open head-to-head',
            onTap: () => _open(context, headToHeadPath('me', p.id)),
            child: Row(
              children: [
                Icon(Icons.compare_arrows_rounded, color: c.inkMuted, size: 20),
                const SizedBox(width: Sx.s12),
                Expanded(child: Text('You vs ${p.name.split(' ').first}', style: SxType.heading(c.ink, size: 15))),
                Text('${h2h.aWins}–${h2h.bWins}', style: SxType.number(22, c.ink, weight: FontWeight.w800)),
                Icon(Icons.chevron_right_rounded, color: c.inkFaint),
              ],
            ),
          ),
        ],
        const SizedBox(height: Sx.s24),
        SxButton(
          key: const Key('viewFullStats'),
          label: 'View full stats',
          icon: Icons.insights_rounded,
          onPressed: () => _open(context, playerStatsPath(p.id)),
        ),
      ],
    );
  }
}

/// Picture, name, id and level, and where they play.
class PlayerHeader extends StatelessWidget {
  const PlayerHeader({super.key, required this.profile, this.size = 64});

  final PlayerProfile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final p = profile;
    return Row(
      children: [
        p.isMe ? _MeRing(size: size) : PlayerDp(name: p.name, size: size),
        const SizedBox(width: Sx.s16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Semantics(
                      header: true,
                      child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: SxType.title(c.ink, size: 28)),
                    ),
                  ),
                  if (p.isMe) ...[
                    const SizedBox(width: Sx.s8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(gradient: c.brand, borderRadius: BorderRadius.circular(10)),
                      child: Text('YOU', style: SxType.label(c.onVolt, size: 11)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                [if (p.hasPublicId) p.id, ?p.level].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SxType.caption(c.inkMuted),
              ),
              if (p.placeLabel != null) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.place_outlined, size: 14, color: c.inkFaint),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(p.placeLabel!, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MeRing extends StatelessWidget {
  const _MeRing({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(colors: [c.voltFill, c.cyan, c.blue, c.voltFill]),
      ),
      child: PlayerDp(name: 'You', size: size - 5, edge: c.surface),
    );
  }
}

/// One tile per format played: matches and win %. Only formats the player
/// has played, so the row never shows empty tiles.
class FormatTiles extends StatelessWidget {
  const FormatTiles({super.key, required this.formats});

  final List<WinLoss> formats;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    if (formats.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (final (i, f) in formats.indexed) ...[
          if (i > 0) const SizedBox(width: Sx.s8),
          Expanded(
            child: Semantics(
              label: '${f.label}: ${f.played} matches, ${f.winRate ?? 0} percent won',
              excludeSemantics: true,
              child: Container(
                padding: const EdgeInsets.fromLTRB(Sx.s12, Sx.s12, Sx.s8, Sx.s12),
                decoration: BoxDecoration(
                  color: c.surfaceAlt.withValues(alpha: c.isDark ? 0.7 : 1),
                  borderRadius: BorderRadius.circular(Sx.radius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.label.toUpperCase(), maxLines: 1, style: SxType.label(c.inkMuted, size: 11)),
                    const SizedBox(height: Sx.s8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('${f.played}', style: SxType.number(26, c.ink, weight: FontWeight.w800)),
                    ),
                    Text(f.played == 1 ? 'match' : 'matches', style: SxType.caption(c.inkMuted, size: 12)),
                    const SizedBox(height: Sx.s4),
                    Text('${f.winRate ?? 0}% win',
                        maxLines: 1, style: SxType.heading(f.winRate != null && f.winRate! >= 50 ? c.volt : c.inkMuted, size: 14)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Recent results as W / L marks, newest first.
class FormStrip extends StatelessWidget {
  const FormStrip({super.key, required this.form, this.size = 26});

  final List<bool> form;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      label: 'Form, newest first: ${form.map((w) => w ? 'win' : 'loss').join(', ')}',
      excludeSemantics: true,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final won in form)
            Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: won ? c.brand : null,
                color: won ? null : c.surfaceAlt,
              ),
              child: Text(won ? 'W' : 'L', style: SxType.verdict(size * 0.55, won ? c.onVolt : c.inkMuted)),
            ),
        ],
      ),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Loading player',
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Skeleton(width: 64, height: 64, radius: 32),
                SizedBox(width: Sx.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton(height: 22, width: 170),
                      SizedBox(height: Sx.s8),
                      Skeleton(height: 12, width: 120),
                      SizedBox(height: Sx.s8),
                      Skeleton(height: 12, width: 140),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: Sx.s24),
            Row(
              children: [
                Expanded(child: Skeleton(height: 44)),
                SizedBox(width: Sx.s16),
                Expanded(child: Skeleton(height: 44)),
                SizedBox(width: Sx.s16),
                Expanded(child: Skeleton(height: 44)),
              ],
            ),
            SizedBox(height: Sx.s20),
            Row(
              children: [
                Expanded(child: Skeleton(height: 96, radius: Sx.radius)),
                SizedBox(width: Sx.s8),
                Expanded(child: Skeleton(height: 96, radius: Sx.radius)),
              ],
            ),
            SizedBox(height: Sx.s24),
            Skeleton(height: 52, radius: Sx.radius),
          ],
        ),
      );
}
