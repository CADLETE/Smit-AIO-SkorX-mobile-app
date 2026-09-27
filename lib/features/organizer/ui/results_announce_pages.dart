import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/theme/typography.dart';
import '../../../shared/format.dart';
import '../../../shared/ui/components.dart';
import '../data/organizer_repository.dart';
import '../data/tms_models.dart';
import 'draw_schedule_pages.dart' show standings;
import 'org_widgets.dart';

/// Podium per category, then every finished match.
class ResultsPage extends ConsumerWidget {
  const ResultsPage({super.key, required this.orgId, required this.tournamentId});

  final String orgId;
  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.skorx.colors;
    final tAsync = ref.watch(orgTournamentProvider(tournamentId));
    final matches = ref.watch(tmsMatchesProvider(tournamentId)).value ?? const <TmsMatch>[];
    final entries = ref.watch(entriesProvider(tournamentId)).value ?? const <Entry>[];
    final byId = {for (final e in entries) e.id: e};
    final can = orgPermissions(ref, orgId);

    return DetailScaffold(
      title: 'Results',
      fallback: '/org/$orgId/t/$tournamentId',
      body: AsyncBody<OrgTournament>(
        value: tAsync,
        onRetry: () => ref.invalidate(orgTournamentProvider(tournamentId)),
        data: (t) {
          final done = matches.where((m) => m.state == MatchState.completed).toList()
            ..sort((a, b) => (b.completedAt ?? DateTime(0)).compareTo(a.completedAt ?? DateTime(0)));
          return ListView(
            padding: EdgeInsets.fromLTRB(SkorxSpace.lg, SkorxSpace.sm, SkorxSpace.lg, SkorxSpace.xxl + MediaQuery.paddingOf(context).bottom),
            children: [
              TournamentBanner(tournament: t),
              for (final c in t.categories) ...[
                _Podium(category: c, matches: matches.where((m) => m.categoryId == c.id).toList(), byId: byId),
                const SizedBox(height: SkorxSpace.md),
              ],
              if (t.status == TournamentStatus.completed)
                SkxCard(
                  padding: const EdgeInsets.all(SkorxSpace.lg),
                  child: Row(
                    children: [
                      Icon(Icons.workspace_premium_rounded, color: colors.limeText),
                      const SizedBox(width: SkorxSpace.md),
                      Expanded(
                        child: Text(
                          'Winner, runner-up and participation certificates go to every player\'s SkorX profile with their achievement badge.',
                          style: TextStyle(color: colors.textMuted, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              SkxSectionTitle('${done.length} matches final'),
              if (done.isEmpty)
                const SkxEmpty(compact: true, icon: Icons.sports_score_rounded, title: 'No results yet', message: 'Confirmed scores show here straight away.'),
              for (final m in done) ...[
                TmsMatchRow(
                  match: m,
                  category: t.category(m.categoryId)?.name,
                  onTap: can.score && (t.status == TournamentStatus.live || t.can(TmsAction.correctResults))
                      ? () => context.push('/org/$orgId/t/${t.id}/match/${m.id}')
                      : null,
                ),
                const SizedBox(height: SkorxSpace.sm),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.category, required this.matches, required this.byId});

  final OrgCategory category;
  final List<TmsMatch> matches;
  final Map<String, Entry> byId;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final c = category;
    String? name(String? id) => id == null ? null : byId[id]?.name;

    List<(String, String?, Color)> places;
    var decided = false;
    if (c.drawFormat == DrawFormat.knockout && matches.isNotEmpty) {
      final last = matches.map((m) => m.round).reduce((a, b) => a > b ? a : b);
      final finalMatch = matches.where((m) => m.round == last).firstOrNull;
      final semis = matches.where((m) => m.round == last - 1).toList();
      decided = finalMatch?.state == MatchState.completed;
      final w = finalMatch?.winner;
      places = [
        ('Winner', decided ? name(finalMatch!.entry(w!)) : null, colors.lime),
        ('Runner-up', decided ? name(finalMatch!.entry(w!.opponent)) : null, colors.cyan),
        for (final s in semis)
          ('Semi-finalist', s.state == MatchState.completed && s.winner != null ? name(s.entry(s.winner!.opponent)) : null, colors.textMuted),
      ];
    } else {
      final ids = {for (final m in matches) ...[m.entryA, m.entryB]}.whereType<String>().toList();
      final table = standings(ids, matches);
      decided = matches.isNotEmpty && matches.every((m) => m.state == MatchState.completed);
      places = [
        for (final (i, s) in table.take(3).indexed)
          (['Winner', 'Runner-up', 'Third'][i], s.played == 0 ? null : '${name(s.entryId)} · ${s.won}W', [colors.lime, colors.cyan, colors.textMuted][i]),
      ];
    }

    return SkxCard(
      padding: const EdgeInsets.all(SkorxSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(c.title.toUpperCase(), style: SkorxType.headline(20, color: colors.text, weight: FontWeight.w800))),
              SkxPill(decided ? 'Final' : 'In progress', tone: decided ? SkxTone.brand : SkxTone.neutral),
            ],
          ),
          const SizedBox(height: SkorxSpace.md),
          for (final (label, who, color) in places)
            Padding(
              padding: const EdgeInsets.only(bottom: SkorxSpace.sm),
              child: Row(
                children: [
                  Icon(label == 'Winner' ? Icons.emoji_events_rounded : Icons.military_tech_rounded, color: color, size: 20),
                  const SizedBox(width: SkorxSpace.sm),
                  SizedBox(width: 104, child: Text(label, style: TextStyle(color: colors.textMuted, fontSize: 13))),
                  Expanded(
                    child: Text(who ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w800, color: who == null ? colors.textMuted : colors.text)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Message players: everyone, a category, a court or one player. Templates
/// cover the messages sent on every tournament day.
class AnnouncePage extends ConsumerStatefulWidget {
  const AnnouncePage({super.key, required this.orgId, required this.tournamentId, this.kind, this.player});

  final String orgId;
  final String tournamentId;
  final String? kind;

  /// Prefills a message to one player, e.g. from their registration.
  final String? player;

  @override
  ConsumerState<AnnouncePage> createState() => _AnnouncePageState();
}

class _AnnouncePageState extends ConsumerState<AnnouncePage> {
  late var _kind = AnnouncementKind.values.asNameMap()[widget.kind] ?? AnnouncementKind.general;
  late var _audience = widget.player == null ? Audience.everyone : Audience.player;
  String? _target;
  var _push = true;
  var _sending = false;
  late final _message = TextEditingController(text: _templateFor(_kind));
  late final _player = TextEditingController(text: widget.player ?? '');

  static String _templateFor(AnnouncementKind k) => switch (k) {
        AnnouncementKind.delay => 'Matches are running 15 minutes late. Stay close to your court.',
        AnnouncementKind.match => 'Your match is starting in 10 minutes.',
        AnnouncementKind.court => 'Please report to Court 3.',
        AnnouncementKind.schedule => 'The schedule has changed. Check your new match time in the app.',
        AnnouncementKind.emergency => '',
        AnnouncementKind.general => '',
      };

  @override
  void dispose() {
    _message.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _send(OrgTournament t) async {
    final text = _message.text.trim();
    if (text.isEmpty) {
      showSkxToast(context, 'Write the message first.', icon: Icons.error_outline_rounded);
      return;
    }
    final who = switch (_audience) {
      Audience.everyone => 'every registered player',
      Audience.category => 'players in ${t.category(_target ?? '')?.title ?? 'the category'}',
      Audience.court => 'players on the court',
      Audience.player => _player.text.trim(),
    };
    final ok = await confirmAction(
      context,
      title: _kind == AnnouncementKind.emergency ? 'Send emergency notice?' : 'Send announcement?',
      message: 'This goes to $who${_push ? ' as a push notification and' : ''} in the SkorX app now.',
      confirm: 'Send',
      destructive: _kind == AnnouncementKind.emergency,
    );
    if (!ok || !mounted) return;
    setState(() => _sending = true);
    final sent = await runAction(context, () async {
      final a = await ref.read(organizerRepositoryProvider).announce(
            t.id,
            kind: _kind,
            audience: _audience,
            message: text,
            target: _audience == Audience.player ? _player.text.trim() : _target,
            push: _push,
          );
      if (mounted) showSkxToast(context, 'Sent to ${a.recipients} ${a.recipients == 1 ? 'player' : 'players'}.');
    });
    if (!mounted) return;
    setState(() => _sending = false);
    if (sent) _message.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final tAsync = ref.watch(orgTournamentProvider(widget.tournamentId));
    final history = ref.watch(announcementsProvider(widget.tournamentId));
    final courts = ref.watch(courtsProvider(widget.tournamentId)).value ?? const <TmsCourt>[];
    final can = orgPermissions(ref, widget.orgId);

    return DetailScaffold(
      title: 'Announce',
      fallback: '/org/${widget.orgId}/t/${widget.tournamentId}',
      body: !can.announce
          ? const NoAccess(what: 'send announcements')
          : AsyncBody<OrgTournament>(
              value: tAsync,
              onRetry: () => ref.invalidate(orgTournamentProvider(widget.tournamentId)),
              data: (t) => ListView(
                padding: EdgeInsets.fromLTRB(SkorxSpace.lg, SkorxSpace.sm, SkorxSpace.lg, SkorxSpace.xxl + MediaQuery.paddingOf(context).bottom),
                children: [
                  TournamentBanner(tournament: t),
                  Text('TYPE', style: SkorxType.label(color: colors.textMuted, size: 12)),
                  Wrap(
                    spacing: SkorxSpace.sm,
                    children: [
                      for (final k in AnnouncementKind.values)
                        SkxChip(
                          label: k.label,
                          icon: k == AnnouncementKind.emergency ? Icons.warning_amber_rounded : null,
                          selected: _kind == k,
                          onTap: () => setState(() {
                            _kind = k;
                            final template = _templateFor(k);
                            if (template.isNotEmpty) _message.text = template;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: SkorxSpace.lg),
                  Text('TO', style: SkorxType.label(color: colors.textMuted, size: 12)),
                  Wrap(
                    spacing: SkorxSpace.sm,
                    children: [
                      for (final a in Audience.values)
                        SkxChip(label: a.label, selected: _audience == a, onTap: () => setState(() {
                              _audience = a;
                              _target = null;
                            })),
                    ],
                  ),
                  if (_audience == Audience.category)
                    Wrap(spacing: SkorxSpace.sm, children: [
                      for (final c in t.categories)
                        SkxChip(label: c.title, selected: _target == c.id, onTap: () => setState(() => _target = c.id)),
                    ]),
                  if (_audience == Audience.court)
                    Wrap(spacing: SkorxSpace.sm, children: [
                      for (final c in courts) SkxChip(label: c.name, selected: _target == c.id, onTap: () => setState(() => _target = c.id)),
                    ]),
                  if (_audience == Audience.player) ...[
                    const SizedBox(height: SkorxSpace.sm),
                    TextField(controller: _player, decoration: const InputDecoration(hintText: 'Player name')),
                  ],
                  const SizedBox(height: SkorxSpace.lg),
                  TextField(
                    key: const Key('announcementText'),
                    controller: _message,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 280,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'What do players need to know?'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Push notification', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Always shown in the app inbox too. WhatsApp and SMS arrive with integrations.'),
                    value: _push,
                    onChanged: (v) => setState(() => _push = v),
                  ),
                  const SizedBox(height: SkorxSpace.sm),
                  SkxButton(
                    key: const Key('sendAnnouncement'),
                    label: 'Send',
                    icon: Icons.send_rounded,
                    busy: _sending,
                    onPressed: (_audience == Audience.category || _audience == Audience.court) && _target == null ? null : () => _send(t),
                  ),
                  const SkxSectionTitle('Sent'),
                  AsyncBody<List<Announcement>>(
                    value: history,
                    onRetry: () => ref.invalidate(announcementsProvider(widget.tournamentId)),
                    data: (list) => list.isEmpty
                        ? const SkxEmpty(compact: true, icon: Icons.campaign_outlined, title: 'Nothing sent yet')
                        : Column(children: [
                            for (final a in list) ...[
                              SkxCard(
                                padding: const EdgeInsets.all(SkorxSpace.md),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      SkxPill(a.kind.label,
                                          tone: a.kind == AnnouncementKind.emergency
                                              ? SkxTone.live
                                              : a.kind == AnnouncementKind.delay
                                                  ? SkxTone.warning
                                                  : SkxTone.info),
                                      const SizedBox(width: SkorxSpace.sm),
                                      Expanded(
                                        child: Text('${a.targetLabel ?? a.audience.label} · ${a.recipients} players',
                                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.textMuted, fontSize: 12)),
                                      ),
                                    ]),
                                    const SizedBox(height: SkorxSpace.sm),
                                    Text(a.message, style: const TextStyle(height: 1.35)),
                                    const SizedBox(height: SkorxSpace.xs),
                                    Text('${a.sentBy} · ${timeAgo(a.sentAt, DateTime.now())}',
                                        style: TextStyle(color: colors.textMuted, fontSize: 12)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: SkorxSpace.sm),
                            ],
                          ]),
                  ),
                ],
              ),
            ),
    );
  }
}
