import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:go_router/go_router.dart';

import '../../app/theme/tokens.dart';
import '../../design/fx.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';
import '../workspace/workspace_switcher.dart';
import '../onboarding/app_tour.dart';

class ShellDestination {
  const ShellDestination(this.label, this.icon, this.selectedIcon, {this.badge});

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// A count shown on the tab (requests, unread messages); nothing at zero.
  final ProviderListenable<int>? badge;
}

/// Room at the bottom of scrolling pages so content clears the bottom bar.
const floatingNavClearance = 120.0;

/// Bottom padding for a scrolling tab page: the bar (and anything floating
/// on it) plus a little air. The shell extends the body under the bar, so
/// the bar's height arrives as bottom padding.
double tabBottomPadding(BuildContext context) => MediaQuery.paddingOf(context).bottom + SkorxSpace.xl;

/// The frame of one workspace: its name (and an optional action) on top,
/// its own bottom navigation below. Switching modes lives on the Profile
/// tab, not in the top bar. Each workspace builds its own shell, so no
/// workspace ever shows another's tabs.
class WorkspaceShell extends ConsumerWidget {
  const WorkspaceShell({
    super.key,
    required this.child,
    required this.destinations,
    required this.currentIndex,
    required this.onSelect,
    this.fullBleedTabs = const {},
    this.overlay,
    this.tour = false,
    this.action,
  });

  /// A shell whose tabs each keep their own navigation stack.
  factory WorkspaceShell.stateful({
    required StatefulNavigationShell navigationShell,
    required List<ShellDestination> destinations,
    Set<int> fullBleedTabs = const {},
    Widget? overlay,
    bool tour = false,
  }) =>
      WorkspaceShell(
        destinations: destinations,
        currentIndex: navigationShell.currentIndex,
        onSelect: (index) => navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex),
        fullBleedTabs: fullBleedTabs,
        overlay: overlay,
        tour: tour,
        child: navigationShell,
      );

  final Widget child;
  final List<ShellDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  /// Tabs that draw their own header (every Player tab), so the shell's top
  /// bar is hidden there.
  final Set<int> fullBleedTabs;

  /// Floats just above the bottom bar on every tab, e.g. the player's
  /// resume-match bar. Sizes itself to nothing when it has nothing to show.
  final Widget? overlay;

  /// Whether this shell hosts the first-run app tour (the Player shell).
  final bool tour;

  /// Top right of the bar, e.g. the organiser's tournament actions.
  final Widget? action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final offline = auth is SignedIn && auth.fromCache;
    final fullBleed = fullBleedTabs.contains(currentIndex);

    final wide = MediaQuery.sizeOf(context).width >= 840;
    if (wide) {
      // Tablet and web: the tabs become a side rail and content stays centred.
      return Scaffold(
        appBar: fullBleed
            ? null
            : AppBar(
                toolbarHeight: 64,
                titleSpacing: SkorxSpace.lg,
                title: const Align(alignment: Alignment.centerLeft, child: WorkspaceTitle()),
                actions: [
                  if (action != null) Padding(padding: const EdgeInsets.only(right: SkorxSpace.lg), child: action),
                ],
              ),
        body: Row(
          children: [
            SkorxSideRail(destinations: destinations, currentIndex: currentIndex, onSelect: onSelect),
            Expanded(
              child: Column(
                children: [
                  if (offline) SafeArea(bottom: false, child: const OfflineBanner()),
                  Expanded(child: child),
                  ?overlay,
                ],
              ),
            ),
          ],
        ),
      );
    }

    final scaffold = Scaffold(
      // Content scrolls underneath the frosted bottom bar.
      extendBody: true,
      appBar: fullBleed
          ? null
          : AppBar(
              toolbarHeight: 64,
              titleSpacing: SkorxSpace.lg,
              title: const Align(alignment: Alignment.centerLeft, child: WorkspaceTitle()),
              actions: [
                if (action != null) Padding(padding: const EdgeInsets.only(right: SkorxSpace.lg), child: action),
              ],
            ),
      body: Column(
        children: [
          if (offline) SafeArea(bottom: false, child: const OfflineBanner()),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?overlay,
          SkorxNavBar(
            destinations: destinations,
            currentIndex: currentIndex,
            onSelect: onSelect,
            tabKeys: tour ? appTourTabKeys : null,
          ),
        ],
      ),
    );
    if (!tour) return scaffold;
    return Stack(children: [scaffold, Positioned.fill(child: AppTourLayer(onSelectTab: onSelect))]);
  }
}

/// The workspace's bottom bar: a frosted dock with the tabs split either
/// side of an optional raised [centerAction] (the player's Play button).
class SkorxNavBar extends StatelessWidget {
  const SkorxNavBar({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onSelect,
    this.centerAction,
    this.tabKeys,
  });

  /// Keys on each tab, so the app tour can find them on screen.
  final List<GlobalKey>? tabKeys;

  final List<ShellDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final Widget? centerAction;

  static const barHeight = 66.0;

  /// How far the centre button rises above the bar.
  static const centerRise = 22.0;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    Widget tab(int index) => Expanded(
          child: _NavTab(
            key: tabKeys != null && index < tabKeys!.length ? tabKeys![index] : null,
            destination: destinations[index],
            selected: index == currentIndex,
            onTap: () => onSelect(index),
          ),
        );

    final split = (destinations.length / 2).ceil();
    final tabs = <Widget>[
      if (centerAction == null)
        for (var i = 0; i < destinations.length; i++) tab(i)
      else ...[
        for (var i = 0; i < split; i++) tab(i),
        // Room for the raised button, which is drawn over the bar.
        const SizedBox(width: 76),
        for (var i = split; i < destinations.length; i++) tab(i),
      ],
    ];

    // A floating glass dock over the ambient backdrop.
    final c = context.sx;
    final bar = Padding(
      padding: EdgeInsets.fromLTRB(Sx.s12, 0, Sx.s12, bottomInset > 0 ? bottomInset : Sx.s12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: c.isDark ? 0.5 : 0.12), blurRadius: 30, offset: const Offset(0, 12)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(c.surface, c.blue, c.isDark ? 0.10 : 0.03)!.withValues(alpha: c.isDark ? 0.78 : 0.86),
                    c.surface.withValues(alpha: c.isDark ? 0.86 : 0.94),
                  ],
                ),
                border: Border.all(color: c.cardEdge),
              ),
              child: SizedBox(height: barHeight, child: Row(children: tabs)),
            ),
          ),
        ),
      ),
    );
    if (centerAction == null) return bar;

    // The button rises above the bar. The strip beside it stays transparent
    // to taps, so content under it is still reachable.
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Padding(padding: const EdgeInsets.only(top: centerRise), child: bar),
        centerAction!,
      ],
    );
  }
}

class _NavTab extends ConsumerWidget {
  const _NavTab({super.key, required this.destination, required this.selected, required this.onTap});

  final ShellDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final motion = !sxReduceMotion(context);
    final badge = destination.badge == null ? 0 : ref.watch(destination.badge!);
    return Semantics(
      button: true,
      selected: selected,
      label: badge > 0 ? '${destination.label}, $badge new' : destination.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!selected) HapticFeedback.selectionClick();
          onTap();
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.elasticOut,
                  scale: selected && motion ? 1.08 : 1,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    width: selected ? 50 : 40,
                    height: 30,
                    decoration: BoxDecoration(
                      gradient: selected ? c.brand : null,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: selected ? c.glowOf(c.voltFill, strength: 0.7) : null,
                    ),
                    child: Icon(
                      selected ? destination.selectedIcon : destination.icon,
                      color: selected ? c.onVolt : c.inkMuted,
                      size: 20,
                    ),
                  ),
                ),
                if (badge > 0)
                  Positioned(
                    top: -5,
                    right: -7,
                    child: Container(
                      key: Key('navBadge-${destination.label}'),
                      constraints: const BoxConstraints(minWidth: 18),
                      height: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: c.heat,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: c.surface, width: 1.5),
                      ),
                      child: Text(
                        badge > 9 ? '9+' : '$badge',
                        style: const TextStyle(fontFamily: SxType.sans, fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(
                fontFamily: SxType.sans,
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? c.ink : c.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The tabs as a side rail, for tablet and web widths.
class SkorxSideRail extends StatelessWidget {
  const SkorxSideRail({super.key, required this.destinations, required this.currentIndex, required this.onSelect});

  final List<ShellDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      width: 96,
      decoration: BoxDecoration(border: Border(right: BorderSide(color: c.line))),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: Sx.s24),
            for (var i = 0; i < destinations.length; i++)
              SizedBox(
                height: 76,
                child: _NavTab(destination: destinations[i], selected: i == currentIndex, onTap: () => onSelect(i)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Scrollable page body with the standard gutters.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(SkorxSpace.lg, SkorxSpace.sm, SkorxSpace.lg, floatingNavClearance),
        children: [for (final (i, child) in children.indexed) SxReveal(index: i, child: child)],
      );
}
