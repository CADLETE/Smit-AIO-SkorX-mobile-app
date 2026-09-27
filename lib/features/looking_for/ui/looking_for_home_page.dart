import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../../notifications/notifications.dart';
import '../data/looking_for.dart';
import '../looking_for_controller.dart';
import 'lf_browse.dart';
import 'lf_widgets.dart';
import 'my_looking_for.dart';

/// Looking For: what the pickleball community needs right now, and the
/// fastest way to ask for what you need (docs/LOOKING-FOR.md §9).
///
/// One calm scroll: the hero, search, browse-by-need tiles, then the feed
/// under tabs that stay pinned. My Requests is a separate view from the top bar.
class LookingForHomePage extends ConsumerStatefulWidget {
  const LookingForHomePage({super.key, this.initialTab});

  /// for_you | nearby | latest | mine
  final String? initialTab;

  @override
  ConsumerState<LookingForHomePage> createState() => _LookingForHomePageState();
}

class _LookingForHomePageState extends ConsumerState<LookingForHomePage> {
  late bool _mine = widget.initialTab == 'mine';
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  /// The hero's own Post button is off screen: show the floating one.
  bool _showFab = false;

  @override
  void initState() {
    super.initState();
    final tab = LfTab.parse(widget.initialTab);
    if (tab != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(lfQueryProvider.notifier).update((q) => q.copyWith(tab: tab)));
    }
    _search.text = ref.read(lfQueryProvider).text;
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final show = _scroll.offset > 220;
    if (show != _showFab) setState(() => _showFab = show);
    if (_scroll.position.extentAfter < 600) ref.read(lfFeedProvider(ref.read(lfQueryProvider)).notifier).loadMore();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(lfQueryProvider.notifier).update((q) => q.copyWith(text: text));
    });
  }

  void _back() {
    // Opened on My Requests from browsing: back returns to browsing.
    if (_mine && widget.initialTab != 'mine') {
      setState(() => _mine = false);
    } else {
      lfBack(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final pending = ref.watch(lfCountsProvider).value?.pendingResponses ?? 0;
    return Scaffold(
      floatingActionButton: _mine
          ? null
          : AnimatedScale(
              scale: _showFab ? 1 : 0,
              duration: Sx.medium,
              curve: Curves.easeOutBack,
              child: _PostButton(onTap: () => context.push('/player/looking-for/new')),
            ),
      body: SafeArea(
        bottom: false,
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(
                title: _mine ? 'My Looking For' : 'Looking For',
                onBack: _back,
                actions: [
                  if (!_mine)
                    SxIconAction(
                      key: const Key('lfOpenMine'),
                      icon: Icons.inventory_2_outlined,
                      label: 'My requests',
                      dot: pending > 0,
                      onTap: () => setState(() => _mine = true),
                    ),
                  SxIconAction(
                    key: const Key('lfAlerts'),
                    icon: Icons.notifications_active_outlined,
                    label: 'My Looking For alerts',
                    onTap: () => context.push('/player/looking-for/alerts'),
                  ),
                  if (_mine)
                    SxIconAction(
                      icon: Icons.notifications_none_rounded,
                      label: 'Notifications',
                      dot: ref.watch(unreadNotificationsProvider) > 0,
                      onTap: () => context.push('/player/notifications'),
                    ),
                ],
              ),
              Expanded(
                child: _mine
                    ? const MyLookingForView()
                    : RefreshIndicator(
                        color: c.volt,
                        onRefresh: () async {
                          final q = ref.read(lfQueryProvider);
                          ref
                            ..invalidate(lfFeedProvider(q))
                            ..invalidate(lfSummaryProvider)
                            ..invalidate(lfCountsProvider);
                          await ref.read(lfFeedProvider(q).future);
                        },
                        child: CustomScrollView(
                          controller: _scroll,
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            const SliverPadding(
                              padding: EdgeInsets.fromLTRB(Sx.gutter, Sx.s4, Sx.gutter, 0),
                              sliver: SliverToBoxAdapter(child: SxReveal(child: LfHero())),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s20, Sx.gutter, 0),
                              sliver: SliverToBoxAdapter(
                                child: SxReveal(
                                  index: 1,
                                  child: LfSearchPill(
                                    controller: _search,
                                    onChanged: _onSearch,
                                    onFilters: () => showSxSheet<void>(context, builder: (_) => const _FilterSheet()),
                                  ),
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s24, Sx.gutter, 0),
                              sliver: SliverToBoxAdapter(
                                child: SxReveal(
                                  index: 2,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('BROWSE BY NEED', style: SxType.label(c.inkMuted)),
                                      const SizedBox(height: Sx.s16),
                                      const LfNeedGrid(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SliverToBoxAdapter(child: SizedBox(height: Sx.s24)),
                            SliverPersistentHeader(pinned: true, delegate: _TabsHeader(color: c.canvas)),
                            const SliverPadding(
                              padding: EdgeInsets.fromLTRB(Sx.gutter, Sx.s4, Sx.gutter, 0),
                              sliver: SliverToBoxAdapter(child: LfActiveFilters()),
                            ),
                            const _FeedSliver(),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostButton extends StatelessWidget {
  const _PostButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      button: true,
      label: 'Post a Looking For',
      excludeSemantics: true,
      child: Tappable(
        key: const Key('lfPost'),
        haptic: true,
        radius: 30,
        onTap: onTap,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: Sx.s24),
          decoration: BoxDecoration(gradient: c.brand, borderRadius: BorderRadius.circular(30), boxShadow: c.glowOf(c.voltFill)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, color: c.onPrimary),
              const SizedBox(width: Sx.s8),
              Text('Post', style: SxType.heading(c.onPrimary, size: 16)),
            ],
          ),
        ),
      ),
    );
  }
}

/// For You · Nearby · Latest, pinned under the top bar as the feed scrolls.
class _TabsHeader extends SliverPersistentHeaderDelegate {
  const _TabsHeader({required this.color});

  final Color color;

  @override
  double get minExtent => 58;

  @override
  double get maxExtent => 58;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => ClipRect(
    // Frosted, so the page's light shows through instead of a hard band.
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: Container(
        color: color.withValues(alpha: overlapsContent || shrinkOffset > 0 ? 0.72 : 0),
        alignment: Alignment.centerLeft,
        child: Consumer(
          builder: (context, ref, _) {
            final tab = ref.watch(lfQueryProvider.select((q) => q.tab));
            return SxTabs<LfTab>(
              tabs: [for (final t in LfTab.values) (t, t.label, null)],
              selected: tab,
              onSelect: (t) => ref.read(lfQueryProvider.notifier).update((q) => q.copyWith(tab: t)),
            );
          },
        ),
      ),
    ),
  );

  @override
  bool shouldRebuild(_TabsHeader old) => old.color != color;
}

class _FeedSliver extends ConsumerWidget {
  const _FeedSliver();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(lfQueryProvider);
    final feed = ref.watch(lfFeedProvider(query));
    final bottom = MediaQuery.paddingOf(context).bottom + 104;
    Widget boxed(Widget child) => SliverPadding(
      padding: EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, bottom),
      sliver: SliverToBoxAdapter(child: child),
    );
    return switch (feed) {
      AsyncData(:final value) when value.posts.isEmpty => boxed(_Empty(query: query, needsLocation: value.needsLocation)),
      AsyncData(:final value) => SliverPadding(
        padding: EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, bottom),
        sliver: SliverList.builder(
          itemCount: value.posts.length + (value.hasMore ? 1 : 0),
          itemBuilder: (context, i) {
            if (i >= value.posts.length) {
              return const Padding(
                padding: EdgeInsets.all(Sx.s16),
                child: Center(child: BallLoader()),
              );
            }
            final post = value.posts[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: Sx.s12),
              child: SxReveal(
                index: i.clamp(0, 6),
                child: LfPostCard(
                  post: post,
                  showReasons: query.tab == LfTab.forYou,
                  onChanged: (next) => ref.read(lfFeedProvider(query).notifier).patch(post.id, (_) => next),
                ),
              ),
            );
          },
        ),
      ),
      AsyncError() => boxed(ErrorBlock(message: 'Could not load requests.', onRetry: () => ref.invalidate(lfFeedProvider(query)))),
      _ => boxed(const SkeletonList(rows: 3, rowHeight: 170)),
    };
  }
}

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final q = ref.watch(lfQueryProvider);
    void set(LfQuery Function(LfQuery) f) => ref.read(lfQueryProvider.notifier).update(f);
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: Sx.s20, bottom: Sx.s8),
      child: Text(t.toUpperCase(), style: SxType.label(c.inkMuted)),
    );
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
      children: [
        Row(
          children: [
            Expanded(child: Text('Filters', style: SxType.heading(c.ink, size: 20))),
            if (q.activeFilters > 0)
              SxButton.quiet(
                label: 'Clear all',
                onPressed: () => set((q) => LfQuery(tab: q.tab, text: q.text)),
              ),
          ],
        ),
        label('Distance'),
        LfChoiceRow<int?>(
          keyPrefix: 'lfRadius',
          options: const [(null, 'Any'), (5, '5 km'), (10, '10 km'), (25, '25 km'), (50, '50 km')],
          isSelected: (v) => q.radiusKm == v,
          onTap: (v) => set(
            (q) => v == null ? q.copyWith(clearRadius: true) : q.copyWith(radiusKm: v, tab: q.tab == LfTab.forYou ? LfTab.nearby : q.tab),
          ),
        ),
        label('Level'),
        LfChoiceRow<String>(
          keyPrefix: 'lfSkill',
          options: [for (final s in lfSkillBands) (s, lfSkillLabels[s]!)],
          isSelected: q.skill.contains,
          onTap: (s) => set((q) {
            final next = {...q.skill};
            next.contains(s) ? next.remove(s) : next.add(s);
            return q.copyWith(skill: next);
          }),
        ),
        label('Payment'),
        LfChoiceRow<bool?>(
          keyPrefix: 'lfPaid',
          options: const [(null, 'Any'), (true, 'Paid work'), (false, 'Unpaid')],
          isSelected: (v) => q.paid == v,
          onTap: (v) => set((q) => v == null ? q.copyWith(clearPaid: true) : q.copyWith(paid: v)),
        ),
        label('Open to'),
        LfChoiceRow<String?>(
          keyPrefix: 'lfGender',
          options: const [(null, 'Everyone'), ('male', 'Men'), ('female', 'Women')],
          isSelected: (v) => q.gender == v,
          onTap: (v) => set((q) => v == null ? q.copyWith(clearGender: true) : q.copyWith(gender: v)),
        ),
        label('Sort'),
        LfChoiceRow<String>(
          keyPrefix: 'lfSort',
          options: const [('new', 'Newly posted'), ('soonest', 'Happening soonest'), ('expiring', 'Expiring soon')],
          isSelected: (v) => q.sort == v,
          onTap: (v) => set((q) => q.copyWith(sort: v)),
        ),
        const SizedBox(height: Sx.s24),
        SxButton(label: 'Show requests', onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}

class _Empty extends ConsumerWidget {
  const _Empty({required this.query, required this.needsLocation});

  final LfQuery query;
  final bool needsLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtered = query.activeFilters > 0 || query.text.trim().isNotEmpty;
    final (_, title, message, action) = needsLocation
        ? (
            Icons.location_off_outlined,
            'Where are you playing?',
            'Set your city in Looking For alerts to see requests near you.',
            SxButton.secondary(label: 'Set my city', expand: false, onPressed: () => context.push('/player/looking-for/alerts')),
          )
        : filtered || query.tab == LfTab.nearby
        ? (
            Icons.radar_rounded,
            'Nothing nearby yet.',
            'No active requirements match your filters.',
            SxButton(
                  key: const Key('lfEmptyPost'),
                  label: 'Create a Looking For',
                  expand: false,
                  onPressed: () => context.push('/player/looking-for/new'),
                )
                as Widget,
          )
        : query.tab == LfTab.forYou
        ? (
            Icons.radar_rounded,
            'Nothing for you right now.',
            'When someone near you needs a player, official or court that fits you, it shows here.',
            SxButton.secondary(
                  label: 'See latest',
                  expand: false,
                  onPressed: () => ref.read(lfQueryProvider.notifier).update((q) => q.copyWith(tab: LfTab.latest)),
                )
                as Widget,
          )
        : (
            Icons.campaign_rounded,
            'Be the first.',
            'Need a player, referee, scorer or court?',
            SxButton(label: 'Post Looking For', expand: false, onPressed: () => context.push('/player/looking-for/new')) as Widget,
          );
    return Column(
      children: [
        const SizedBox(height: Sx.s16),
        const SxBall(size: 56),
        EmptyBlock(title: title, message: message, action: action, compact: true),
      ],
    );
  }
}
