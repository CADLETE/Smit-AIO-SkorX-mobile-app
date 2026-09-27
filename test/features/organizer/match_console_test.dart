import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skorx/features/auth/auth_controller.dart';
import 'package:skorx/features/organizer/data/organizer_repository.dart';
import 'package:skorx/features/organizer/data/sample_organizer_repository.dart';
import 'package:skorx/features/organizer/data/tms_models.dart';
import 'package:skorx/features/organizer/scoring/match_console_controller.dart';
import 'package:skorx/sports/core/score_state.dart';

import '../../support/fakes.dart';

void main() {
  setUp(useInMemoryPreferences);

  late SampleOrganizerRepository server;
  late ProviderContainer container;
  late TmsMatch live;

  ProviderContainer phone() {
    final c = ProviderContainer(overrides: [
      organizerRepositoryProvider.overrideWithValue(server),
      preferencesProvider.overrideWithValue(SharedPreferencesAsync()),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    server = SampleOrganizerRepository(latency: Duration.zero);
    addTearDown(server.dispose);
    await server.tournaments('org1');
    live = (await server.matches('t-summer')).firstWhere((m) => m.state == MatchState.live);
    container = phone();
  });

  (String, String) key() => ('t-summer', live.id);

  Future<MatchConsoleController> open(ProviderContainer c) async {
    c.listen(matchConsoleProvider(key()), (_, _) {});
    await settle();
    return c.read(matchConsoleProvider(key()).notifier);
  }

  ConsoleState stateOf(ProviderContainer c) => c.read(matchConsoleProvider(key()));

  test('opens on the server score, then a tap syncs', () async {
    final console = await open(container);
    final before = stateOf(container);
    expect(before.sync, SyncStatus.synced);
    expect(before.score.currentGame, live.currentGame);

    await console.rally(before.score.serve.side);
    await settle();
    expect(stateOf(container).sync, SyncStatus.synced);
    expect(stateOf(container).pending, isEmpty);
    expect((await server.match(live.id)).scoreVersion, live.scoreVersion + 1);
  });

  test('taps made offline show at once, are kept, and sync in order when the network is back', () async {
    final console = await open(container);
    final serving = stateOf(container).score.serve.side;
    final start = stateOf(container).score.currentGame.of(serving);

    server.offline = true;
    await console.rally(serving);
    await settle();
    await console.rally(serving);
    await settle();
    expect(stateOf(container).sync, SyncStatus.offline);
    expect(stateOf(container).pending, hasLength(2));
    expect(stateOf(container).score.currentGame.of(serving), start + 2, reason: 'the score moves without the network');
    expect((await _peek(server, live.id)).scoreVersion, live.scoreVersion, reason: 'nothing reached the server');

    server.offline = false;
    await console.retryNow();
    await settle();
    expect(stateOf(container).sync, SyncStatus.synced);
    expect(stateOf(container).pending, isEmpty);
    final m = await server.match(live.id);
    expect(m.scoreVersion, live.scoreVersion + 2);
    expect(m.currentGame.of(serving), start + 2);
  });

  test('taps survive the app being closed while offline', () async {
    final console = await open(container);
    server.offline = true;
    await console.rally(Side.a);
    await settle();
    container.dispose();

    server.offline = false;
    final reopened = phone();
    await open(reopened);
    await settle();
    expect(stateOf(reopened).pending, isEmpty, reason: 'the saved tap was sent on reopen');
    expect((await server.match(live.id)).scoreVersion, live.scoreVersion + 1);
  });

  test('when another device scored first, the official chooses; nothing is overwritten', () async {
    final console = await open(container);
    // The other device scores while this phone is offline with a tap waiting.
    server.offline = true;
    await console.rally(Side.a);
    await settle();
    server.offline = false;
    final other = await server.score(
      live.id,
      ScoreWrite(clientEventId: 'other-device', baseVersion: live.scoreVersion, kind: ScoreWriteKind.rally, side: Side.b),
    );

    await console.retryNow();
    await settle();
    final s = stateOf(container);
    expect(s.sync, SyncStatus.conflict);
    expect(s.theirs, isNotNull);
    expect((await server.match(live.id)).scoreVersion, other.scoreVersion, reason: 'this phone did not overwrite');

    await console.addMyTaps();
    await settle();
    expect(stateOf(container).sync, SyncStatus.synced);
    expect((await server.match(live.id)).scoreVersion, other.scoreVersion + 1, reason: 'both devices\' taps count');
  });

  test('undo of a tap still on the phone never reaches the server', () async {
    final console = await open(container);
    server.offline = true;
    await console.rally(Side.a);
    await settle();
    await console.undo();
    await settle();
    expect(stateOf(container).pending, isEmpty);
    server.offline = false;
    await console.retryNow();
    await settle();
    expect((await server.match(live.id)).scoreVersion, live.scoreVersion);
  });

  test('a result is confirmed only once every tap is synced', () async {
    final console = await open(container);
    server.offline = true;
    await console.rally(Side.a);
    await settle();
    expect(await console.confirmResult(), contains('still on this phone'));
    server.offline = false;
    await console.retryNow();
    await settle();

    while (!stateOf(container).score.isOver) {
      await console.rally(stateOf(container).score.serve.side);
      await settle();
    }
    expect(await console.confirmResult(), isNull);
    expect((await server.match(live.id)).state, MatchState.completed);
  });
}

/// Reads the server without its offline switch getting in the way.
Future<TmsMatch> _peek(SampleOrganizerRepository server, String id) async {
  final was = server.offline;
  server.offline = false;
  try {
    return await server.match(id);
  } finally {
    server.offline = was;
  }
}
