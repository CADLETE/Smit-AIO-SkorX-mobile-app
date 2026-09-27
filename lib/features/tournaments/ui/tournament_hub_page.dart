import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../../matches/data/journey.dart';
import '../../matches/data/match.dart';
import '../../matches/data/match_repository.dart';
import '../data/tournaments.dart';
import 'tournament_banner.dart';
import 'tournament_widgets.dart';

enum HubView {
  journey('My journey'),
  matches('Matches'),
  standings('Standings'),
  about('About');

  const HubView(this.label);
  final String label;
}

/// One tournament. The first question it answers is "where am I in it?";
/// a player who is not in it lands on About, where the one action is
/// Register.
class TournamentHubPage extends ConsumerStatefulWidget {
  const TournamentHubPage({super.key, required this.tournamentId, this.view});

  final String tournamentId;
  final String? view;

  @override
  ConsumerState<TournamentHubPage> createState() => _TournamentHubPageState();
}

class _TournamentHubPageState extends ConsumerState<TournamentHubPage> {
  late HubView? _view = HubView.values.asNameMap()[widget.view];

  @override
  void didUpdateWidget(TournamentHubPage old) {
    super.didUpdateWidget(old);
    if (old.view != widget.view) _view = HubView.values.asNameMap()[widget.view];
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(tournamentDetailProvider(widget.tournamentId));
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SxWidth(
          child: switch (detail) {
            AsyncData(:final value) => _hub(context, value),
            AsyncError(:final error) => Column(
                children: [
                  SxBackBar(onBack: () => _back(context)),
                  EmptyBlock(
                    icon: Icons.search_off_rounded,
                    title: 'Not available',
                    message: error is ApiException ? error.message : 'This tournament did not load.',
                    action: SxButton.secondary(
                      label: 'Try again',
                      expand: false,
                      onPressed: () => ref.invalidate(tournamentDetailProvider(widget.tournamentId)),
                    ),
                  ),
                ],
              ),
            _ => Column(
                children: [
                  SxBackBar(onBack: () => _back(context)),
                  const Padding(padding: EdgeInsets.all(Sx.gutter), child: SkeletonList(rows: 4, rowHeight: 90)),
                ],
              ),
          },
        ),
      ),
    );
  }

  void _back(BuildContext context) => context.canPop() ? context.pop() : context.go('/player/explore');

  Widget _hub(BuildContext context, TournamentDetail detail) {
    final c = context.sx;
    final t = detail.tournament;
    final registered = detail.myRegistration != null;
    final now = DateTime.now();
    final journey = registered ? ref.watch(journeyProvider(t.id)).value : null;
    final views = [if (registered) HubView.journey, HubView.matches, HubView.standings, HubView.about];
    final view = views.contains(_view) ? _view! : views.first == HubView.journey ? HubView.journey : HubView.about;
    final (state, word) = tournamentState(t, now, registered: registered);
    final window = t.window(now);
    final canRegister = !registered && (window == RegistrationWindow.open || window == RegistrationWindow.closingSoon);

    return Column(
      children: [
        SxBackBar(title: 'Tournament', onBack: () => _back(context)),
        Expanded(
          child: NestedScrollView(
            headerSliverBuilder: (_, _) => [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s4, Sx.gutter, Sx.s20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TournamentBanner.of(t, height: 132),
                      const SizedBox(height: Sx.s16),
                      StateMark(state, word: word, size: 13),
                      const SizedBox(height: Sx.s12),
                      Semantics(header: true, child: Text(t.name.toUpperCase(), style: SxType.title(c.ink, size: 34))),
                      const SizedBox(height: Sx.s8),
                      Text('${dateRange(t.start, t.end)} · ${t.venue}, ${t.city}', style: SxType.body(c.inkMuted, size: 14)),
                      if (journey != null) ...[
                        const SizedBox(height: Sx.s16),
                        Row(
                          children: [
                            Container(width: 3, height: 20, color: c.voltFill),
                            const SizedBox(width: Sx.s8),
                            Expanded(
                              child: Text(journey.headline.toUpperCase(),
                                  key: const Key('journeyHeadline'), style: SxType.label(c.ink, size: 15)),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabsHeader(
                  color: c.canvas,
                  child: SxTabs<HubView>(
                    tabs: [for (final v in views) (v, v.label, null)],
                    selected: view,
                    onSelect: (v) => setState(() => _view = v),
                  ),
                ),
              ),
            ],
            body: switch (view) {
              HubView.journey => _JourneyView(tournament: t, registration: detail.myRegistration!),
              HubView.matches => _MatchesView(tournamentId: t.id),
              HubView.standings => _StandingsView(tournamentId: t.id),
              HubView.about => _AboutView(tournament: t, registration: detail.myRegistration),
            },
          ),
        ),
        if (canRegister && view == HubView.about)
          _RegisterBar(tournament: t),
      ],
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  _TabsHeader({required this.child, required this.color});

  final Widget child;
  final Color color;

  @override
  double get minExtent => 47;
  @override
  double get maxExtent => 47;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      ColoredBox(color: color, child: child);

  @override
  bool shouldRebuild(_TabsHeader old) => old.child != child || old.color != color;
}

EdgeInsets _viewPadding(BuildContext context) =>
    EdgeInsets.fromLTRB(Sx.gutter, Sx.s24, Sx.gutter, Sx.s48 + MediaQuery.paddingOf(context).bottom);

class _JourneyView extends ConsumerWidget {
  const _JourneyView({required this.tournament, required this.registration});

  final Tournament tournament;
  final Registration registration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final journey = ref.watch(journeyProvider(tournament.id));
    return ListView(
      padding: _viewPadding(context),
      children: [
        Text(
          [registration.categoryName, if (registration.partner != null) 'with ${registration.partner}'].join(' · '),
          style: SxType.caption(c.inkMuted),
        ),
        const SizedBox(height: Sx.s16),
        switch (journey) {
          AsyncData(:final value?) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                JourneyRail(
                  key: const Key('journeyRail'),
                  journey: value,
                  onOpenMatch: (id) => context.push('/player/matches/$id'),
                ),
                if (value.current?.match case final m? when m.isLive) ...[
                  const SizedBox(height: Sx.s16),
                  SxButton(label: 'View live match', onPressed: () => context.push('/player/matches/${m.id}')),
                ],
                if (value.won + value.lost > 0) ...[
                  const SizedBox(height: Sx.s32),
                  SxSection('In this tournament'),
                  Row(
                    children: [
                      Expanded(child: Stat(value: '${value.won + value.lost}', label: 'Played')),
                      Expanded(child: Stat(value: '${value.won}', label: 'Won', color: c.volt)),
                      Expanded(child: Stat(value: '${value.lost}', label: 'Lost')),
                    ],
                  ),
                ],
              ],
            ),
          AsyncError() => ErrorBlock(
              message: 'Your journey did not load.',
              onRetry: () => ref.invalidate(journeyProvider(tournament.id)),
            ),
          _ => const SkeletonList(rows: 5, rowHeight: 48),
        },
      ],
    );
  }
}

class _MatchesView extends ConsumerWidget {
  const _MatchesView({required this.tournamentId});

  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final matches = ref.watch(tournamentMatchesProvider(tournamentId));
    return switch (matches) {
      AsyncData(:final value) when value.isEmpty => ListView(
          padding: _viewPadding(context),
          children: const [
            EmptyBlock(
              icon: Icons.account_tree_outlined,
              title: 'Draw not out yet',
              message: 'Matches appear here once the organiser publishes the draw, usually two days before play.',
            ),
          ],
        ),
      AsyncData(:final value) => ListView(
          padding: _viewPadding(context),
          children: [
            for (final (group, list) in _byRound(value)) ...[
              SxSection(group, padding: const EdgeInsets.only(top: Sx.s8, bottom: Sx.s4)),
              for (final (i, m) in list.indexed) ...[
                if (i > 0) Divider(height: 1, color: c.line),
                MatchRow(match: m, showContext: false, onTap: () => context.push('/player/matches/${m.id}')),
              ],
              const SizedBox(height: Sx.s24),
            ],
          ],
        ),
      AsyncError() => ListView(
          padding: _viewPadding(context),
          children: [
            ErrorBlock(message: 'Matches did not load.', onRetry: () => ref.invalidate(tournamentMatchesProvider(tournamentId))),
          ],
        ),
      _ => ListView(padding: _viewPadding(context), children: const [SkeletonList()]),
    };
  }

  /// Pools first, then knockout rounds, each in playing order.
  static List<(String, List<Match>)> _byRound(List<Match> matches) {
    final groups = <String, List<Match>>{};
    for (final m in matches) {
      final key = m.tournament?.pool ?? m.tournament?.round ?? 'Matches';
      groups.putIfAbsent(key, () => []).add(m);
    }
    return [for (final e in groups.entries) (e.key, e.value)];
  }
}

class _StandingsView extends ConsumerWidget {
  const _StandingsView({required this.tournamentId});

  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tables = ref.watch(tournamentMatchesProvider(tournamentId)).whenData(computeStandings);
    return ListView(
      padding: _viewPadding(context),
      children: [
        switch (tables) {
          AsyncData(:final value) when value.isEmpty => const EmptyBlock(
              icon: Icons.table_rows_outlined,
              title: 'No standings yet',
              message: 'Pool tables fill in as matches finish.',
            ),
          AsyncData(:final value) => Column(
              children: [for (final t in value) _PoolTableView(table: t)],
            ),
          _ => const SkeletonList(),
        },
      ],
    );
  }
}

class _PoolTableView extends StatelessWidget {
  const _PoolTableView({required this.table});

  final PoolTable table;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    Widget num(String v, {Color? color, double w = 34}) =>
        SizedBox(width: w, child: Text(v, textAlign: TextAlign.right, style: SxType.number(16, color ?? c.ink)));
    Widget head(String v, {double w = 34}) =>
        SizedBox(width: w, child: Text(v, textAlign: TextAlign.right, style: SxType.label(c.inkFaint, size: 11)));
    return Padding(
      padding: const EdgeInsets.only(bottom: Sx.s32),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: SxSection(table.pool, padding: EdgeInsets.zero)),
              head('P'),
              head('W'),
              head('L'),
              head('+/−', w: 44),
            ],
          ),
          const SizedBox(height: Sx.s8),
          for (final (i, r) in table.rows.indexed) ...[
            Divider(height: 1, color: c.line),
            Semantics(
              label: '${i + 1}, ${r.team}, played ${r.played}, won ${r.won}, lost ${r.lost}, point difference ${r.pointDiff}',
              excludeSemantics: true,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  border: r.isMe ? Border(left: BorderSide(color: c.voltFill, width: 3)) : null,
                ),
                padding: EdgeInsets.only(left: r.isMe ? Sx.s8 : 0),
                child: Row(
                  children: [
                    SizedBox(width: 24, child: Text('${i + 1}', style: SxType.number(16, c.inkMuted))),
                    Expanded(
                      child: Text(
                        r.team,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SxType.body(c.ink, size: 15).copyWith(fontWeight: r.isMe ? FontWeight.w700 : FontWeight.w400),
                      ),
                    ),
                    num('${r.played}'),
                    num('${r.won}', color: r.won > 0 ? c.ink : c.inkFaint),
                    num('${r.lost}', color: c.inkMuted),
                    num(signed(r.pointDiff), w: 44, color: c.inkMuted),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AboutView extends StatelessWidget {
  const _AboutView({required this.tournament, required this.registration});

  final Tournament tournament;
  final Registration? registration;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final t = tournament;
    final now = DateTime.now();
    return ListView(
      padding: _viewPadding(context),
      children: [
        if (registration != null) ...[
          SxBlock(
            child: Row(
              children: [
                const StateGlyph(SxState.registered, size: 12),
                const SizedBox(width: Sx.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("You're registered", style: SxType.heading(c.ink, size: 16)),
                      Text(
                        [registration!.categoryName, if (registration!.partner != null) 'with ${registration!.partner}'].join(' · '),
                        style: SxType.caption(c.inkMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Sx.section),
        ],
        SxRows(
          children: [
            SxRow(label: 'Dates', value: dateRange(t.start, t.end)),
            SxRow(label: 'Venue', value: t.venue, subtitle: t.address),
            SxRow(label: 'Entry', value: t.minFee == 0 ? 'Free' : 'from ${formatInr(t.minFee)}'),
            if (t.phase(now) == TournamentPhase.upcoming)
              SxRow(label: 'Entries close', value: '${dayDate(t.registrationDeadline)} · ${time12(t.registrationDeadline)}'),
            SxRow(label: 'Format', value: t.format),
            if (t.prizePool != null) SxRow(label: 'Prize pool', value: formatInr(t.prizePool!)),
          ],
        ),
        const SizedBox(height: Sx.section),
        const SxSection('Categories'),
        for (final cat in t.categories) _CategoryLine(category: cat),
        if (t.schedule.isNotEmpty) ...[
          const SizedBox(height: Sx.section),
          SxRows(
            title: 'Schedule',
            children: [
              for (final (at, what) in t.schedule) SxRow(label: what, value: '${dayDate(at)} · ${timeShort(at)}'),
            ],
          ),
        ],
        if (t.rules.isNotEmpty) ...[
          const SizedBox(height: Sx.section),
          const SxSection('Rules'),
          for (final r in t.rules)
            Padding(
              padding: const EdgeInsets.only(bottom: Sx.s8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, right: Sx.s12),
                    child: Container(width: 5, height: 5, color: c.inkMuted),
                  ),
                  Expanded(child: Text(r, style: SxType.body(c.ink, size: 14))),
                ],
              ),
            ),
        ],
        const SizedBox(height: Sx.section),
        SxRows(
          title: 'Organiser',
          children: [
            SxRow(
              label: t.organizer,
              icon: Icons.shield_outlined,
              trailing: t.organizerVerified ? Icon(Icons.verified_rounded, color: c.info, size: 20) : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _CategoryLine extends StatelessWidget {
  const _CategoryLine({required this.category});

  final TournamentCategory category;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final cat = category;
    final left = cat.spotsLeft;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Sx.s12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${cat.name} · ${cat.level}', style: SxType.heading(c.ink, size: 15)),
                const SizedBox(height: 2),
                Text(
                  cat.full ? 'Full' : left <= 8 ? '$left spots left' : '${cat.registered} of ${cat.capacity} entered',
                  style: SxType.caption(cat.full ? c.inkFaint : left <= 8 ? c.caution : c.inkMuted),
                ),
              ],
            ),
          ),
          Text(formatInr(cat.fee), style: SxType.heading(c.ink, size: 15)),
        ],
      ),
    );
  }
}

class _RegisterBar extends StatelessWidget {
  const _RegisterBar({required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      padding: EdgeInsets.fromLTRB(Sx.gutter, Sx.s12, Sx.gutter, Sx.s12 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(color: c.canvas, border: Border(top: BorderSide(color: c.line))),
      child: SxButton(
        key: const Key('registerNow'),
        label: tournament.minFee == 0 ? 'Register · free' : 'Register · from ${formatInr(tournament.minFee)}',
        onPressed: () => showSxSheet<void>(context, builder: (_) => RegisterSheet(tournament: tournament)),
      ),
    );
  }
}

/// Category, partner, pay. Three decisions, one sheet.
class RegisterSheet extends ConsumerStatefulWidget {
  const RegisterSheet({super.key, required this.tournament});

  final Tournament tournament;

  @override
  ConsumerState<RegisterSheet> createState() => _RegisterSheetState();
}

class _RegisterSheetState extends ConsumerState<RegisterSheet> {
  late TournamentCategory? _category = widget.tournament.categories.where((c) => !c.full).firstOrNull;
  final _partner = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _partner.dispose();
    super.dispose();
  }

  bool get _ready =>
      _category != null && (!_category!.needsPartner || _partner.text.trim().length >= 2);

  Future<void> _confirm() async {
    final cat = _category;
    if (cat == null || !_ready) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(tournamentRepositoryProvider).register(
            widget.tournament.id,
            cat.id,
            partner: cat.needsPartner ? _partner.text.trim() : null,
          );
      ref.invalidate(tournamentDetailProvider(widget.tournament.id));
      ref.invalidate(myTournamentsProvider);
      ref.invalidate(journeyProvider(widget.tournament.id));
      if (!mounted) return;
      Navigator.of(context).pop();
      GoRouter.of(context).push('/player/tournament/${widget.tournament.id}/registered');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Registration did not go through. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final t = widget.tournament;
    return Padding(
      padding: EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('REGISTER', style: SxType.title(c.ink, size: 28)),
            Text(t.name, style: SxType.caption(c.inkMuted)),
            const SizedBox(height: Sx.s24),
            const SxSection('1 · Category'),
            for (final cat in t.categories)
              Semantics(
                button: true,
                selected: cat == _category,
                enabled: !cat.full,
                label: '${cat.name} ${cat.level}, ${formatInr(cat.fee)}${cat.full ? ', full' : ''}',
                excludeSemantics: true,
                child: Tappable(
                  onTap: cat.full ? null : () => setState(() => _category = cat),
                  radius: Sx.radius,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: Sx.s8),
                    padding: const EdgeInsets.all(Sx.s16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Sx.radius),
                      border: Border.all(color: cat == _category ? c.ink : c.line, width: cat == _category ? 1.5 : 1),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${cat.name} · ${cat.level}',
                            style: SxType.heading(cat.full ? c.inkFaint : c.ink, size: 15),
                          ),
                        ),
                        Text(cat.full ? 'Full' : formatInr(cat.fee), style: SxType.heading(cat.full ? c.inkFaint : c.ink, size: 15)),
                      ],
                    ),
                  ),
                ),
              ),
            if (_category?.needsPartner ?? false) ...[
              const SizedBox(height: Sx.s16),
              const SxSection('2 · Partner'),
              TextField(
                key: const Key('partnerField'),
                controller: _partner,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: "Your partner's name"),
                onChanged: (_) => setState(() {}),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: Sx.s16),
              Text(_error!, style: SxType.body(c.live, size: 14)),
            ],
            const SizedBox(height: Sx.s24),
            SxButton(
              key: const Key('confirmRegistration'),
              label: _category == null ? 'Pick a category' : 'Confirm & pay ${formatInr(_category!.fee)}',
              busy: _busy,
              onPressed: _ready ? _confirm : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// After registering: you're in, and where to look next.
class RegisteredPage extends ConsumerWidget {
  const RegisteredPage({super.key, required this.tournamentId});

  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final detail = ref.watch(tournamentDetailProvider(tournamentId)).value;
    final reg = detail?.myRegistration;
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Padding(
            padding: const EdgeInsets.all(Sx.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                const StateMark(SxState.registered, size: 14),
                const SizedBox(height: Sx.s16),
                Text("YOU'RE IN", style: SxType.hero(72, c.ink)),
                const SizedBox(height: Sx.s12),
                Text(detail?.tournament.name ?? '', style: SxType.heading(c.ink, size: 18)),
                if (reg != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    [reg.categoryName, if (reg.partner != null) 'with ${reg.partner}', 'Paid ${formatInr(reg.amountPaid)}'].join(' · '),
                    style: SxType.body(c.inkMuted, size: 14),
                  ),
                ],
                const SizedBox(height: Sx.s24),
                const SizedBox(height: 8, child: NetLine()),
                const SizedBox(height: Sx.s24),
                Text(
                  'Your journey starts now. The draw comes out two days before play; your matches will appear in My Matches.',
                  style: SxType.body(c.inkMuted),
                ),
                const Spacer(),
                SxButton(
                  key: const Key('viewMyRegistration'),
                  label: 'See my journey',
                  onPressed: () => context.pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
