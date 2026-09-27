import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../design/design.dart';
import 'workspace.dart';
import 'workspace_controller.dart';
import 'workspace_switcher.dart';

/// Player ⇄ Organiser as one segmented pill: the open mode is lit, the other
/// is one tap away. Shown on the profile in both modes. A player with no
/// organisation yet gets a way to set one up instead of a switch.
class ModeSwitch extends ConsumerWidget {
  const ModeSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final state = ref.watch(workspaceControllerProvider);
    final orgs = state.available.whereType<OrganizerWorkspace>().toList();
    final inPlayer = state.current is PlayerWorkspace;

    Future<void> openOrganiser() async {
      if (orgs.isEmpty) {
        await _showOrganiserIntro(context);
      } else if (orgs.length == 1) {
        await switchWorkspace(context, orgs.single);
      } else {
        await showWorkspaceSwitcher(context);
      }
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        gradient: c.card,
        borderRadius: BorderRadius.circular(Sx.radiusLg),
        border: Border.all(color: c.cardEdge),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Segment(
              key: inPlayer ? null : const Key('switchToPlayer'),
              icon: Icons.sports_tennis_rounded,
              label: 'Player',
              caption: 'Matches & stats',
              selected: inPlayer,
              semanticLabel: inPlayer ? 'Player mode, current' : 'Switch to Player',
              onTap: inPlayer ? null : () => switchWorkspace(context, const PlayerWorkspace()),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _Segment(
              key: Key(inPlayer ? 'switchModeCard' : 'switchOrganisation'),
              icon: Icons.dashboard_customize_rounded,
              label: 'Organiser',
              caption: !inPlayer
                  ? state.current.title
                  : switch (orgs.length) {
                      0 => 'Run tournaments',
                      1 => orgs.single.title,
                      final n => '$n organisations',
                    },
              selected: !inPlayer,
              // Already organising one club: nothing to switch to.
              trailing: !inPlayer && orgs.length > 1 ? Icons.unfold_more_rounded : null,
              semanticLabel: inPlayer ? 'Switch to Organiser' : 'Organiser mode, current',
              onTap: inPlayer || orgs.length > 1 ? openOrganiser : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Organiser mode belongs to an organisation, and organisations are set up
/// with the SkorX team for now, so this says how to get one.
Future<void> _showOrganiserIntro(BuildContext context) => showSxSheet<void>(
      context,
      builder: (ctx) {
        final c = ctx.sx;
        return Padding(
          key: const Key('organiserIntro'),
          padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('RUN TOURNAMENTS ON SKORX', style: SxType.title(c.ink, size: 26)),
              const SizedBox(height: Sx.s8),
              Text(
                'Organiser mode is for clubs, academies and venues. Draws, schedules, live scoring and results, '
                'all from this app. Your player account stays the same.',
                style: SxType.body(c.inkMuted, size: 14.5),
              ),
              const SizedBox(height: Sx.s20),
              SxRows(
                title: 'Set up your organisation',
                children: [
                  SxRow(icon: FontAwesomeIcons.whatsapp.data, label: 'WhatsApp us', value: '+91 79 4000 0000'),
                  const SxRow(icon: Icons.mail_outline_rounded, label: 'Email', value: 'help@skorx.app'),
                ],
              ),
              const SizedBox(height: Sx.s16),
              SxButton.secondary(label: 'Not now', onPressed: () => Navigator.pop(ctx)),
            ],
          ),
        );
      },
    );

class _Segment extends StatelessWidget {
  const _Segment({
    super.key,
    required this.icon,
    required this.label,
    required this.caption,
    required this.selected,
    required this.semanticLabel,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String caption;
  final bool selected;
  final String semanticLabel;
  final IconData? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final fg = selected ? c.onVolt : c.ink;
    final muted = selected ? c.onVolt.withValues(alpha: 0.7) : c.inkMuted;
    const radius = Sx.radiusLg - 4;
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      child: Tappable(
        onTap: onTap,
        radius: radius,
        child: AnimatedContainer(
          duration: Sx.fast,
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: Sx.s12),
          decoration: BoxDecoration(
            gradient: selected ? c.brand : null,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: selected ? c.glowOf(c.voltFill, strength: 0.5) : null,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: Sx.s8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label.toUpperCase(), maxLines: 1, style: SxType.label(fg, size: 13)),
                    const SizedBox(height: 1),
                    Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(muted, size: 11.5)),
                  ],
                ),
              ),
              if (trailing != null) Icon(trailing, size: 18, color: muted),
              if (!selected) Icon(Icons.arrow_forward_rounded, size: 16, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}
