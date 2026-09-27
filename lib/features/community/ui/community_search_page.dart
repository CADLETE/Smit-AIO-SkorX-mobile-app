import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../../player/player_pages.dart';
import '../community_controller.dart';
import '../data/community.dart';
import '../data/community_query.dart';
import 'community_widgets.dart';

/// Searches Community, or browses one sector of it. Plain sentences work:
/// "referee near Ahmedabad", "indoor courts Surat", "coach for beginners".
/// A sector page starts from the chosen location; a search starts anywhere.
class CommunitySearchPage extends ConsumerStatefulWidget {
  const CommunitySearchPage({super.key, this.sector, this.initialText = ''});

  final CommunitySector? sector;
  final String initialText;

  @override
  ConsumerState<CommunitySearchPage> createState() => _CommunitySearchPageState();
}

class _CommunitySearchPageState extends ConsumerState<CommunitySearchPage> {
  late final _search = TextEditingController(text: widget.initialText);
  Timer? _debounce;
  late String _text = widget.initialText;
  late CommunityQuery _filters = CommunityQuery(
    sector: widget.sector,
    city: widget.sector == null ? null : ref.read(communityLocationProvider).city,
  );

  static const examples = [
    'Referee near Ahmedabad',
    'Scorekeepers in Gujarat',
    'Pickleball academy near me',
    'Indoor courts Ahmedabad',
    'Tournament organizers',
    'Pickleball streamer',
    'Coach for beginner training',
    'Doubles partner Surat',
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => setState(() => _text = text));
  }

  void _setText(String text) {
    _debounce?.cancel();
    _search.text = text;
    _search.selection = TextSelection.collapsed(offset: text.length);
    setState(() => _text = text);
  }

  /// The sentence's filters, with the chips and filter sheet on top.
  CommunityQuery get _query {
    final parsed = CommunityQuery.parse(_text);
    final here = ref.read(communityLocationProvider).city;
    final f = _filters;
    return CommunityQuery(
      text: parsed.text,
      sector: f.sector,
      roles: {...parsed.roles, ...f.roles},
      kinds: {...parsed.kinds, ...f.kinds},
      city: parsed.city ?? f.city ?? (parsed.nearMe ? here : null),
      state: parsed.city != null ? null : (parsed.state ?? f.state),
      verifiedOnly: parsed.verifiedOnly || f.verifiedOnly,
      availableOnly: parsed.availableOnly || f.availableOnly,
      language: f.language ?? parsed.language,
      setting: f.setting ?? parsed.setting,
      level: f.level ?? parsed.level,
      tag: f.tag ?? parsed.tag,
    );
  }

  bool get _idle => _text.trim().isEmpty && _filters.sector == null && _filters.filterCount == 0 && _filters.city == null;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final q = _query;
    final title = widget.sector?.title ?? 'Search';
    return SafeArea(
      bottom: false,
      child: SxWidth(
        child: Column(
          children: [
            SxTitleBar(
              title: title,
              leading: SxIconAction(
                key: const Key('communityBack'),
                icon: Icons.arrow_back_rounded,
                label: 'Back to Community',
                onTap: () => context.canPop() ? context.pop() : context.go('/player/community'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s8),
              child: TextField(
                key: const Key('communitySearchField'),
                controller: _search,
                autofocus: widget.sector == null && widget.initialText.isEmpty,
                onChanged: _onChanged,
                onSubmitted: _setText,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: widget.sector == null ? 'Try "referee near Ahmedabad"' : 'Search ${title.toLowerCase()}',
                  prefixIcon: Icon(Icons.search_rounded, color: c.inkMuted),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: Icon(Icons.close_rounded, color: c.inkMuted),
                          onPressed: () => _setText(''),
                        ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            _ChipsRow(
              query: q,
              filters: _filters,
              sector: widget.sector,
              onFilters: (f) => setState(() => _filters = f),
            ),
            Expanded(
              child: _idle
                  ? _Suggestions(examples: examples, onPick: _setText)
                  : _Results(query: q, onClear: () {
                      _setText('');
                      setState(() => _filters = CommunityQuery(sector: widget.sector));
                    }),
            ),
          ],
        ),
      ),
    );
  }
}

/// Location, filters, then the sector's own roles and kinds as chips.
class _ChipsRow extends ConsumerWidget {
  const _ChipsRow({required this.query, required this.filters, required this.sector, required this.onFilters});

  final CommunityQuery query;
  final CommunityQuery filters;
  final CommunitySector? sector;
  final ValueChanged<CommunityQuery> onFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chips = <Widget>[
      SxChip(
        key: const Key('searchLocation'),
        icon: Icons.place_rounded,
        label: query.city ?? query.state ?? 'Anywhere',
        selected: false,
        onTap: () => _pickCity(context, ref),
      ),
      SxChip(
        key: const Key('communityFilters'),
        icon: Icons.tune_rounded,
        label: filters.filterCount == 0 ? 'Filters' : 'Filters · ${filters.filterCount}',
        selected: filters.filterCount > 0,
        onTap: () async {
          final next = await showCommunityFilters(context, filters);
          if (next != null) onFilters(next);
        },
      ),
    ];
    final s = sector;
    if (s != null) {
      final roleOptions = s.roles.length > 1 ? s.roles : const <CommunityRole>[];
      final kindOptions = s.placeKinds;
      final all = filters.roles.isEmpty && filters.kinds.isEmpty && filters.tag == null && filters.setting == null;
      chips.add(SxChip(
        key: const Key('chip-all'),
        label: 'All',
        selected: all,
        onTap: () => onFilters(filters.copyWith(roles: const {}, kinds: const {}, tag: () => null, setting: () => null)),
      ));
      for (final r in roleOptions) {
        chips.add(SxChip(
          key: Key('chip-${r.name}'),
          label: r.plural,
          selected: filters.roles.length == 1 && filters.roles.contains(r),
          onTap: () => onFilters(filters.copyWith(roles: {r}, kinds: const {})),
        ));
      }
      // Kinds get chips when there is something to choose between.
      if ((s.roles.isNotEmpty && kindOptions.isNotEmpty) || kindOptions.length > 1) {
        for (final k in kindOptions) {
          chips.add(SxChip(
            key: Key('chip-${k.name}'),
            label: k.plural,
            selected: filters.kinds.length == 1 && filters.kinds.contains(k),
            onTap: () => onFilters(filters.copyWith(kinds: {k}, roles: const {})),
          ));
        }
      }
      if (s == CommunitySector.players) {
        for (final t in playerTags) {
          chips.add(SxChip(
            key: Key('chip-$t'),
            label: t,
            selected: filters.tag == t,
            onTap: () => onFilters(filters.copyWith(tag: () => filters.tag == t ? null : t)),
          ));
        }
      }
      if (s == CommunitySector.places) {
        for (final st in [PlaceSetting.indoor, PlaceSetting.outdoor]) {
          chips.add(SxChip(
            key: Key('chip-${st.name}'),
            label: st.label,
            selected: filters.setting == st,
            onTap: () => onFilters(filters.copyWith(setting: () => filters.setting == st ? null : st)),
          ));
        }
      }
    }
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(Sx.gutter, 2, Sx.gutter, 8),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: Sx.s8),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }

  Future<void> _pickCity(BuildContext context, WidgetRef ref) async {
    final picked = await showSxSheet<(String?,)>(
      context,
      builder: (ctx) {
        final c = ctx.sx;
        Widget row(String? city) => SxRow(
              key: Key('searchCity-${city ?? 'anywhere'}'),
              icon: city == null ? Icons.public_rounded : Icons.place_outlined,
              label: city ?? 'Anywhere',
              trailing: query.city == city ? Icon(Icons.check_rounded, color: c.volt) : const SizedBox(width: 24),
              onTap: () => Navigator.pop(ctx, (city,)),
            );
        return Padding(
          padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
          child: SxRows(title: 'Where', children: [row(null), for (final city in communityCities.keys) row(city)]),
        );
      },
    );
    if (picked != null) onFilters(filters.copyWith(city: () => picked.$1, state: () => null));
  }
}

/// Every filter at once. Returns the new filters, or null if dismissed.
Future<CommunityQuery?> showCommunityFilters(BuildContext context, CommunityQuery start) => showSxSheet<CommunityQuery>(
      context,
      builder: (ctx) {
        var f = start;
        return StatefulBuilder(builder: (ctx, setState) {
          final c = ctx.sx;
          void set(CommunityQuery next) => setState(() => f = next);
          Widget group(String title, List<Widget> chips) => Padding(
                padding: const EdgeInsets.only(top: Sx.s20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title.toUpperCase(), style: SxType.label(c.inkMuted)),
                    const SizedBox(height: Sx.s8),
                    Wrap(spacing: Sx.s8, runSpacing: Sx.s8, children: chips),
                  ],
                ),
              );
          final roles = f.sector?.roles ?? CommunityRole.values;
          final kinds = f.sector?.placeKinds ?? PlaceKind.values;
          return Padding(
            padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Filters', style: SxType.title(c.ink, size: 26)),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (roles.length > 1)
                          group('Role', [
                            for (final r in roles)
                              SxChip(
                                key: Key('filterRole-${r.name}'),
                                label: r.label,
                                icon: r.icon,
                                selected: f.roles.contains(r),
                                onTap: () => set(f.copyWith(roles: {...f.roles}..toggle(r))),
                              ),
                          ]),
                        if (kinds.isNotEmpty)
                          group('Places', [
                            for (final k in kinds)
                              SxChip(
                                label: k.plural,
                                icon: k.icon,
                                selected: f.kinds.contains(k),
                                onTap: () => set(f.copyWith(kinds: {...f.kinds}..toggle(k))),
                              ),
                          ]),
                        group('Trust and availability', [
                          SxChip(
                            key: const Key('filterVerified'),
                            label: 'Verified only',
                            icon: Icons.verified_rounded,
                            selected: f.verifiedOnly,
                            onTap: () => set(f.copyWith(verifiedOnly: !f.verifiedOnly)),
                          ),
                          SxChip(
                            key: const Key('filterAvailable'),
                            label: 'Available now',
                            icon: Icons.event_available_rounded,
                            selected: f.availableOnly,
                            onTap: () => set(f.copyWith(availableOnly: !f.availableOnly)),
                          ),
                        ]),
                        group('Language', [
                          for (final l in communityLanguages)
                            SxChip(
                              label: l,
                              selected: f.language == l,
                              onTap: () => set(f.copyWith(language: () => f.language == l ? null : l)),
                            ),
                        ]),
                        group('Level', [
                          for (final l in communityLevels)
                            SxChip(
                              label: l,
                              selected: f.level == l,
                              onTap: () => set(f.copyWith(level: () => f.level == l ? null : l)),
                            ),
                        ]),
                        group('Courts', [
                          for (final s in [PlaceSetting.indoor, PlaceSetting.outdoor])
                            SxChip(
                              label: s.label,
                              selected: f.setting == s,
                              onTap: () => set(f.copyWith(setting: () => f.setting == s ? null : s)),
                            ),
                        ]),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Sx.s24),
                Row(
                  children: [
                    Expanded(
                      child: SxButton.secondary(
                        label: 'Clear',
                        onPressed: () => Navigator.pop(ctx, CommunityQuery(sector: f.sector, city: f.city)),
                      ),
                    ),
                    const SizedBox(width: Sx.s12),
                    Expanded(
                      child: SxButton(key: const Key('applyFilters'), label: 'Show results', onPressed: () => Navigator.pop(ctx, f)),
                    ),
                  ],
                ),
              ],
            ),
          );
        });
      },
    );

extension<T> on Set<T> {
  void toggle(T value) => contains(value) ? remove(value) : add(value);
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.examples, required this.onPick});

  final List<String> examples;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return ListView(
      padding: EdgeInsets.fromLTRB(Sx.gutter, Sx.s16, Sx.gutter, playerTabBottom(context)),
      children: [
        Text('TRY ASKING', style: SxType.label(c.inkMuted)),
        const SizedBox(height: Sx.s12),
        Wrap(
          spacing: Sx.s8,
          runSpacing: Sx.s8,
          children: [
            for (final e in examples)
              SxChip(key: Key('example-$e'), label: e, icon: Icons.north_west_rounded, selected: false, onTap: () => onPick(e)),
          ],
        ),
        const SizedBox(height: Sx.section),
        const SxSection('Browse'),
        SxRows(children: [
          for (final s in CommunitySector.values)
            SxRow(
              icon: s.icon,
              label: s.title,
              subtitle: s.tagline,
              onTap: () => context.push('/player/community/browse/${s.name}'),
            ),
        ]),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.query, required this.onClear});

  final CommunityQuery query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final people = query.wantsPeople ? ref.watch(communityMembersProvider(query)) : const AsyncData(<CommunityMember>[]);
    final places = query.wantsPlaces ? ref.watch(communityPlacesProvider(query)) : const AsyncData(<CommunityPlace>[]);
    final bottom = playerTabBottom(context);
    if (people.isLoading || places.isLoading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s16, Sx.gutter, 0),
        child: const SkeletonList(rows: 5, rowHeight: 76),
      );
    }
    if (people.hasError || places.hasError) {
      return ErrorBlock(
        message: 'Could not load Community.',
        onRetry: () {
          ref.invalidate(communityMembersProvider(query));
          ref.invalidate(communityPlacesProvider(query));
        },
      );
    }
    final ps = people.value ?? const [];
    final pl = places.value ?? const [];
    if (ps.isEmpty && pl.isEmpty) {
      return ListView(
        padding: EdgeInsets.fromLTRB(Sx.gutter, Sx.s32, Sx.gutter, bottom),
        children: [
          EmptyBlock(
            key: const Key('communityNoResults'),
            icon: Icons.search_off_rounded,
            title: 'No one matches',
            message: query.city != null
                ? 'Nobody for ${query.describe()} yet. Try searching anywhere, or fewer filters.'
                : 'Try fewer words or filters.',
            action: SxButton.secondary(label: 'Clear search', expand: false, onPressed: onClear),
          ),
        ],
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, bottom),
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            'Showing ${query.describe()}${query.text.isEmpty ? '' : ' matching "${query.text}"'}',
            key: const Key('searchSummary'),
            style: SxType.caption(c.inkMuted),
          ),
        ),
        if (ps.isNotEmpty) ...[
          const SizedBox(height: Sx.s16),
          SxSection('People · ${ps.length}'),
          ListCard(children: [for (final m in ps) MemberRow(member: m)]),
        ],
        if (pl.isNotEmpty) ...[
          const SizedBox(height: Sx.s24),
          SxSection('Places · ${pl.length}'),
          ListCard(children: [for (final p in pl) PlaceRow(place: p)]),
        ],
      ],
    );
  }
}
