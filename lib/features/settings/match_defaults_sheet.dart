import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/design.dart';
import '../../sports/core/match_rules.dart';
import '../casual_match/data/match_setup.dart';
import '../casual_match/ui/create_match_screen.dart' show playableSportsProvider;
import '../casual_match/ui/rules_controls.dart';
import 'app_settings.dart';

/// "Doubles · Best of 3 · Rally · to 11", or what happens without defaults.
String describeMatchDefaults(AppSettings s) {
  final format = MatchFormat.values.asNameMap()[s.matchFormat];
  final r = s.matchRules;
  if (format == null && r == null) return 'Not set · 1 game to 11, or what you played last';
  return [
    format?.label ?? 'Last type played',
    if (r != null) ...[
      r.bestOf == 1 ? '1 game' : 'Best of ${r.bestOf}',
      r.scoring == ScoringSystem.rally ? 'Rally' : 'Side out',
      'to ${r.pointsToWin}',
    ],
  ].join(' · ');
}

/// How every new casual match starts: type, games, scoring, points, win by.
/// Saved on each tap, so there is nothing to confirm. The match screen still
/// lets the player change any of it for one match.
class MatchDefaultsSheet extends ConsumerWidget {
  const MatchDefaultsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final sport = ref.watch(playableSportsProvider).first;
    final s = ref.watch(appSettingsProvider);
    final ctl = ref.read(appSettingsProvider.notifier);
    final saved = s.matchRules;
    final rules = saved != null && sport.rulesProblem(saved) == null ? saved : sport.defaultRules.copyWith(bestOf: 1);
    final format = MatchFormat.values.asNameMap()[s.matchFormat] ?? MatchFormat.doubles;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SxIconTile(icon: Icons.tune_rounded, colors: [c.voltFill, c.olive], size: 44),
              const SizedBox(width: Sx.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DEFAULT MATCH SETTINGS', style: SxType.title(c.ink, size: 24)),
                    Text('Every new casual match starts like this.', style: SxType.caption(c.inkMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Sx.s24),
          Text('MATCH TYPE', style: SxType.label(c.inkMuted)),
          const SizedBox(height: Sx.s8),
          SegmentedPills<MatchFormat>(
            keyPrefix: 'defaultFormat',
            options: [for (final f in MatchFormat.values) (f, f == MatchFormat.mixed ? 'Mixed' : f.label)],
            selected: format,
            onChanged: (f) => ctl.update((s) => s.copyWith(matchFormat: () => f.name)),
          ),
          const SizedBox(height: Sx.s20),
          RulesBlock(
            sport: sport,
            rules: rules,
            onChanged: (r) => ctl.update((s) => s.copyWith(matchRules: () => r)),
          ),
          const SizedBox(height: Sx.s16),
          Row(
            children: [
              SxButton.quiet(
                key: const Key('resetMatchDefaults'),
                label: 'Reset',
                onPressed: s.matchRules == null && s.matchFormat == null
                    ? null
                    : () => ctl.update((s) => s.copyWith(matchRules: () => null, matchFormat: () => null)),
              ),
              const Spacer(),
              SxButton(label: 'Done', expand: false, height: 48, onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        ],
      ),
    );
  }
}
