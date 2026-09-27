import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/theme/typography.dart';
import '../../../core/api/api_exception.dart';
import '../../../design/player_dp.dart';
import '../../../shared/format.dart';
import '../../../shared/ui/components.dart';
import '../../../sports/core/score_state.dart';
import '../../player/player_pages.dart' show LiveDot;
import '../../workspace/workspace.dart';
import '../../workspace/workspace_controller.dart';
import '../data/organizer_repository.dart';
import '../data/tms_models.dart';

/// What the signed-in member may do in this organisation. From the role's
/// capabilities (`GET /auth/me`); the server enforces the same list, so
/// hiding here is for clarity, never for security.
class OrgPermissions {
  const OrgPermissions(this.capabilities);

  final Set<String> capabilities;

  bool _has(String c) => capabilities.contains(c);

  bool get editTournaments => _has('editTournament');
  bool get manageEntries => _has('managePlayers');
  bool get checkIn => _has('manageCheckIn') || manageEntries;
  bool get schedule => _has('manageSchedule') || editTournaments;
  bool get score => _has('scoreMatch') || editTournaments;
  bool get money => _has('managePayments');
  bool get analytics => _has('viewAnalytics');
  bool get settings => _has('manageSettings');
  bool get announce => editTournaments;
}

OrganizerWorkspace? orgWorkspace(WidgetRef ref, String orgId) => ref
    .watch(workspaceControllerProvider)
    .available
    .whereType<OrganizerWorkspace>()
    .where((w) => w.organizationId == orgId)
    .firstOrNull;

OrgPermissions orgPermissions(WidgetRef ref, String orgId) =>
    OrgPermissions(orgWorkspace(ref, orgId)?.membership.capabilities ?? const {});

/// Keeps every organiser screen under it current from the realtime stream.
class OrgRealtimeScope extends ConsumerWidget {
  const OrgRealtimeScope({super.key, required this.orgId, required this.child});

  final String orgId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(tmsRealtimeProvider(orgId));
    return child;
  }
}

SkxTone tournamentTone(TournamentStatus s) => switch (s) {
      TournamentStatus.live => SkxTone.live,
      TournamentStatus.registrationOpen => SkxTone.success,
      TournamentStatus.registrationClosed || TournamentStatus.drawGenerated || TournamentStatus.scheduled => SkxTone.info,
      TournamentStatus.completed => SkxTone.brand,
      TournamentStatus.draft => SkxTone.warning,
      TournamentStatus.cancelled || TournamentStatus.archived => SkxTone.neutral,
    };

class TournamentStatusPill extends StatelessWidget {
  const TournamentStatusPill(this.status, {super.key});

  final TournamentStatus status;

  @override
  Widget build(BuildContext context) {
    if (status == TournamentStatus.live) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LiveDot(),
          const SizedBox(width: 6),
          Flexible(child: SkxPill(status.label, tone: SkxTone.live, solid: true)),
        ],
      );
    }
    return SkxPill(status.label, tone: tournamentTone(status));
  }
}

SkxTone courtTone(CourtStatus s) => switch (s) {
      CourtStatus.live => SkxTone.success,
      CourtStatus.ready => SkxTone.info,
      CourtStatus.delayed => SkxTone.warning,
      CourtStatus.maintenance || CourtStatus.blocked => SkxTone.live,
      CourtStatus.idle || CourtStatus.onBreak => SkxTone.neutral,
    };

SkxTone approvalTone(Approval a) => switch (a) {
      Approval.approved => SkxTone.success,
      Approval.pending => SkxTone.warning,
      Approval.waitlisted => SkxTone.info,
      Approval.rejected => SkxTone.neutral,
    };

SkxTone paymentTone(PaymentState p) => switch (p) {
      PaymentState.paid || PaymentState.waived => SkxTone.success,
      PaymentState.pending => SkxTone.warning,
      PaymentState.refunded => SkxTone.neutral,
    };

/// A big number with a label and icon. Tappable when it leads somewhere.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone,
    this.caption,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;

  /// Colours the icon and number when the metric needs attention.
  final SkxTone? tone;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final accent = tone == null ? colors.cyan : toneColor(context, tone!);
    return SkxCard(
      onTap: onTap,
      semanticLabel: '$label: $value${caption == null ? '' : ', $caption'}',
      padding: const EdgeInsets.all(SkorxSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const Spacer(),
              if (onTap != null) Icon(Icons.chevron_right_rounded, size: 18, color: colors.textMuted),
            ],
          ),
          const SizedBox(height: SkorxSpace.md),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: SkorxType.score(34, color: tone == null ? colors.text : accent)),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SkorxType.label(color: colors.textMuted, size: 11),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.textMuted, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

/// Two metric cards per row.
class MetricGrid extends StatelessWidget {
  const MetricGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i += 2) ...[
          if (i > 0) const SizedBox(height: SkorxSpace.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: children[i]),
                const SizedBox(width: SkorxSpace.md),
                Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A big round action with a label under it, for one-thumb use on court.
class QuickAction extends StatelessWidget {
  const QuickAction({super.key, required this.icon, required this.label, required this.onTap, this.primary = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        haptic: true,
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: primary ? colors.lime : colors.surface,
                borderRadius: BorderRadius.circular(SkorxRadius.lg),
                border: Border.all(color: primary ? colors.lime : colors.border),
              ),
              child: Icon(icon, color: primary ? limeInk : colors.text, size: 26),
            ),
            const SizedBox(height: SkorxSpace.sm),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.text, height: 1.15),
            ),
          ],
        ),
      ),
    );
  }
}

class QuickActionRow extends StatelessWidget {
  const QuickActionRow({super.key, required this.actions});

  final List<QuickAction> actions;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final a in actions) Expanded(child: a)],
      );
}

/// The players on one side, for their pictures; empty until the slot is filled.
List<String> sideNames(TmsMatch m, Side s) => m.entry(s) == null ? const [] : m.label(s).split(' / ');

/// A court on the live board: name, status, and the score or what is next.
class CourtTile extends StatelessWidget {
  const CourtTile({super.key, required this.slot, required this.now, this.onTap});

  final CourtSlot slot;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final tone = courtTone(slot.status);
    final accent = toneColor(context, tone);
    final m = slot.current;
    final live = slot.status == CourtStatus.live;

    Widget side(Side s) {
      final serving = live && m!.serve?.side == s;
      final points = m!.currentGame.of(s);
      return Row(
        children: [
          if (serving)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.sports_baseball_rounded, size: 11, color: colors.limeText),
            ),
          SideDps(names: sideNames(m, s), size: 18, edge: colors.surface),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              m.label(s),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: serving ? FontWeight.w800 : FontWeight.w600, color: colors.text),
            ),
          ),
          if (m.state != MatchState.called)
            Text('$points', style: SkorxType.score(26, color: serving ? colors.limeText : colors.text)),
        ],
      );
    }

    final String semantic;
    if (m != null && m.state != MatchState.called) {
      semantic = '${slot.court.name}, ${slot.status.label}. ${m.labelA} ${m.currentGame.a}, ${m.labelB} ${m.currentGame.b}';
    } else if (m != null) {
      semantic = '${slot.court.name}, ${slot.status.label}. Match ${m.number} called: ${m.labelA} versus ${m.labelB}';
    } else {
      semantic = '${slot.court.name}, ${slot.status.label}';
    }

    return SkxCard(
      onTap: onTap,
      semanticLabel: semantic,
      padding: const EdgeInsets.all(SkorxSpace.md),
      borderColor: live || slot.status == CourtStatus.delayed ? accent.withValues(alpha: 0.5) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  slot.court.name.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SkorxType.headline(18, color: colors.text, weight: FontWeight.w800),
                ),
              ),
              if (live) ...[const LiveDot(size: 7), const SizedBox(width: 4)],
              SkxPill(slot.status.label, tone: tone),
            ],
          ),
          const SizedBox(height: SkorxSpace.sm),
          if (m != null) ...[
            Text(
              'M${m.number} · ${m.roundLabel}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: colors.textMuted),
            ),
            const SizedBox(height: 6),
            side(Side.a),
            const SizedBox(height: 4),
            side(Side.b),
            if (m.state == MatchState.called) ...[
              const SizedBox(height: 6),
              Text(
                m.scheduledAt == null ? 'Waiting to start' : 'Due ${time12(m.scheduledAt!)}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accent),
              ),
            ],
          ] else ...[
            Text(
              switch (slot.status) {
                CourtStatus.onBreak || CourtStatus.maintenance || CourtStatus.blocked =>
                  slot.court.note ?? slot.court.mode.label,
                _ => slot.next == null
                    ? 'Nothing scheduled'
                    : 'Next: M${slot.next!.number} at ${time12(slot.next!.scheduledAt!)}',
              },
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: colors.textMuted, height: 1.3),
            ),
          ],
        ],
      ),
    );
  }
}

/// One match in a list: number, round, sides, and its score or time.
class TmsMatchRow extends StatelessWidget {
  const TmsMatchRow({super.key, required this.match, this.court, this.category, this.onTap, this.now});

  final TmsMatch match;
  final String? court;
  final String? category;
  final VoidCallback? onTap;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final m = match;
    final delayed = now != null && m.isDelayed(now!);
    final (String status, SkxTone tone) = switch (m.state) {
      MatchState.live => ('Live', SkxTone.live),
      MatchState.paused => ('Paused', SkxTone.warning),
      MatchState.completed => ('Final', SkxTone.neutral),
      MatchState.called => (delayed ? 'Delayed' : 'Called', delayed ? SkxTone.warning : SkxTone.info),
      _ => (delayed ? 'Delayed' : (m.scheduledAt == null ? 'Unscheduled' : time12(m.scheduledAt!)),
          delayed ? SkxTone.warning : SkxTone.neutral),
    };

    Widget line(Side s) {
      final won = m.winner == s && m.state == MatchState.completed;
      return Row(
        children: [
          SideDps(names: sideNames(m, s), size: 22, edge: colors.surface),
          const SizedBox(width: SkorxSpace.sm),
          Expanded(
            child: Text(
              m.label(s),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: won ? FontWeight.w800 : FontWeight.w600,
                color: m.entry(s) == null ? colors.textMuted : colors.text,
              ),
            ),
          ),
          if (m.games.isNotEmpty)
            for (final g in m.games)
              SizedBox(
                width: 26,
                child: Text(
                  '${g.of(s)}',
                  textAlign: TextAlign.right,
                  style: SkorxType.score(17, color: g.of(s) > g.of(s.opponent) ? colors.text : colors.textMuted),
                ),
              ),
        ],
      );
    }

    return SkxCard(
      onTap: onTap,
      padding: const EdgeInsets.all(SkorxSpace.md),
      semanticLabel: 'Match ${m.number}, ${m.roundLabel}, ${m.labelA} versus ${m.labelB}, $status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('M${m.number}', style: SkorxType.label(color: colors.textMuted, size: 12)),
              const SizedBox(width: SkorxSpace.sm),
              Expanded(
                child: Text(
                  [m.roundLabel, ?category, ?court].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              ),
              if (m.state == MatchState.live) ...[const LiveDot(size: 6), const SizedBox(width: 4)],
              SkxPill(status, tone: tone),
            ],
          ),
          const SizedBox(height: SkorxSpace.sm),
          line(Side.a),
          const SizedBox(height: 4),
          line(Side.b),
        ],
      ),
    );
  }
}

/// A thin progress bar with a label and "x / y".
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.label, required this.done, required this.total, this.tone = SkxTone.brand});

  final String label;
  final int done;
  final int total;
  final SkxTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final color = tone == SkxTone.brand ? colors.lime : toneColor(context, tone);
    return Semantics(
      label: '$label: $done of $total',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: colors.textMuted))),
              Text('$done / $total', style: SkorxType.score(16, color: colors.text)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 6,
              backgroundColor: colors.surfaceInteractive,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks before an action players will notice. Destructive actions use a red
/// button and say what will happen; the safe choice is on the left.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
  String cancel = 'Cancel',
  bool destructive = false,
}) async {
  final colors = context.skorx.colors;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(SkorxSpace.xl, 0, SkorxSpace.xl, SkorxSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(header: true, child: Text(title, style: SkorxType.headline(28, color: colors.text))),
            const SizedBox(height: SkorxSpace.md),
            Text(message, style: TextStyle(fontSize: 15, color: colors.textMuted, height: 1.4)),
            const SizedBox(height: SkorxSpace.xl),
            Row(
              children: [
                Expanded(child: SkxButton.secondary(label: cancel, onPressed: () => Navigator.pop(context, false))),
                const SizedBox(width: SkorxSpace.md),
                Expanded(
                  child: destructive
                      ? SkxButton(
                          key: const Key('confirmAction'),
                          label: confirm,
                          kind: SkxButtonKind.danger,
                          height: 52,
                          onPressed: () => Navigator.pop(context, true),
                        )
                      : SkxButton(
                          key: const Key('confirmAction'),
                          label: confirm,
                          height: 52,
                          onPressed: () => Navigator.pop(context, true),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return ok ?? false;
}

/// Runs [action] and shows a friendly message if it fails. Returns whether
/// it succeeded. Server messages are written for people; anything else
/// becomes a calm "nothing changed".
Future<bool> runAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) showSkxToast(context, success);
    return true;
  } on ApiException catch (e) {
    if (context.mounted) showSkxToast(context, e.message, icon: Icons.error_outline_rounded);
    return false;
  } catch (_) {
    if (context.mounted) {
      showSkxToast(context, 'Something went wrong. Nothing was changed; try again.', icon: Icons.error_outline_rounded);
    }
    return false;
  }
}

/// The tournament at the top of a tournament screen: name, status, date.
class TournamentBanner extends StatelessWidget {
  const TournamentBanner({super.key, required this.tournament});

  final OrgTournament tournament;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final t = tournament;
    return Padding(
      padding: const EdgeInsets.only(bottom: SkorxSpace.lg),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${t.name} · ${dateRange(t.start, t.end)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.textMuted, fontSize: 13),
            ),
          ),
          const SizedBox(width: SkorxSpace.sm),
          TournamentStatusPill(t.status),
        ],
      ),
    );
  }
}

/// A read-only screen for a role without the capability.
class NoAccess extends StatelessWidget {
  const NoAccess({super.key, required this.what});

  final String what;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(SkorxSpace.lg),
        child: SkxEmpty(
          icon: Icons.lock_outline_rounded,
          title: 'Your role cannot $what',
          message: 'Ask an owner of this organisation if you need access.',
        ),
      );
}
