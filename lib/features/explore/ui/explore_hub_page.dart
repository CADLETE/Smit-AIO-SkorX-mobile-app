import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../../player/player_pages.dart';
import '../explore_modules.dart';
import '../explore_page.dart';
import '../explore_signals.dart';
import 'coming_soon.dart';
import 'explore_cards.dart';
import 'leaderboard_section.dart';

/// The Explore tab: everything on SkorX, one tap from each. What is open
/// leads; what is coming follows, so the hub is never a dead end.
class ExploreHubPage extends ConsumerWidget {
  const ExploreHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signals = {for (final m in exploreModules) m.id: ref.watch(exploreSignalProvider(m.id))};
    return PlayerTabList(
      onRefresh: () async => refreshExploreSignals(ref),
      header: const ExploreHeader(),
      children: [
        const SizedBox(height: Sx.s12),
        ExploreGrid(
          modules: exploreModules,
          signalOf: (m) => signals[m.id],
          onOpen: (m) => openExploreModule(context, m),
        ),
        const SizedBox(height: Sx.section),
        const ExploreLeaderboards(),
        if (upcomingExploreModules.isNotEmpty) ...[
          const SizedBox(height: Sx.section),
          const SxSection('Coming to SkorX'),
          ComingSoonList(modules: upcomingExploreModules, onTap: (m) => openExploreModule(context, m)),
        ],
      ],
    );
  }
}

/// Opens a module: inside Explore, on its own tab, or, if it is not built
/// yet, the coming-soon sheet.
void openExploreModule(BuildContext context, ExploreModule m) {
  if (!m.available) {
    showComingSoon(context, m);
    return;
  }
  // Full-screen features open on top, with a way back; tabs are switched to.
  if (m.location!.startsWith('/player/looking-for')) {
    context.push(m.location!);
  } else {
    context.go(m.location!);
  }
}

class ExploreHeader extends StatelessWidget {
  const ExploreHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SxTitleBar(title: 'Explore'),
        Padding(
          padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s8),
          child: Text('Discover everything happening on SkorX.', style: SxType.body(c.inkMuted)),
        ),
      ],
    );
  }
}

/// `/player/explore/:module`: an open module inside the Explore tab, or
/// the coming-soon page for one still being built.
class ExploreModulePage extends StatelessWidget {
  const ExploreModulePage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final m = exploreModuleById(id);
    if (m != null && !m.available) return ComingSoonPage(module: m);
    return ExploreBrowser(view: id, tabs: false);
  }
}

/// Where `/player/explore/:module` really goes: unknown modules back to the
/// hub, modules on other tabs (Scores) to that tab, Leaderboards (a
/// section on the hub) to the full rankings.
String? exploreModuleRedirect(String id) {
  if (id == 'leaderboards') return '/player/rankings';
  final m = exploreModuleById(id);
  if (m == null) return '/player/explore';
  if (m.available && !m.nested) return m.location;
  return null;
}
