import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';
import '../../app/theme/typography.dart';
import 'workspace.dart';
import 'workspace_controller.dart';

IconData workspaceIcon(Workspace workspace) => switch (workspace) {
      PlayerWorkspace() => Icons.sports_tennis_rounded,
      OrganizerWorkspace() => Icons.dashboard_customize_rounded,
    };

/// The current workspace, top left of the shell. Just a label: switching
/// happens from the Profile tab.
class WorkspaceTitle extends ConsumerWidget {
  const WorkspaceTitle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(workspaceControllerProvider.select((s) => s.current));
    final colors = context.skorx.colors;
    return Semantics(
      header: true,
      label: '${current.title}, ${current.subtitle}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: context.skorx.highlight.withValues(alpha: 0.18),
            child: Icon(workspaceIcon(current), size: 17, color: context.skorx.highlight),
          ),
          const SizedBox(width: SkorxSpace.sm),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                if (current is! PlayerWorkspace)
                  Text(
                    current.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showWorkspaceSwitcher(BuildContext context) async {
  final target = await showModalBottomSheet<Workspace>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _WorkspaceSheet(),
  );
  if (target == null || !context.mounted) return;
  await switchWorkspace(context, target);
}

/// A short, calm transition that says where the user is going, then opens
/// that workspace where they left it. It is the same account, so there is no
/// loading or sign-in step.
Future<void> switchWorkspace(BuildContext context, Workspace target) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final state = container.read(workspaceControllerProvider);
  if (target.key == state.current.key) return;
  final destination = state.entryLocation(target);
  final router = GoRouter.of(context);
  final reduceMotion = MediaQuery.of(context).disableAnimations;

  if (!reduceMotion) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Switching mode',
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => _SwitchingOverlay(target: target),
      transitionBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
    );
    await Future<void>.delayed(const Duration(milliseconds: 550));
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
  router.go(destination);
}

class _SwitchingOverlay extends StatelessWidget {
  const _SwitchingOverlay({required this.target});

  final Workspace target;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    final (mode, accent) = switch (target) {
      PlayerWorkspace() => ('PLAYER MODE', colors.cyan),
      OrganizerWorkspace() => ('ORGANISER MODE', colors.lime),
    };
    return Material(
      color: colors.background.withValues(alpha: 0.97),
      child: Center(
        child: Semantics(
          liveRegion: true,
          label: 'Switching to ${target.title}, ${mode.toLowerCase()}',
          excludeSemantics: true,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: MediaQuery.of(context).disableAnimations ? 1 : 0, end: 1),
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
            builder: (_, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.14),
                    border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.5),
                  ),
                  child: Icon(workspaceIcon(target), size: 34, color: accent),
                ),
                const SizedBox(height: SkorxSpace.xl),
                Text(mode, style: SkorxType.headline(44, color: colors.text)),
                const SizedBox(height: SkorxSpace.sm),
                Text(
                  target is PlayerWorkspace ? 'Your matches, stats and courts' : target.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textMuted, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: SkorxSpace.xl),
                SizedBox(
                  width: 120,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      color: accent,
                      backgroundColor: colors.surfaceInteractive,
                      value: MediaQuery.of(context).disableAnimations ? 1 : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceSheet extends ConsumerWidget {
  const _WorkspaceSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceControllerProvider);
    final organizations = state.available.whereType<OrganizerWorkspace>().toList();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(SkorxSpace.lg, 0, SkorxSpace.lg, SkorxSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SWITCH MODE', style: SkorxType.headline(28, color: context.skorx.colors.text)),
            const SizedBox(height: SkorxSpace.md),
            _WorkspaceTile(workspace: const PlayerWorkspace(), selected: state.current is PlayerWorkspace),
            if (organizations.isNotEmpty) ...[
              const _SheetLabel('Organiser'),
              for (final org in organizations) _WorkspaceTile(workspace: org, selected: state.current.key == org.key),
            ],
          ],
        ),
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: SkorxSpace.lg, bottom: SkorxSpace.sm),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w800,
            color: context.skorx.colors.textMuted,
          ),
        ),
      );
}

class _WorkspaceTile extends StatelessWidget {
  const _WorkspaceTile({required this.workspace, required this.selected});

  final Workspace workspace;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: SkorxSpace.sm),
      child: ListTile(
        selected: selected,
        minTileHeight: 60,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SkorxRadius.md),
          side: BorderSide(color: selected ? colors.blue : colors.border),
        ),
        tileColor: colors.surfaceMuted,
        selectedTileColor: colors.surfaceInteractive,
        leading: Icon(workspaceIcon(workspace), color: selected ? colors.blue : colors.textMuted),
        title: Text(workspace.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(workspace.subtitle),
        trailing: selected ? Icon(Icons.check_rounded, color: colors.blue) : null,
        onTap: () => Navigator.of(context).pop(workspace),
      ),
    );
  }
}
