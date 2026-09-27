import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../../player/data/player_repository.dart' show PlayCategory;
import '../../tournaments/data/tournaments.dart' show PlaceFilter;
import '../data/match.dart';
import '../data/match_feed.dart';
import 'filter_widgets.dart';

/// The Matches filters, one sheet: location, match type, casual or
/// tournament, tournament, date, status. Every change applies at once.
class MatchFilterSheet extends ConsumerStatefulWidget {
  const MatchFilterSheet({super.key});

  @override
  ConsumerState<MatchFilterSheet> createState() => _MatchFilterSheetState();
}

class _MatchFilterSheetState extends ConsumerState<MatchFilterSheet> {
  String _tournamentText = '';

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final q = ref.watch(matchQueryProvider);
    final ctl = ref.read(matchQueryProvider.notifier);
    final options = ref.watch(matchPlaceOptionsProvider);
    final venues = [
      for (final v in ref.watch(matchPlacesProvider).value ?? const <VenueOption>[])
        if (q.place.includes(country: v.place.country, region: v.place.region, city: v.place.city)) v.venue,
    ];
    // Tournaments in the chosen place, whatever the other filters say.
    final tournaments = ref.watch(tournamentActivityProvider(MatchQuery(place: q.place))).value ?? const [];
    final t = _tournamentText.trim().toLowerCase();
    final shown = tournaments.where((x) => t.isEmpty || x.name.toLowerCase().contains(t) || x.id.toLowerCase().contains(t)).take(8);

    return SingleChildScrollView(
      key: const Key('matchFilterSheet'),
      padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('FILTER MATCHES', style: SxType.title(c.ink, size: 28)),
          const SizedBox(height: Sx.s24),
          const SxSection('Location'),
          PlacePicker(
            options: options,
            value: q.place,
            onChanged: (p) => ctl.update((q) => q.copyWith(place: p, venue: () => null)),
            venues: venues,
            venue: q.venue,
            onVenue: (v) => ctl.update((q) => q.copyWith(venue: () => v)),
          ),
          const SizedBox(height: Sx.s24),
          FilterGroup(title: 'Match type', children: [
            for (final f in PlayCategory.values)
              SxChip(
                key: Key('format-${f.name}'),
                label: f == PlayCategory.mixed ? 'Mixed doubles' : f.label,
                selected: q.formats.contains(f),
                onTap: () => ctl.update((q) => q.copyWith(formats: toggled(q.formats, f))),
              ),
          ]),
          FilterGroup(title: 'Casual or tournament', children: [
            SxChip(label: 'Both', selected: q.category == null, onTap: () => ctl.update((q) => q.copyWith(category: () => null))),
            for (final k in MatchCategory.values)
              SxChip(
                key: Key('category-${k.name}'),
                label: k.label,
                selected: q.category == k,
                onTap: () => ctl.update((q) => q.copyWith(category: () => k)),
              ),
          ]),
          const SxSection('Tournament'),
          TextField(
            key: const Key('tournamentFilterSearch'),
            onChanged: (v) => setState(() => _tournamentText = v),
            decoration: InputDecoration(
              hintText: 'Tournament name or ID',
              prefixIcon: Icon(Icons.emoji_events_outlined, color: c.inkMuted),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: Sx.s12),
          Wrap(
            spacing: Sx.s8,
            runSpacing: Sx.s8,
            children: [
              SxChip(label: 'Any', selected: q.tournamentId == null, onTap: () => ctl.update((q) => q.copyWith(tournament: () => null))),
              for (final x in shown)
                SxChip(
                  key: Key('tournament-${x.id}'),
                  label: x.name,
                  selected: q.tournamentId == x.id,
                  onTap: () => ctl.update((q) => q.copyWith(tournament: () => (x.id, x.name), category: () => null)),
                ),
              if (shown.isEmpty) Text('No tournaments match "$_tournamentText".', style: SxType.caption(c.inkMuted)),
            ],
          ),
          const SizedBox(height: Sx.s24),
          FilterGroup(title: 'Date', children: [
            for (final w in MatchWhen.values)
              SxChip(
                key: Key('when-${w.name}'),
                label: w == MatchWhen.day && q.when == MatchWhen.day && q.day != null ? dayDate(q.day!) : w.label,
                icon: w == MatchWhen.day ? Icons.calendar_today_rounded : null,
                selected: q.when == w,
                onTap: () async {
                  if (w != MatchWhen.day) return ctl.update((q) => q.copyWith(when: w, day: () => null));
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: q.day ?? now,
                    firstDate: now.subtract(const Duration(days: 365)),
                    lastDate: now.add(const Duration(days: 365)),
                  );
                  if (picked != null) ctl.update((q) => q.copyWith(when: MatchWhen.day, day: () => picked));
                },
              ),
          ]),
          FilterGroup(title: 'Status', children: [
            SxChip(label: 'All', selected: q.status == null, onTap: () => ctl.update((q) => q.copyWith(status: () => null))),
            for (final (s, label) in const [
              (MatchStatus.live, 'Live'),
              (MatchStatus.upcoming, 'Upcoming'),
              (MatchStatus.completed, 'Completed'),
            ])
              SxChip(
                key: Key('status-${s.name}'),
                label: label,
                selected: q.status == s,
                onTap: () => ctl.update((q) => q.copyWith(status: () => s)),
              ),
          ]),
          Row(
            children: [
              SxButton.quiet(label: 'Clear all', onPressed: () => ctl.update((q) => q.cleared())),
              const SizedBox(width: Sx.s8),
              Expanded(
                child: SxButton(key: const Key('showMatches'), label: 'Show matches', onPressed: () => Navigator.of(context).pop()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The chips for whatever is filtered, each removable.
List<Widget> activeMatchFilterChips(MatchQuery q, void Function(MatchQuery Function(MatchQuery)) update) => [
      if (q.text.trim().isNotEmpty)
        RemovableChip(icon: Icons.search_rounded, label: '"${q.text.trim()}"', onRemove: () => update((q) => q.copyWith(text: ''))),
      if (!q.place.isAny)
        RemovableChip(
          icon: Icons.place_outlined,
          label: q.place.label!,
          onRemove: () => update((q) => q.copyWith(place: const PlaceFilter(), venue: () => null)),
        ),
      if (q.venue != null) RemovableChip(label: q.venue!, onRemove: () => update((q) => q.copyWith(venue: () => null))),
      for (final f in q.formats)
        RemovableChip(label: f.label, onRemove: () => update((q) => q.copyWith(formats: toggled(q.formats, f)))),
      if (q.category != null) RemovableChip(label: q.category!.label, onRemove: () => update((q) => q.copyWith(category: () => null))),
      if (q.tournamentId != null)
        RemovableChip(
          icon: Icons.emoji_events_outlined,
          label: q.tournamentName?.isNotEmpty == true ? q.tournamentName! : q.tournamentId!,
          onRemove: () => update((q) => q.copyWith(tournament: () => null)),
        ),
      if (q.when != MatchWhen.any)
        RemovableChip(
          icon: Icons.event_outlined,
          label: q.when == MatchWhen.day && q.day != null ? dayDate(q.day!) : q.when.label,
          onRemove: () => update((q) => q.copyWith(when: MatchWhen.any, day: () => null)),
        ),
    ];
