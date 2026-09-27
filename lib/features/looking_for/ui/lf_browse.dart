import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../data/looking_for.dart';
import '../looking_for_controller.dart';
import 'lf_widgets.dart';

/// A way to browse: one tile for one or more categories.
class LfNeed {
  const LfNeed(this.id, this.label, this.icon, this.categories);

  final String id;
  final String label;
  final IconData icon;

  /// Empty for "More", which opens the full list.
  final Set<String> categories;

  bool matches(Set<String> selected) => categories.isNotEmpty && selected.length == categories.length && selected.containsAll(categories);
}

/// The eight tiles on the Looking For home: what people most often need.
const lfNeeds = [
  LfNeed('players', 'Players', Icons.person_add_alt_1_rounded, {'player'}),
  LfNeed('match', 'Match', Icons.sports_tennis_rounded, {'match'}),
  LfNeed('team', 'Team', Icons.groups_rounded, {'team'}),
  LfNeed('tournament', 'Tournament', Icons.emoji_events_rounded, {'tournament'}),
  LfNeed('officials', 'Officials', Icons.sports_rounded, {'referee', 'scorer'}),
  LfNeed('media', 'Media', Icons.videocam_rounded, {'commentator', 'streamer'}),
  LfNeed('courts', 'Courts', Icons.stadium_rounded, {'ground', 'club'}),
  LfNeed('more', 'More', Icons.apps_rounded, {}),
];

/// Each tile its own pair, so the eight read apart at a glance.
List<Color> lfNeedColors(SxColors c, String id) => switch (id) {
      'players' => [c.voltFill, c.olive],
      'match' => [c.cyan, c.blue],
      'team' => [c.olive, c.deep],
      'tournament' => [c.deep, c.blue],
      'officials' => [c.blue, c.deep],
      'media' => [Color.lerp(c.cyan, c.deep, 0.35)!, c.deep],
      'courts' => [Color.lerp(c.voltFill, c.cyan, 0.55)!, c.blue],
      _ => [c.inkMuted, c.inkFaint],
    };

/// The top of Looking For: what it is for, and the two things you came to do.
class LfHero extends ConsumerWidget {
  const LfHero({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(lfSummaryProvider).value?.total;
    final pending = ref.watch(lfCountsProvider).value?.pendingResponses ?? 0;
    return SxHeroCard(
      padding: const EdgeInsets.fromLTRB(Sx.s20, Sx.s20, Sx.s20, Sx.s20),
      child: SxOnHero(
        child: Builder(builder: (context) {
          final c = context.sx;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.radar_rounded, size: 16, color: c.ink.withValues(alpha: 0.8)),
                  const SizedBox(width: 6),
                  Text('LOOKING FOR', style: SxType.label(c.ink.withValues(alpha: 0.8), size: 11.5)),
                ],
              ),
              const SizedBox(height: Sx.s8),
              Padding(
                // Leaves the ball its corner.
                padding: const EdgeInsets.only(right: 56),
                child: Text('Find players, officials and courts', maxLines: 2, style: SxType.title(c.ink, size: 26)),
              ),
              const SizedBox(height: Sx.s4),
              Text(
                total == null || total == 0
                    ? 'Post what you need. SkorX tells the people who fit.'
                    : '$total open ${total == 1 ? 'request' : 'requests'} in the community right now',
                style: SxType.body(c.ink.withValues(alpha: 0.85), size: 14),
              ),
              const SizedBox(height: Sx.s16),
              Row(
                children: [
                  _HeroPill(
                    key: const Key('lfHeroPost'),
                    icon: Icons.add_rounded,
                    label: 'Post a need',
                    onTap: () => context.push('/player/looking-for/new'),
                  ),
                  if (pending > 0) ...[
                    const SizedBox(width: Sx.s12),
                    Flexible(
                      child: Tappable(
                        key: const Key('lfHeroResponses'),
                        onTap: () => context.push('/player/looking-for?tab=mine'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: Sx.s8),
                          child: Text(
                            '$pending new ${pending == 1 ? 'response' : 'responses'} →',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SxType.heading(c.ink, size: 14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tappable(
        onTap: onTap,
        haptic: true,
        radius: 24,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: Sx.s16),
          decoration: BoxDecoration(
            gradient: c.brand,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: c.onVolt),
              const SizedBox(width: 6),
              Text(label, style: SxType.heading(c.onVolt, size: 14.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One rounded search field with the filters button inside it.
class LfSearchPill extends ConsumerWidget {
  const LfSearchPill({super.key, required this.controller, required this.onChanged, required this.onFilters});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final active = ref.watch(lfQueryProvider.select((q) => q.activeFilters - (q.categories.isEmpty ? 0 : 1)));
    return Container(
      height: 52,
      padding: const EdgeInsets.only(left: Sx.s16, right: 6),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: c.isDark ? 0.7 : 1),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: c.cardEdge),
        boxShadow: c.cardShadow,
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: c.inkMuted, size: 21),
          const SizedBox(width: Sx.s8),
          Expanded(
            child: TextField(
              key: const Key('lfSearch'),
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: SxType.body(c.ink),
              decoration: InputDecoration(
                hintText: 'Try "players tonight" or "referee"',
                hintStyle: SxType.body(c.inkFaint),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (_, v, _) => v.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Clear search',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded, color: c.inkMuted, size: 20),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
          Semantics(
            button: true,
            label: active == 0 ? 'Filters' : 'Filters, $active on',
            excludeSemantics: true,
            child: Tappable(
              key: const Key('lfFilters'),
              radius: 20,
              onTap: onFilters,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: active > 0 ? c.brand : null,
                  color: active > 0 ? null : c.surfaceAlt.withValues(alpha: c.isDark ? 0.7 : 1),
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.tune_rounded, size: 19, color: active > 0 ? c.onVolt : c.ink),
                    if (active > 0)
                      Positioned(
                        right: 6,
                        top: 5,
                        child: Text('$active', style: SxType.label(c.onVolt, size: 9.5, weight: FontWeight.w900)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Browse by need: eight illustrated tiles with how many are open in each.
class LfNeedGrid extends ConsumerWidget {
  const LfNeedGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(lfQueryProvider.select((q) => q.categories));
    final summary = ref.watch(lfSummaryProvider).value;
    final categories = ref.watch(lfCategoriesProvider).value ?? const <LfCategory>[];
    final custom = selected.isNotEmpty && !lfNeeds.any((n) => n.matches(selected));
    void choose(LfNeed n) {
      if (n.categories.isEmpty) {
        showSxSheet<void>(context, builder: (_) => _AllNeedsSheet(categories: categories));
        return;
      }
      ref.read(lfQueryProvider.notifier).update((q) => q.copyWith(categories: n.matches(q.categories) ? {} : n.categories));
    }

    return LayoutBuilder(builder: (context, box) {
      const columns = 4;
      final width = (box.maxWidth - Sx.s8 * (columns - 1)) / columns;
      return Wrap(
        spacing: Sx.s8,
        runSpacing: Sx.s16,
        children: [
          for (final n in lfNeeds)
            SizedBox(
              width: width,
              child: _NeedTile(
                need: n,
                label: n.categories.isEmpty && custom
                    ? (categories.where((c) => selected.contains(c.id)).map((c) => c.label).firstOrNull ?? n.label)
                    : n.label,
                count: n.categories.isEmpty ? null : summary?.count(n.categories),
                selected: n.categories.isEmpty ? custom : n.matches(selected),
                dimmed: selected.isNotEmpty && !(n.categories.isEmpty ? custom : n.matches(selected)),
                onTap: () => choose(n),
              ),
            ),
        ],
      );
    });
  }
}

class _NeedTile extends StatelessWidget {
  const _NeedTile({
    required this.need,
    required this.label,
    required this.count,
    required this.selected,
    required this.dimmed,
    required this.onTap,
  });

  final LfNeed need;
  final String label;
  final int? count;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final colors = lfNeedColors(c, need.id);
    return Semantics(
      button: true,
      selected: selected,
      label: count == null || count == 0 ? label : '$label, $count open',
      excludeSemantics: true,
      child: Tappable(
        key: Key('lfNeed-${need.id}'),
        onTap: onTap,
        radius: 20,
        child: AnimatedOpacity(
          duration: Sx.fast,
          opacity: dimmed ? 0.45 : 1,
          child: Column(
            children: [
              SizedBox(
                width: 62,
                height: 62,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: Sx.medium,
                      curve: Curves.easeOutCubic,
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        gradient: need.categories.isEmpty
                            ? null
                            : LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color.lerp(colors[0], Colors.white, 0.12)!, colors[1]],
                              ),
                        color: need.categories.isEmpty ? c.surface : null,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected ? c.volt : (need.categories.isEmpty ? c.cardEdge : Colors.transparent),
                          width: selected ? 2.5 : 1,
                        ),
                        boxShadow: selected ? c.glowOf(colors[0], strength: 0.9) : c.glowOf(colors[0], strength: 0.25),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Stack(
                          children: [
                            // A court corner behind the icon: the tiles belong together.
                            if (need.categories.isNotEmpty)
                              Positioned(
                                right: -18,
                                bottom: -14,
                                width: 58,
                                height: 44,
                                child: ExcludeSemantics(
                                  child: CustomPaint(painter: CourtPainter(color: Colors.white.withValues(alpha: 0.22), topInset: 0.14)),
                                ),
                              ),
                            Center(
                              child: Icon(
                                need.icon,
                                size: 28,
                                color: need.categories.isEmpty
                                    ? c.ink
                                    : (colors[0] == c.voltFill ? c.onVolt : Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (count != null && count! > 0)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          height: 22,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.canvas,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: c.volt, width: 1.5),
                          ),
                          child: Text('${count! > 99 ? '99+' : count}', style: SxType.label(c.ink, size: 10.5, weight: FontWeight.w800)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Sx.s8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: SxType.caption(selected ? c.ink : c.inkMuted, size: 12.5)
                    .copyWith(fontWeight: selected ? FontWeight.w800 : FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every category, for needs that are not on the eight tiles.
class _AllNeedsSheet extends ConsumerWidget {
  const _AllNeedsSheet({required this.categories});

  final List<LfCategory> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final selected = ref.watch(lfQueryProvider.select((q) => q.categories));
    final summary = ref.watch(lfSummaryProvider).value;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
      children: [
        Text('Everything you can look for', style: SxType.heading(c.ink, size: 20)),
        const SizedBox(height: Sx.s12),
        SxRows(children: [
          for (final cat in categories)
            SxRow(
              key: Key('lfAllNeed-${cat.id}'),
              label: cat.label,
              subtitle: cat.tagline,
              icon: lfIcon(cat.icon),
              value: (summary?.byCategory[cat.id] ?? 0) == 0 ? null : '${summary!.byCategory[cat.id]} open',
              trailing: selected.length == 1 && selected.contains(cat.id) ? Icon(Icons.check_rounded, color: c.volt) : null,
              onTap: () {
                ref.read(lfQueryProvider.notifier).update((q) => q.copyWith(categories: {cat.id}));
                Navigator.of(context).pop();
              },
            ),
        ]),
      ],
    );
  }
}

/// What is narrowing the list, each removable in one tap.
class LfActiveFilters extends ConsumerWidget {
  const LfActiveFilters({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(lfQueryProvider);
    final categories = ref.watch(lfCategoriesProvider).value ?? const <LfCategory>[];
    void set(LfQuery Function(LfQuery) f) => ref.read(lfQueryProvider.notifier).update(f);
    final need = lfNeeds.where((n) => n.matches(q.categories)).firstOrNull;
    final chips = <(String, VoidCallback)>[
      if (q.categories.isNotEmpty)
        (
          need?.label ?? categories.where((c) => q.categories.contains(c.id)).map((c) => c.label).join(', '),
          () => set((q) => q.copyWith(categories: {})),
        ),
      if (q.radiusKm != null) ('Within ${q.radiusKm} km', () => set((q) => q.copyWith(clearRadius: true))),
      if (q.skill.isNotEmpty) (q.skill.map((s) => lfSkillLabels[s]).join(' / '), () => set((q) => q.copyWith(skill: {}))),
      if (q.paid != null) (q.paid! ? 'Paid work' : 'Unpaid', () => set((q) => q.copyWith(clearPaid: true))),
      if (q.gender != null) (q.gender == 'male' ? 'Men' : 'Women', () => set((q) => q.copyWith(clearGender: true))),
      if (q.sort != 'new') (q.sort == 'expiring' ? 'Expiring soon' : 'Soonest first', () => set((q) => q.copyWith(sort: 'new'))),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    final c = context.sx;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sx.s12),
      child: Wrap(
        spacing: Sx.s8,
        runSpacing: Sx.s8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (label, clear) in chips)
            Tappable(
              key: Key('lfActive-$label'),
              radius: 16,
              onTap: clear,
              child: Container(
                height: 32,
                padding: const EdgeInsets.only(left: 12, right: 8),
                decoration: BoxDecoration(
                  color: c.volt.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.volt.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: SxType.caption(c.ink, size: 12.5).copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 4),
                    Icon(Icons.close_rounded, size: 15, color: c.inkMuted),
                  ],
                ),
              ),
            ),
          if (chips.length > 1)
            SxButton.quiet(label: 'Clear all', onPressed: () => set((q) => LfQuery(tab: q.tab, text: q.text))),
        ],
      ),
    );
  }
}
