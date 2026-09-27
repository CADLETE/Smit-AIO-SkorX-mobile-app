import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/theme/typography.dart';
import '../../../shared/format.dart';
import '../../../shared/ui/components.dart';
import '../../player/player_pages.dart' show LiveDot;
import '../../shell/workspace_shell.dart';
import '../data/organizer_repository.dart';
import '../data/tms_models.dart';
import 'org_home_page.dart';
import 'org_widgets.dart';

enum _Show { all, live, waiting, issues }

/// The Live tab: the running tournament's control room, or the way to it.
class OrgLiveTab extends ConsumerWidget {
  const OrgLiveTab({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(orgTournamentsProvider(orgId));
    return AsyncBody<List<OrgTournament>>(
      value: all,
      onRetry: () => ref.invalidate(orgTournamentsProvider(orgId)),
      loading: const Padding(padding: EdgeInsets.all(SkorxSpace.lg), child: SkeletonCard(height: 300)),
      data: (list) {
        final live = list.where((t) => t.status == TournamentStatus.live).firstOrNull;
        if (live != null) return LiveControlRoom(orgId: orgId, tournament: live, inTab: true);
        final ready = list.where((t) => t.status == TournamentStatus.scheduled).firstOrNull;
        return ListView(
          padding: const EdgeInsets.all(SkorxSpace.lg),
          children: [
            const ScreenHeader(title: 'Live'),
            SkxEmpty(
              icon: Icons.sensors_off_rounded,
              title: 'Nothing live right now',
              message: ready == null
                  ? 'When a tournament starts, every court and score shows here.'
                  : '${ready.name} is scheduled. Start it when the first players are on court.',
              actionLabel: ready == null ? null : 'Open ${ready.name}',
              onAction: () => context.push('/org/$orgId/t/${ready!.id}'),
            ),
          ],
        );
      },
    );
  }
}

/// Every court at once, so the organiser never opens a match to know how
/// it is going.
class LiveControlRoom extends ConsumerStatefulWidget {
  const LiveControlRoom({super.key, required this.orgId, required this.tournament, this.inTab = false});

  final String orgId;
  final OrgTournament tournament;
  final bool inTab;

  @override
  ConsumerState<LiveControlRoom> createState() => _LiveControlRoomState();
}

class _LiveControlRoomState extends ConsumerState<LiveControlRoom> {
  var _show = _Show.all;
  late Timer _clock;
  var _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Delays depend on the time, so the board re-checks every half minute.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final t = widget.tournament;
    final orgId = widget.orgId;
    final can = orgPermissions(ref, orgId);
    final matches = ref.watch(tmsMatchesProvider(t.id));
    final courts = ref.watch(courtsProvider(t.id));

    if (matches.value == null || courts.value == null) {
      if (matches.hasError || courts.hasError) {
        return Padding(
          padding: const EdgeInsets.all(SkorxSpace.lg),
          child: ErrorState(
            message: "We couldn't load the courts. Scores being kept on phones are safe.",
            onRetry: () {
              ref.invalidate(tmsMatchesProvider(t.id));
              ref.invalidate(courtsProvider(t.id));
            },
          ),
        );
      }
      return const Padding(padding: EdgeInsets.all(SkorxSpace.lg), child: SkeletonCard(height: 400));
    }

    final s = LiveSummary(matches.value!, courts.value!, _now);
    final board = s.board.where((slot) => switch (_show) {
          _Show.all => true,
          _Show.live => slot.status == CourtStatus.live,
          _Show.waiting => slot.status == CourtStatus.ready || slot.status == CourtStatus.idle,
          _Show.issues => slot.status == CourtStatus.delayed ||
              slot.status == CourtStatus.maintenance ||
              slot.status == CourtStatus.blocked,
        }).toList();
    final queue = matches.value!
        .where((m) => m.state == MatchState.scheduled || (m.state == MatchState.pending && m.ready))
        .toList()
      ..sort((a, b) => (a.scheduledAt ?? _now).compareTo(b.scheduledAt ?? _now));
    final courtName = {for (final c in courts.value!) c.id: c.name};
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1000 ? 4 : width >= 680 ? 3 : 2;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(tmsMatchesProvider(t.id));
        ref.invalidate(courtsProvider(t.id));
        await ref.read(tmsMatchesProvider(t.id).future);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          SkorxSpace.lg,
          SkorxSpace.sm,
          SkorxSpace.lg,
          widget.inTab ? tabBottomPadding(context) + 80 : SkorxSpace.xxl + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Row(
            children: [
              const LiveDot(),
              const SizedBox(width: SkorxSpace.sm),
              Text('LIVE · ${time12(_now)}', style: SkorxType.label(color: colors.live, size: 13)),
              const Spacer(),
              if (s.round != null) Text(s.round!.toUpperCase(), style: SkorxType.label(color: colors.textMuted, size: 12)),
            ],
          ),
          const SizedBox(height: SkorxSpace.xs),
          Text(t.name.toUpperCase(), maxLines: 2, style: SkorxType.headline(30, color: colors.text)),
          const SizedBox(height: SkorxSpace.lg),
          SkxCard(
            padding: const EdgeInsets.symmetric(horizontal: SkorxSpace.lg, vertical: SkorxSpace.md),
            child: Row(
              children: [
                Expanded(child: StatBlock(value: '${s.completed}/${s.total}', label: 'Done', size: 26)),
                Expanded(child: StatBlock(value: '${s.courtsLive}', label: 'Courts live', size: 26, color: colors.success)),
                Expanded(child: StatBlock(value: '${s.waiting}', label: 'Waiting', size: 26)),
                Expanded(
                  child: StatBlock(
                    value: '${s.delayed}',
                    label: 'Delayed',
                    size: 26,
                    color: s.delayed > 0 ? colors.warning : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SkorxSpace.lg),
          QuickActionRow(actions: [
            if (can.announce)
              QuickAction(
                icon: Icons.timer_outlined,
                label: 'Announce delay',
                onTap: () => context.push('/org/$orgId/t/${t.id}/announce?kind=delay'),
              ),
            if (can.schedule)
              QuickAction(icon: Icons.grid_on_rounded, label: 'Courts', onTap: () => context.push('/org/$orgId/t/${t.id}/courts')),
            if (can.checkIn)
              QuickAction(icon: Icons.qr_code_scanner_rounded, label: 'Check-in', onTap: () => context.push('/org/$orgId/t/${t.id}/check-in')),
            QuickAction(icon: Icons.emoji_events_outlined, label: 'Results', onTap: () => context.push('/org/$orgId/t/${t.id}/results')),
          ]),
          const SizedBox(height: SkorxSpace.lg),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final (v, label) in [
                  (_Show.all, 'All ${s.board.length}'),
                  (_Show.live, 'Live ${s.courtsLive}'),
                  (_Show.waiting, 'Waiting'),
                  (_Show.issues, 'Issues'),
                ]) ...[
                  SkxChip(label: label, selected: _show == v, onTap: () => setState(() => _show = v)),
                  const SizedBox(width: SkorxSpace.sm),
                ],
              ],
            ),
          ),
          const SizedBox(height: SkorxSpace.sm),
          if (board.isEmpty)
            const SkxEmpty(compact: true, icon: Icons.check_circle_outline_rounded, title: 'Nothing here right now'),
          for (var i = 0; i < board.length; i += columns) ...[
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < columns; j++) ...[
                    if (j > 0) const SizedBox(width: SkorxSpace.md),
                    Expanded(
                      child: i + j < board.length
                          ? CourtTile(
                              key: Key('court-${board[i + j].court.id}'),
                              slot: board[i + j],
                              now: _now,
                              onTap: () => showCourtSheet(context, ref, orgId, t, board[i + j], queue),
                            )
                          : const SizedBox(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: SkorxSpace.md),
          ],
          if (queue.isNotEmpty) ...[
            SkxSectionTitle('Up next', trailing: Text('${queue.length}', style: SkorxType.score(18, color: colors.textMuted))),
            for (final m in queue.take(6)) ...[
              TmsMatchRow(
                match: m,
                court: courtName[m.courtId],
                category: t.category(m.categoryId)?.name,
                now: _now,
                onTap: () => showMatchSheet(context, ref, orgId, t, m, courts.value!),
              ),
              const SizedBox(height: SkorxSpace.sm),
            ],
          ],
        ],
      ),
    );
  }
}

/// A tournament's courts as their own screen.
class CourtsPage extends ConsumerWidget {
  const CourtsPage({super.key, required this.orgId, required this.tournamentId});

  final String orgId;
  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(orgTournamentProvider(tournamentId));
    final courts = ref.watch(courtsProvider(tournamentId));
    final matches = ref.watch(tmsMatchesProvider(tournamentId)).value ?? const <TmsMatch>[];
    final now = DateTime.now();
    return DetailScaffold(
      title: 'Courts',
      fallback: '/org/$orgId/t/$tournamentId',
      body: AsyncBody<OrgTournament>(
        value: t,
        onRetry: () => ref.invalidate(orgTournamentProvider(tournamentId)),
        data: (t) => AsyncBody<List<TmsCourt>>(
          value: courts,
          onRetry: () => ref.invalidate(courtsProvider(tournamentId)),
          data: (list) {
            final board = courtBoard(list, matches, now);
            final queue = matches.where((m) => m.state == MatchState.scheduled).toList();
            return ListView(
              padding: EdgeInsets.fromLTRB(SkorxSpace.lg, SkorxSpace.sm, SkorxSpace.lg, SkorxSpace.xxl + MediaQuery.paddingOf(context).bottom),
              children: [
                TournamentBanner(tournament: t),
                if (board.isEmpty) const SkxEmpty(icon: Icons.grid_off_rounded, title: 'No courts yet'),
                for (var i = 0; i < board.length; i += 2) ...[
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: CourtTile(
                            slot: board[i],
                            now: now,
                            onTap: () => showCourtSheet(context, ref, orgId, t, board[i], queue),
                          ),
                        ),
                        const SizedBox(width: SkorxSpace.md),
                        Expanded(
                          child: i + 1 < board.length
                              ? CourtTile(
                                  slot: board[i + 1],
                                  now: now,
                                  onTap: () => showCourtSheet(context, ref, orgId, t, board[i + 1], queue),
                                )
                              : const SizedBox(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: SkorxSpace.md),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// What can be done with a court: score it, start or call its match, or
/// change its state.
Future<void> showCourtSheet(
  BuildContext context,
  WidgetRef ref,
  String orgId,
  OrgTournament t,
  CourtSlot slot,
  List<TmsMatch> queue,
) {
  final can = orgPermissions(ref, orgId);
  final repo = ref.read(organizerRepositoryProvider);
  final m = slot.current;
  final court = slot.court;
  final live = t.status == TournamentStatus.live;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) {
      final colors = sheet.skorx.colors;
      Future<void> run(Future<void> Function() action, String done) async {
        Navigator.pop(sheet);
        await runAction(context, action, success: done);
      }

      final nextHere = slot.next;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(SkorxSpace.xl, 0, SkorxSpace.xl, SkorxSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(court.name.toUpperCase(), style: SkorxType.headline(28, color: colors.text))),
                  SkxPill(slot.status.label, tone: courtTone(slot.status)),
                ],
              ),
              if (m != null) ...[
                const SizedBox(height: SkorxSpace.sm),
                Text('M${m.number} · ${m.roundLabel} · ${t.category(m.categoryId)?.name ?? ''}',
                    style: TextStyle(color: colors.textMuted)),
                const SizedBox(height: 2),
                Text('${m.labelA}  v  ${m.labelB}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ],
              const SizedBox(height: SkorxSpace.lg),
              if (m != null && can.score && live && m.state != MatchState.called)
                SkxButton(
                  key: const Key('openScore'),
                  label: 'Open score',
                  icon: Icons.scoreboard_rounded,
                  onPressed: () {
                    Navigator.pop(sheet);
                    context.push('/org/$orgId/t/${t.id}/match/${m.id}');
                  },
                ),
              if (m != null && can.score && live && m.state == MatchState.called)
                SkxButton(
                  key: const Key('startMatch'),
                  label: 'Start match',
                  icon: Icons.play_arrow_rounded,
                  onPressed: () async {
                    Navigator.pop(sheet);
                    final ok = await runAction(context, () => repo.command(m.id, MatchCommand.start));
                    if (ok && context.mounted) context.push('/org/$orgId/t/${t.id}/match/${m.id}');
                  },
                ),
              if (m == null && nextHere != null && nextHere.ready && can.score && live && court.mode == CourtMode.open)
                SkxButton(
                  label: 'Call M${nextHere.number} to court',
                  icon: Icons.campaign_rounded,
                  onPressed: () => run(() => repo.command(nextHere.id, MatchCommand.call),
                      'M${nextHere.number} called. Players were notified.'),
                ),
              if (m == null && can.schedule && queue.isNotEmpty && court.mode == CourtMode.open) ...[
                const SizedBox(height: SkorxSpace.sm),
                SkxButton.secondary(
                  label: 'Move a match here',
                  icon: Icons.move_down_rounded,
                  onPressed: () async {
                    final chosen = await showModalBottomSheet<TmsMatch>(
                      context: sheet,
                      builder: (pick) => SafeArea(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final q in queue.take(12))
                              ListTile(
                                title: Text('M${q.number} · ${q.labelA} v ${q.labelB}', maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text([q.roundLabel, if (q.scheduledAt != null) time12(q.scheduledAt!)].join(' · ')),
                                onTap: () => Navigator.pop(pick, q),
                              ),
                          ],
                        ),
                      ),
                    );
                    if (chosen != null) await run(() => repo.moveMatch(chosen.id, court.id), 'M${chosen.number} moved to ${court.name}.');
                  },
                ),
              ],
              if (m != null && m.state == MatchState.live && can.score) ...[
                const SizedBox(height: SkorxSpace.sm),
                SkxButton.secondary(
                  label: 'Pause match',
                  icon: Icons.pause_rounded,
                  onPressed: () => run(() => repo.command(m.id, MatchCommand.pause), 'Match paused.'),
                ),
              ],
              if (m != null && m.state == MatchState.called && can.schedule) ...[
                const SizedBox(height: SkorxSpace.sm),
                SkxButton.secondary(
                  label: 'Move to another court',
                  icon: Icons.swap_horiz_rounded,
                  onPressed: () async {
                    Navigator.pop(sheet);
                    await _pickCourtAndMove(context, ref, t, m);
                  },
                ),
              ],
              if (can.schedule && t.can(TmsAction.manageCourts)) ...[
                const SkxSectionTitle('Court', padding: EdgeInsets.only(top: SkorxSpace.xl, bottom: SkorxSpace.sm)),
                Wrap(
                  spacing: SkorxSpace.sm,
                  children: [
                    for (final mode in CourtMode.values)
                      SkxChip(
                        label: mode.label,
                        selected: court.mode == mode,
                        onTap: () async {
                          if (mode == court.mode) return;
                          String? note;
                          if (mode == CourtMode.onBreak) {
                            note = 'Back at ${time12(DateTime.now().add(const Duration(minutes: 15)))}';
                          }
                          await run(() => repo.updateCourt(court.id, mode: mode, note: note), '${court.name}: ${mode.label.toLowerCase()}.');
                        },
                      ),
                  ],
                ),
                const SizedBox(height: SkorxSpace.sm),
                SkxButton.ghost(
                  label: 'Rename court',
                  icon: Icons.edit_rounded,
                  onPressed: () async {
                    final controller = TextEditingController(text: court.name);
                    final name = await showDialog<String>(
                      context: sheet,
                      builder: (d) => AlertDialog(
                        title: const Text('Rename court'),
                        content: TextField(controller: controller, autofocus: true),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(d, controller.text.trim()), child: const Text('Save')),
                        ],
                      ),
                    );
                    controller.dispose();
                    if (name != null && name.isNotEmpty) await run(() => repo.updateCourt(court.id, name: name), 'Renamed.');
                  },
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _pickCourtAndMove(BuildContext context, WidgetRef ref, OrgTournament t, TmsMatch m) async {
  final courts = ref.read(courtsProvider(t.id)).value ?? const <TmsCourt>[];
  final to = await showModalBottomSheet<TmsCourt>(
    context: context,
    builder: (pick) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final c in courts.where((c) => c.id != m.courtId && c.mode == CourtMode.open))
            ListTile(title: Text(c.name), onTap: () => Navigator.pop(pick, c)),
        ],
      ),
    ),
  );
  if (to != null && context.mounted) {
    await runAction(context, () => ref.read(organizerRepositoryProvider).moveMatch(m.id, to.id),
        success: 'M${m.number} moved to ${to.name}. Players were notified.');
  }
}

/// A match from the queue: call it, move it, or open it.
Future<void> showMatchSheet(BuildContext context, WidgetRef ref, String orgId, OrgTournament t, TmsMatch m, List<TmsCourt> courts) {
  final can = orgPermissions(ref, orgId);
  final repo = ref.read(organizerRepositoryProvider);
  final court = courts.where((c) => c.id == m.courtId).firstOrNull;
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheet) {
      final colors = sheet.skorx.colors;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(SkorxSpace.xl, 0, SkorxSpace.xl, SkorxSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('M${m.number} · ${m.roundLabel}'.toUpperCase(), style: SkorxType.headline(24, color: colors.text)),
              const SizedBox(height: SkorxSpace.sm),
              Text('${m.labelA}  v  ${m.labelB}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(
                [court?.name ?? 'No court', if (m.scheduledAt != null) time12(m.scheduledAt!)].join(' · '),
                style: TextStyle(color: colors.textMuted),
              ),
              const SizedBox(height: SkorxSpace.lg),
              if (can.score && m.ready && court != null && t.status == TournamentStatus.live)
                SkxButton(
                  label: 'Call to ${court.name}',
                  icon: Icons.campaign_rounded,
                  onPressed: () async {
                    Navigator.pop(sheet);
                    await runAction(context, () => repo.command(m.id, MatchCommand.call), success: 'Called. Players were notified.');
                  },
                ),
              if (can.schedule) ...[
                const SizedBox(height: SkorxSpace.sm),
                SkxButton.secondary(
                  label: 'Move to another court',
                  icon: Icons.swap_horiz_rounded,
                  onPressed: () async {
                    Navigator.pop(sheet);
                    await _pickCourtAndMove(context, ref, t, m);
                  },
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
