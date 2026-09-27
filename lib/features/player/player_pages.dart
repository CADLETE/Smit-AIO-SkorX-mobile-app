import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../design/design.dart';
import '../../shared/ui/components.dart' show reduceMotion;
import '../../sports/core/score_state.dart';
import '../casual_match/scoring_controller.dart';
import '../community/community_controller.dart' show communityBadgeProvider;
import '../shell/workspace_shell.dart';

/// Player tabs, in branch order: one question each (docs/PLAYER-APP.md).
final playerDestinations = [
  const ShellDestination('Home', Icons.home_outlined, Icons.home_rounded),
  const ShellDestination('Matches', Icons.scoreboard_outlined, Icons.scoreboard_rounded),
  // Explore holds Tournaments, Scores, Courts, Community, Looking For…; its
  // badge counts Community requests and unread messages.
  ShellDestination('Explore', Icons.explore_outlined, Icons.explore_rounded, badge: communityBadgeProvider),
  const ShellDestination('My Paddle', Icons.sports_tennis_outlined, Icons.sports_tennis_rounded),
  const ShellDestination('Account', Icons.person_outline_rounded, Icons.person_rounded),
];

/// Bottom padding for a player tab's scroll view: clears the tab bar and,
/// when shown, the resume bar.
double playerTabBottom(BuildContext context) => MediaQuery.paddingOf(context).bottom + Sx.s32;

/// A casual match being scored on this phone, one tap away from any tab.
class ResumeMatchBar extends ConsumerWidget {
  const ResumeMatchBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final match = ref.watch(scoringControllerProvider);
    if (match == null || match.isOver) return const SizedBox.shrink();
    final c = context.sx;
    final score = match.score;
    final a = score.currentGame.of(Side.a);
    final b = score.currentGame.of(Side.b);

    return SxWidth(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Sx.s12, 0, Sx.s12, Sx.s8),
        child: Semantics(
          button: true,
          label: 'Resume scoring, game ${score.gameNumber}, $a to $b',
          excludeSemantics: true,
          child: Tappable(
            key: const Key('resumeMatchBar'),
            onTap: () {
              HapticFeedback.lightImpact();
              context.go('/player/match');
            },
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: Sx.s16),
              decoration: BoxDecoration(
                gradient: c.hero,
                borderRadius: BorderRadius.circular(Sx.radius),
                boxShadow: c.glowOf(c.blue),
              ),
              child: Row(
                children: [
                  LivePulse(size: 8, color: c.live),
                  const SizedBox(width: Sx.s8),
                  Text('SCORING', style: SxType.label(Colors.white, size: 13)),
                  const SizedBox(width: Sx.s12),
                  Expanded(
                    child: Text(
                      'Game ${score.gameNumber} · ${match.label(Side.a)} vs ${match.label(Side.b)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SxType.caption(Colors.white.withValues(alpha: 0.8)),
                    ),
                  ),
                  Text('$a–$b', style: SxType.number(26, Colors.white, weight: FontWeight.w800)),
                  const SizedBox(width: Sx.s8),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pulsing red dot, used by the organiser screens. Still when the system
/// asks for less motion.
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.size = 8});

  final double size;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = context.skorx.colors.live;
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_pulse),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: live,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: live.withValues(alpha: 0.7), blurRadius: 8)],
        ),
      ),
    );
  }
}

/// A player tab's page: safe area, centred width, pull to refresh, and room
/// under the last item for the tab bar.
class PlayerTabList extends StatelessWidget {
  const PlayerTabList({super.key, required this.children, this.onRefresh, this.header, this.controller});

  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  /// Pinned above the scrolling content (a title bar, tabs).
  final Widget? header;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, playerTabBottom(context)),
      children: [for (final (i, child) in children.indexed) SxReveal(index: i, child: child)],
    );
    return SafeArea(
      bottom: false,
      child: SxWidth(
        child: Column(
          children: [
            ?header,
            Expanded(
              child: onRefresh == null
                  ? list
                  : RefreshIndicator(
                      onRefresh: onRefresh!,
                      color: context.sx.onVolt,
                      backgroundColor: context.sx.voltFill,
                      child: list,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
