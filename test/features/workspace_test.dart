import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skorx/features/auth/data/auth_repository.dart';
import 'package:skorx/features/workspace/workspace.dart';
import 'package:skorx/features/workspace/workspace_controller.dart';

import '../support/fakes.dart';

void main() {
  group('workspacesFor', () {
    test('a plain player only has the Player workspace', () {
      expect(workspacesFor(user()).map((w) => w.key), ['player']);
    });

    test('lists organizations by name, and opens nothing for referee roles', () {
      final workspaces = workspacesFor(user(memberships: [
        membership('b', 'Zeta Club', 'tournament_admin'),
        membership('a', 'Ahmedabad Pickleball Club', 'owner'),
        membership('c', 'XYZ Sports', 'referee'),
        membership('d', 'Delta Open', 'referee'),
      ]));
      expect(workspaces.map((w) => w.key), ['player', 'org:a', 'org:b']);
      expect((workspaces[1] as OrganizerWorkspace).subtitle, 'Owner');
    });

    test('a referee-only membership leaves just the Player workspace', () {
      final workspaces = workspacesFor(user(memberships: [membership('c', 'XYZ Sports', 'referee')]));
      expect(workspaces.map((w) => w.key), ['player']);
    });
  });

  group('WorkspaceController', () {
    setUp(useInMemoryPreferences);

    Future<ProviderContainer> signedIn(FakeAuthRepository repo) async {
      final container = ProviderContainer(overrides: appOverrides(repo));
      addTearDown(container.dispose);
      container.listen(workspaceControllerProvider, (_, _) {});
      // Let the session restore and the saved workspace load.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      return container;
    }

    final owner = user(memberships: [
      membership('org1', 'CADLETE Pickleball', 'owner'),
      membership('org2', 'Ahmedabad Pickleball Club', 'tournament_admin'),
    ]);

    test('starts in the Player workspace', () async {
      final container = await signedIn(FakeAuthRepository(stored: RestoredUser(owner, fromCache: false)));
      final state = container.read(workspaceControllerProvider);
      expect(state.ready, isTrue);
      expect(state.current, isA<PlayerWorkspace>());
    });

    test('remembers the workspace and screen across launches', () async {
      final repo = FakeAuthRepository(stored: RestoredUser(owner, fromCache: false));
      final first = await signedIn(repo);
      final controller = first.read(workspaceControllerProvider.notifier);
      controller.recordLocation('/player/paddle');
      controller.recordLocation('/org/org1/schedule');
      await Future<void>.delayed(Duration.zero);

      final relaunched = await signedIn(repo);
      final state = relaunched.read(workspaceControllerProvider);
      expect(state.current.key, 'org:org1');
      expect(state.entryLocation(state.current), '/org/org1/schedule');
      expect(state.lastLocations['player'], '/player/paddle');
    });

    test('keeps each organization separate', () async {
      final container = await signedIn(FakeAuthRepository(stored: RestoredUser(owner, fromCache: false)));
      final controller = container.read(workspaceControllerProvider.notifier);
      controller.recordLocation('/org/org1/matches');
      controller.recordLocation('/org/org2/schedule');
      final state = container.read(workspaceControllerProvider);
      expect(state.lastLocations['org:org1'], '/org/org1/matches');
      expect(state.lastLocations['org:org2'], '/org/org2/schedule');
      expect(state.current.key, 'org:org2');
    });

    test('ignores locations outside the workspaces the user has', () async {
      final container = await signedIn(FakeAuthRepository(stored: RestoredUser(owner, fromCache: false)));
      container.read(workspaceControllerProvider.notifier).recordLocation('/org/not-mine/dashboard');
      expect(container.read(workspaceControllerProvider).current, isA<PlayerWorkspace>());
    });

    test('falls back to Player when the saved organization was left', () async {
      final repo = FakeAuthRepository(stored: RestoredUser(owner, fromCache: false));
      final first = await signedIn(repo);
      first.read(workspaceControllerProvider.notifier).recordLocation('/org/org1/dashboard');
      await Future<void>.delayed(Duration.zero);

      repo.stored = RestoredUser(user(memberships: [membership('org2', 'Ahmedabad Pickleball Club', 'owner')]),
          fromCache: false);
      final relaunched = await signedIn(repo);
      final state = relaunched.read(workspaceControllerProvider);
      expect(state.current, isA<PlayerWorkspace>());
      expect(state.lastLocations.containsKey('org:org1'), isFalse);
    });

    test('does not leak one account\'s workspace into another on the same phone', () async {
      final repo = FakeAuthRepository(stored: RestoredUser(owner, fromCache: false));
      final first = await signedIn(repo);
      first.read(workspaceControllerProvider.notifier).recordLocation('/org/org1/dashboard');
      await Future<void>.delayed(Duration.zero);

      repo.stored = RestoredUser(user(id: 'u2', memberships: [membership('org1', 'CADLETE Pickleball', 'owner')]),
          fromCache: false);
      final other = await signedIn(repo);
      expect(other.read(workspaceControllerProvider).current, isA<PlayerWorkspace>());
    });
  });
}
