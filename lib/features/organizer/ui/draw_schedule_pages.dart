import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/theme/typography.dart';
import '../../../shared/format.dart';
import '../../../shared/ui/components.dart';
import '../../../sports/core/score_state.dart';
import '../data/draw_engine.dart';
import '../data/organizer_repository.dart';
import '../data/schedule_engine.dart';
import '../data/tms_models.dart';
import 'org_widgets.dart';

/// Standing of one entry in a round robin or pool.
class Standing {
  Standing(this.entryId);

  final String entryId;
  int played = 0;
  int won = 0;
  int pointDiff = 0;

  int get lost => played - won;
}

/// Wins first, then point difference.
List<Standing> standings(List<String> entryIds, Iterable<TmsMatch> matches) {
  final table = {for (final id in entryIds) id: Standing(id)};
  for (final m in matches.where((m) => m.state == MatchState.completed && m.winner != null)) {
    for (final side in Side.values) {
      final s = table[m.entry(side)];
      if (s == null) continue;
      s.played++;
      if (m.winner == side) s.won++;
      for (final g in m.games) {
        s.pointDiff += g.of(side) - g.of(side.opponent);
      }
    }
  }
  return table.values.toList()
    ..sort((a, b) => b.won != a.won ? b.won.compareTo(a.won) : b.pointDiff.compareTo(a.pointDiff));
}

/// Make, check, adjust and publish each category's draw.
class DrawPage extends ConsumerStatefulWidget {
  const DrawPage({super.key, required this.orgId, required this.tournamentId});

  final String orgId;
  final String tournamentId;

  @override
  ConsumerState<DrawPage> createState() => _DrawPageState();
}

class _DrawPageState extends ConsumerState<DrawPage> {
  String? _categoryId;
  var _method = DrawMethod.seeded;
  String? _selected;
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final tAsync = ref.watch(orgTournamentProvider(widget.tournamentId));
    return DetailScaffold(
      title: 'Draws',
      fallback: '/org/${widget.orgId}/t/${widget.tournamentId}',
      body: AsyncBody<OrgTournament>(
        value: tAsync,
        onRetry: () => ref.invalidate(orgTournamentProvider(widget.tournamentId)),
        data: (t) {
          final c = t.category(_categoryId ?? '') ?? t.categories.first;
          return ListView(
            padding: EdgeInsets.only(top: SkorxSpace.sm, bottom: SkorxSpace.xxl + MediaQuery.paddingOf(context).bottom),
            children: [
              SkxChipBar(children: [
                for (final x in t.categories)
                  SkxChip(
                    label: x.title,
                    icon: t.publishedDraws.contains(x.id) ? Icons.visibility_rounded : null,
                    selected: x.id == c.id,
                    onTap: () => setState(() {
                      _categoryId = x.id;
                      _selected = null;
                    }),
                  ),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(SkorxSpace.lg, SkorxSpace.md, SkorxSpace.lg, 0),
                child: _category(t, c),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _category(OrgTournament t, OrgCategory c) {
    final colors = context.skorx.colors;
    final can = orgPermissions(ref, widget.orgId);
    final draw = ref.watch(drawProvider((t.id, c.id)));
    final entries = ref.watch(entriesProvider(t.id)).value ?? const <Entry>[];
    final matches = (ref.watch(tmsMatchesProvider(t.id)).value ?? const <TmsMatch>[]).where((m) => m.categoryId == c.id).toList();
    final approved = entries.where((e) => e.categoryId == c.id && e.inDraw).length;
    final byId = {for (final e in entries) e.id: e};
    final canDraw = (can.editTournaments || can.schedule) && t.can(TmsAction.generateDraw);
    final started = matches.any((m) => m.state.index >= MatchState.called.index && m.state != MatchState.completed) ||
        matches.any((m) => m.state == MatchState.completed && m.games.isNotEmpty);
    final published = t.publishedDraws.contains(c.id);

    return AsyncBody<DrawLayout?>(
      value: draw,
      onRetry: () => ref.invalidate(drawProvider((t.id, c.id))),
      data: (layout) {
        if (layout == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SkxCard(
                padding: const EdgeInsets.all(SkorxSpace.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NO DRAW YET', style: SkorxType.headline(24, color: colors.text)),
                    const SizedBox(height: SkorxSpace.sm),
                    Text(
                      '$approved approved ${approved == 1 ? 'entry' : 'entries'} · ${c.drawFormat.label}. '
                      'Seeded keeps the strongest apart by SkorX rating; random shuffles everyone but the seeds.',
                      style: TextStyle(color: colors.textMuted, height: 1.4),
                    ),
                    const SizedBox(height: SkorxSpace.lg),
                    SkxSegmented<DrawMethod>(
                      segments: [for (final m in DrawMethod.values) (m, m.label)],
                      selected: _method,
                      onChanged: (m) => setState(() => _method = m),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SkorxSpace.lg),
              if (!canDraw)
                Text(
                  t.can(TmsAction.generateDraw) ? 'Your role cannot make draws.' : 'Close registration first, then make the draw.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textMuted),
                )
              else
                SkxButton(
                  key: const Key('generateDraw'),
                  label: 'Generate draw',
                  icon: Icons.auto_awesome_rounded,
                  busy: _busy,
                  onPressed: approved < 2 ? null : () => _generate(t, c, replace: false),
                ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: SkorxSpace.sm,
              runSpacing: SkorxSpace.xs,
              children: [
                SkxPill(published ? 'Published' : 'Not published', tone: published ? SkxTone.success : SkxTone.warning,
                    icon: published ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                SkxPill('${layout.method.label} · ${layout.entries.length} entries'),
                if (started) const SkxPill('Locked', icon: Icons.lock_rounded),
              ],
            ),
            const SizedBox(height: SkorxSpace.md),
            if (!started && canDraw)
              Text(
                _selected == null ? 'Tap two entries to swap them.' : 'Now tap who to swap ${byId[_selected]?.shortName} with.',
                style: TextStyle(color: _selected == null ? colors.textMuted : colors.cyan, fontWeight: FontWeight.w600),
              ),
            const SizedBox(height: SkorxSpace.md),
            if (layout.format == DrawFormat.knockout)
              _Bracket(
                matches: matches,
                allMatches: ref.watch(tmsMatchesProvider(t.id)).value ?? const [],
                selected: _selected,
                onTapEntry: started || !canDraw ? null : (id) => _tap(t, c, id),
              )
            else
              for (final (i, group) in layout.groups.indexed) ...[
                _PoolCard(
                  title: layout.format == DrawFormat.pools ? 'Pool ${String.fromCharCode(65 + i)}' : 'Round robin',
                  rows: standings(group.whereType<String>().toList(), matches),
                  byId: byId,
                  selected: _selected,
                  onTapEntry: started || !canDraw ? null : (id) => _tap(t, c, id),
                ),
                const SizedBox(height: SkorxSpace.md),
              ],
            const SizedBox(height: SkorxSpace.lg),
            if (can.editTournaments && t.can(TmsAction.publishDraw) && !published)
              SkxButton(
                key: const Key('publishDraw'),
                label: 'Publish draw',
                icon: Icons.send_rounded,
                onPressed: () async {
                  final ok = await confirmAction(
                    context,
                    title: 'Publish draw?',
                    message: 'Once published, players will be able to see their matches in the SkorX app.',
                    confirm: 'Publish draw',
                  );
                  if (ok && mounted) {
                    await runAction(context, () => ref.read(organizerRepositoryProvider).publishDraw(t.id, c.id),
                        success: 'Draw published. Players can see it now.');
                  }
                },
              ),
            if (canDraw && !started) ...[
              const SizedBox(height: SkorxSpace.sm),
              Center(
                child: SkxButton.ghost(
                  label: 'Generate again',
                  icon: Icons.refresh_rounded,
                  onPressed: () => _generate(t, c, replace: true),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _generate(OrgTournament t, OrgCategory c, {required bool replace}) async {
    if (replace) {
      final ok = await confirmAction(
        context,
        title: 'Generate the draw again?',
        message: TournamentLifecycle.warning(TournamentStatus.drawGenerated, TmsAction.generateDraw)! +
            (t.publishedDraws.contains(c.id) ? ' Players have seen the current one.' : ''),
        confirm: 'Generate again',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    await runAction(
      context,
      () => ref.read(organizerRepositoryProvider).generateDraw(t.id, c.id, _method),
      success: 'Draw ready. Check it, then publish.',
    );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _tap(OrgTournament t, OrgCategory c, String entryId) async {
    HapticFeedback.selectionClick();
    final first = _selected;
    if (first == null) {
      setState(() => _selected = entryId);
      return;
    }
    setState(() => _selected = null);
    if (first == entryId) return;
    await runAction(
      context,
      () => ref.read(organizerRepositoryProvider).swapInDraw(t.id, c.id, first, entryId),
      success: 'Swapped.',
    );
  }
}

/// The knockout bracket, one column per round, scrolled sideways.
class _Bracket extends StatelessWidget {
  const _Bracket({required this.matches, required this.allMatches, required this.selected, required this.onTapEntry});

  final List<TmsMatch> matches;
  final List<TmsMatch> allMatches;
  final String? selected;
  final ValueChanged<String>? onTapEntry;

  @override
  Widget build(BuildContext context) {
    final rounds = <int, List<TmsMatch>>{};
    for (final m in matches) {
      (rounds[m.round] ??= []).add(m);
    }
    final keys = rounds.keys.toList()..sort();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in keys) ...[
            SizedBox(
              width: 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(rounds[r]!.first.roundLabel.toUpperCase(),
                      style: SkorxType.label(color: context.skorx.colors.textMuted, size: 12)),
                  const SizedBox(height: SkorxSpace.sm),
                  for (final m in rounds[r]!..sort((a, b) => _slotIndex(a).compareTo(_slotIndex(b)))) ...[
                    _BracketMatch(match: m, selected: selected, onTapEntry: r == 1 ? onTapEntry : null),
                    SizedBox(height: SkorxSpace.sm * r.toDouble()),
                  ],
                ],
              ),
            ),
            const SizedBox(width: SkorxSpace.md),
          ],
        ],
      ),
    );
  }
}

/// Position of a knockout match within its round, from its id (`…-r2-3`).
int _slotIndex(TmsMatch m) => int.tryParse(m.id.split('-').last) ?? 0;

class _BracketMatch extends StatelessWidget {
  const _BracketMatch({required this.match, required this.selected, required this.onTapEntry});

  final TmsMatch match;
  final String? selected;
  final ValueChanged<String>? onTapEntry;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final m = match;
    Widget slot(Side s) {
      final id = m.entry(s);
      final won = m.winner == s && m.state == MatchState.completed && !m.isBye;
      final isSelected = id != null && id == selected;
      final row = Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: SkorxSpace.sm),
        decoration: BoxDecoration(
          color: isSelected ? colors.cyan.withValues(alpha: 0.18) : null,
          borderRadius: BorderRadius.circular(SkorxRadius.sm),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                m.label(s),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: won ? FontWeight.w800 : FontWeight.w600,
                  color: id == null ? colors.textMuted : colors.text,
                ),
              ),
            ),
            if (m.games.isNotEmpty) Text(m.games.map((g) => g.of(s)).join(' '), style: SkorxType.score(14, color: colors.textMuted)),
          ],
        ),
      );
      if (id == null || onTapEntry == null) return row;
      return Semantics(
        button: true,
        selected: isSelected,
        label: 'Swap ${m.label(s)}',
        excludeSemantics: true,
        child: InkWell(key: Key('slot-$id'), onTap: () => onTapEntry!(id), child: row),
      );
    }

    return SkxCard(
      padding: const EdgeInsets.all(4),
      radius: SkorxRadius.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!m.isBye)
            Padding(
              padding: const EdgeInsets.fromLTRB(SkorxSpace.sm, 2, SkorxSpace.sm, 0),
              child: Text('M${m.number}', style: SkorxType.label(color: colors.textMuted, size: 10)),
            ),
          slot(Side.a),
          Divider(height: 1, color: colors.border),
          slot(Side.b),
        ],
      ),
    );
  }
}

class _PoolCard extends StatelessWidget {
  const _PoolCard({required this.title, required this.rows, required this.byId, required this.selected, required this.onTapEntry});

  final String title;
  final List<Standing> rows;
  final Map<String, Entry> byId;
  final String? selected;
  final ValueChanged<String>? onTapEntry;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    TextStyle head() => SkorxType.label(color: colors.textMuted, size: 11);
    return SkxCard(
      padding: const EdgeInsets.all(SkorxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title.toUpperCase(), style: SkorxType.headline(20, color: colors.text, weight: FontWeight.w800))),
              SizedBox(width: 32, child: Text('W', textAlign: TextAlign.center, style: head())),
              SizedBox(width: 32, child: Text('L', textAlign: TextAlign.center, style: head())),
              SizedBox(width: 44, child: Text('+/−', textAlign: TextAlign.right, style: head())),
            ],
          ),
          const SizedBox(height: SkorxSpace.sm),
          for (final (i, s) in rows.indexed)
            InkWell(
              key: Key('slot-${s.entryId}'),
              onTap: onTapEntry == null ? null : () => onTapEntry!(s.entryId),
              borderRadius: BorderRadius.circular(SkorxRadius.sm),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: s.entryId == selected ? colors.cyan.withValues(alpha: 0.18) : null,
                  borderRadius: BorderRadius.circular(SkorxRadius.sm),
                ),
                child: Row(
                  children: [
                    SizedBox(width: 20, child: Text('${i + 1}', style: SkorxType.score(15, color: colors.textMuted))),
                    Expanded(
                      child: Text(byId[s.entryId]?.shortName ?? '',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    SizedBox(width: 32, child: Text('${s.won}', textAlign: TextAlign.center, style: SkorxType.score(16))),
                    SizedBox(width: 32, child: Text('${s.lost}', textAlign: TextAlign.center, style: SkorxType.score(16, color: colors.textMuted))),
                    SizedBox(width: 44, child: Text(signed(s.pointDiff), textAlign: TextAlign.right, style: SkorxType.score(16))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Courts, match length, breaks → a timetable nobody is double-booked in.
class SchedulePage extends ConsumerStatefulWidget {
  const SchedulePage({super.key, required this.orgId, required this.tournamentId});

  final String orgId;
  final String tournamentId;

  @override
  ConsumerState<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends ConsumerState<SchedulePage> {
  DateTime? _start;
  var _minutes = 25;
  var _buffer = 5;
  var _break = false;
  var _breakAt = const TimeOfDay(hour: 13, minute: 0);
  Set<String>? _courts;
  String? _courtFilter;
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final can = orgPermissions(ref, widget.orgId);
    final tAsync = ref.watch(orgTournamentProvider(widget.tournamentId));
    final matches = ref.watch(tmsMatchesProvider(widget.tournamentId)).value ?? const <TmsMatch>[];
    final courts = ref.watch(courtsProvider(widget.tournamentId)).value ?? const <TmsCourt>[];
    final courtName = {for (final c in courts) c.id: c.name};

    return DetailScaffold(
      title: 'Schedule',
      fallback: '/org/${widget.orgId}/t/${widget.tournamentId}',
      body: AsyncBody<OrgTournament>(
        value: tAsync,
        onRetry: () => ref.invalidate(orgTournamentProvider(widget.tournamentId)),
        data: (t) {
          final start = _start ?? t.start;
          final chosen = _courts ?? {for (final c in courts) c.id};
          final canPlan = can.schedule && t.can(TmsAction.generateSchedule);
          final timed = matches.where((m) => m.scheduledAt != null).toList()
            ..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
          final shown = timed.where((m) => _courtFilter == null || m.courtId == _courtFilter).toList();
          final ends = timed.isEmpty ? null : timed.map((m) => m.scheduledAt!).reduce((a, b) => a.isAfter(b) ? a : b)
              .add(Duration(minutes: _minutes));

          return ListView(
            padding: EdgeInsets.only(top: SkorxSpace.sm, bottom: SkorxSpace.xxl + MediaQuery.paddingOf(context).bottom),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: SkorxSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TournamentBanner(tournament: t),
                    if (matches.isEmpty)
                      SkxEmpty(
                        icon: Icons.account_tree_rounded,
                        title: 'Make the draws first',
                        message: 'The schedule is built from the draw’s matches.',
                        actionLabel: 'Go to draws',
                        onAction: () => context.pushReplacement('/org/${widget.orgId}/t/${t.id}/draw'),
                      )
                    else if (canPlan)
                      SkxCard(
                        padding: const EdgeInsets.all(SkorxSpace.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SkxCard(
                              padding: const EdgeInsets.all(SkorxSpace.md),
                              color: colors.surfaceMuted,
                              onTap: () async {
                                final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start));
                                if (time != null) {
                                  setState(() => _start = DateTime(start.year, start.month, start.day, time.hour, time.minute));
                                }
                              },
                              child: InfoTile(icon: Icons.play_circle_outline_rounded, label: 'First match', value: '${dayDate(start)}, ${time12(start)}'),
                            ),
                            const SizedBox(height: SkorxSpace.md),
                            Text('MATCH LENGTH', style: SkorxType.label(color: colors.textMuted, size: 11)),
                            const SizedBox(height: 6),
                            SkxSegmented<int>(
                              segments: const [(15, '15m'), (20, '20m'), (25, '25m'), (30, '30m'), (45, '45m')],
                              selected: _minutes,
                              onChanged: (v) => setState(() => _minutes = v),
                            ),
                            const SizedBox(height: SkorxSpace.md),
                            Text('CHANGEOVER AND REST', style: SkorxType.label(color: colors.textMuted, size: 11)),
                            const SizedBox(height: 6),
                            SkxSegmented<int>(
                              segments: const [(0, 'None'), (5, '5m'), (10, '10m'), (15, '15m')],
                              selected: _buffer,
                              onChanged: (v) => setState(() => _buffer = v),
                            ),
                            const SizedBox(height: SkorxSpace.md),
                            Text('COURTS', style: SkorxType.label(color: colors.textMuted, size: 11)),
                            Wrap(
                              spacing: SkorxSpace.sm,
                              children: [
                                for (final c in courts)
                                  SkxChip(
                                    label: c.name,
                                    selected: chosen.contains(c.id),
                                    onTap: () => setState(() {
                                      final next = {...chosen};
                                      if (!next.remove(c.id)) next.add(c.id);
                                      _courts = next;
                                    }),
                                  ),
                              ],
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Lunch break', style: TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(_break ? '${_breakAt.format(context)}, 45 minutes' : 'No matches start during it'),
                              value: _break,
                              onChanged: (v) async {
                                if (v) {
                                  final picked = await showTimePicker(context: context, initialTime: _breakAt);
                                  if (picked != null) _breakAt = picked;
                                }
                                setState(() => _break = v);
                              },
                            ),
                            const SizedBox(height: SkorxSpace.sm),
                            SkxButton(
                              key: const Key('generateSchedule'),
                              label: timed.isEmpty ? 'Generate schedule' : 'Rebuild schedule',
                              icon: Icons.auto_awesome_rounded,
                              busy: _busy,
                              onPressed: chosen.isEmpty ? null : () => _generate(t, start, chosen, courts),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (timed.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(SkorxSpace.lg, SkorxSpace.xl, SkorxSpace.lg, SkorxSpace.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TIMETABLE', style: SkorxType.headline(22, color: colors.text, weight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('${timed.length} matches · ends about ${time12(ends!)}', style: TextStyle(color: colors.textMuted, fontSize: 12.5)),
                    ],
                  ),
                ),
                SkxChipBar(children: [
                  SkxChip(label: 'All courts', selected: _courtFilter == null, onTap: () => setState(() => _courtFilter = null)),
                  for (final c in courts)
                    SkxChip(label: c.name, selected: _courtFilter == c.id, onTap: () => setState(() => _courtFilter = c.id)),
                ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(SkorxSpace.lg, SkorxSpace.sm, SkorxSpace.lg, 0),
                  child: Column(
                    children: [
                      for (final m in shown) ...[
                        TmsMatchRow(
                          match: m,
                          court: courtName[m.courtId],
                          category: t.category(m.categoryId)?.name,
                          now: DateTime.now(),
                        ),
                        const SizedBox(height: SkorxSpace.sm),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _generate(OrgTournament t, DateTime start, Set<String> chosen, List<TmsCourt> courts) async {
    final warning = TournamentLifecycle.warning(t.status, TmsAction.generateSchedule);
    if (warning != null) {
      final ok = await confirmAction(context, title: 'Rebuild the schedule?', message: warning, confirm: 'Rebuild');
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    final breakStart = _break ? DateTime(start.year, start.month, start.day, _breakAt.hour, _breakAt.minute) : null;
    await runAction(
      context,
      () => ref.read(organizerRepositoryProvider).generateSchedule(
            t.id,
            ScheduleSettings(
              start: start,
              courtIds: [for (final c in courts) if (chosen.contains(c.id)) c.id],
              matchMinutes: _minutes,
              bufferMinutes: _buffer,
              breakStart: breakStart,
              breakMinutes: _break ? 45 : 0,
              categoryOrder: [for (final c in t.categories) c.id],
            ),
          ),
      success: 'Schedule ready. Players see their times in the app.',
    );
    if (mounted) setState(() => _busy = false);
  }
}
