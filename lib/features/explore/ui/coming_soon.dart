import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../explore_modules.dart';
import 'explore_cards.dart';

/// Tapping a module that is on the way: say so, briefly, and let go.
Future<void> showComingSoon(BuildContext context, ExploreModule module) => showSxSheet<void>(
      context,
      scrollable: false,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ComingSoonMessage(module: module),
            const SizedBox(height: Sx.s24),
            SxButton(key: const Key('comingSoonOk'), label: 'Got it', onPressed: () => Navigator.of(ctx).pop()),
          ],
        ),
      ),
    );

/// The module, marked coming soon, and one plain line on where it stands.
class ComingSoonMessage extends StatelessWidget {
  const ComingSoonMessage({super.key, required this.module});

  final ExploreModule module;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Column(
      key: const Key('comingSoon'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SxPop(child: SxIconTile(icon: module.icon, size: 64, solid: true, colors: module.tone.colors(c))),
        const SizedBox(height: Sx.s20),
        const SoonBadge(text: 'COMING SOON'),
        const SizedBox(height: Sx.s12),
        Semantics(
          header: true,
          child: Text(module.title, textAlign: TextAlign.center, style: SxType.title(c.ink, size: 32)),
        ),
        const SizedBox(height: Sx.s4),
        Text(module.tagline, textAlign: TextAlign.center, style: SxType.heading(c.inkMuted, size: 15)),
        const SizedBox(height: Sx.s12),
        Text(
          'This SkorX feature is currently under development.',
          textAlign: TextAlign.center,
          style: SxType.body(c.inkMuted, size: 14),
        ),
      ],
    );
  }
}

/// Where a link to a module that is not built yet lands (a shared link, an
/// old notification): the same message as a page, with the way back.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({super.key, required this.module});

  final ExploreModule module;

  @override
  Widget build(BuildContext context) => SafeArea(
        bottom: false,
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(onBack: () => context.canPop() ? context.pop() : context.go('/player/explore')),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s48),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ComingSoonMessage(module: module),
                        const SizedBox(height: Sx.s24),
                        SxButton.secondary(
                          label: 'Back to Explore',
                          expand: false,
                          onPressed: () => context.go('/player/explore'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
