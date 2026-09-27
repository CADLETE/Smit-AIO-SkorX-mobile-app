import '../../app/theme/app_theme.dart';
import '../auth/data/current_user.dart';

/// A separate experience inside the one account: its own navigation, its own
/// home, its own accent. Switching workspace replaces the whole shell.
sealed class Workspace {
  const Workspace();

  /// Stable id used for persistence and to match locations to workspaces.
  String get key;
  String get title;
  String get subtitle;
  String get homeLocation;
  WorkspaceAccent get accent;

  /// Whether [location] (a router path) belongs to this workspace.
  bool owns(String location) => location == pathPrefix || location.startsWith('$pathPrefix/');
  String get pathPrefix;
}

class PlayerWorkspace extends Workspace {
  const PlayerWorkspace();

  @override
  String get key => 'player';
  @override
  String get title => 'Player';
  @override
  String get subtitle => 'My matches, stats and tournaments';
  @override
  String get pathPrefix => '/player';
  @override
  String get homeLocation => '/player/home';
  @override
  WorkspaceAccent get accent => WorkspaceAccent.player;
}

class OrganizerWorkspace extends Workspace {
  const OrganizerWorkspace(this.membership);

  final Membership membership;

  String get organizationId => membership.organizationId;

  @override
  String get key => 'org:${membership.organizationId}';
  @override
  String get title => membership.organizationName;
  @override
  String get subtitle => roleLabel(membership.role);
  @override
  String get pathPrefix => '/org/${membership.organizationId}';
  @override
  String get homeLocation => '$pathPrefix/dashboard';
  @override
  WorkspaceAccent get accent => WorkspaceAccent.operations;

  bool can(String capability) => membership.can(capability);
}

String roleLabel(String role) => switch (role) {
      'owner' => 'Owner',
      'tournament_admin' => 'Admin',
      'referee' => 'Referee',
      'scorer' => 'Scorer',
      'check_in_staff' => 'Check-in staff',
      'finance' => 'Finance',
      'viewer' => 'Viewer',
      _ => role,
    };

/// Every workspace the user can open, in switcher order: Player first, then
/// organizations by name. There is no referee mode, so a referee-only
/// membership never opens a workspace.
List<Workspace> workspacesFor(CurrentUser user) {
  final organizer = user.memberships.where((m) => m.role != 'referee').toList()
    ..sort((a, b) => a.organizationName.toLowerCase().compareTo(b.organizationName.toLowerCase()));
  return [
    const PlayerWorkspace(),
    ...organizer.map(OrganizerWorkspace.new),
  ];
}
