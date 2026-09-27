import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';
import '../shell/workspace_shell.dart';
import '../workspace/workspace_controller.dart';
import '../workspace/workspace_switcher.dart';

/// The person behind the account, the same in every workspace: identity,
/// the workspaces they can open, and signing out.
class AccountPage extends ConsumerWidget {
  const AccountPage({super.key, this.sections = const []});

  /// Workspace-specific sections shown between the identity row and the
  /// workspaces, e.g. the player's performance.
  final List<Widget> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final workspaces = ref.watch(workspaceControllerProvider);
    final colors = context.skorx.colors;
    if (user == null) return const SizedBox.shrink();

    return PageBody(
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: colors.surfaceInteractive,
              child: Text(
                user.name.isEmpty ? '?' : user.name.trim()[0].toUpperCase(),
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: SkorxSpace.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name, style: Theme.of(context).textTheme.titleLarge),
                  if (user.phone != null) Text(user.phone!, style: TextStyle(color: colors.textMuted)),
                ],
              ),
            ),
          ],
        ),
        ...sections,
        const SectionHeader('Workspaces'),
        for (final workspace in workspaces.available)
          Padding(
            padding: const EdgeInsets.only(bottom: SkorxSpace.sm),
            child: ListTile(
              minTileHeight: 56,
              tileColor: colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SkorxRadius.md),
                side: BorderSide(color: workspace.key == workspaces.current.key ? colors.blue : colors.border),
              ),
              leading: Icon(workspaceIcon(workspace)),
              title: Text(workspace.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(workspace.subtitle),
              trailing: workspace.key == workspaces.current.key
                  ? Icon(Icons.check_rounded, color: colors.blue)
                  : Icon(Icons.chevron_right_rounded, color: colors.textMuted),
              onTap: () => switchWorkspace(context, workspace),
            ),
          ),
        const SizedBox(height: SkorxSpace.xl),
        OutlinedButton.icon(
          onPressed: () => _confirmSignOut(context, ref),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sign out'),
        ),
      ],
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in any time with your mobile number.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed == true) await ref.read(authControllerProvider.notifier).signOut();
  }
}
