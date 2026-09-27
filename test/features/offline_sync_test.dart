import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skorx/app/theme/app_theme.dart';
import 'package:skorx/core/api/api_exception.dart';
import 'package:skorx/core/sync/connectivity.dart';
import 'package:skorx/features/auth/auth_controller.dart';
import 'package:skorx/features/casual_match/data/match_setup.dart';
import 'package:skorx/features/casual_match/local_match.dart';
import 'package:skorx/features/casual_match/offline/match_store.dart';
import 'package:skorx/features/casual_match/offline/sync_engine.dart';
import 'package:skorx/features/casual_match/offline/sync_upload.dart';
import 'package:skorx/features/casual_match/offline/ui/offline_ui.dart';
import 'package:skorx/features/casual_match/played_matches.dart';
import 'package:skorx/features/casual_match/verification/verification_controller.dart' show casualVerificationRepositoryProvider;
import 'package:skorx/features/casual_match/verification/verification_repository.dart';
import 'package:skorx/sports/core/match_rules.dart';
import 'package:skorx/sports/core/score_state.dart';
import 'package:skorx/sports/core/scoring_engine.dart';

import '../support/fakes.dart';

const _oneGame = MatchRules(pointsToWin: 11, winByTwo: true, bestOf: 1);
const _bestOf3 = MatchRules(pointsToWin: 11, winByTwo: true, bestOf: 3);

int _seq = 0;

/// A singles match against a registered player, with rallies won by [sides].
LocalMatch match(String id, {List<Side> sides = const [], MatchRules rules = _oneGame, DateTime? at}) {
  final start = at ?? DateTime(2026, 9, 27, 10);
  final events = [
    for (final (i, s) in sides.indexed)
      RecordedEvent(id: 'evt-${++_seq}-$i', event: RallyWon(s), recordedAt: start.add(Duration(seconds: 20 * (i + 1)))),
  ];
  final m = LocalMatch(
    id: id,
    sportId: 'pickleball',
    categoryId: 'singles',
    sideA: const ['You'],
    sideB: const ['Riya Shah'],
    rules: rules,
    firstServer: Side.a,
    startedAt: start,
    events: events,
    details: const MatchDetails(sideAIds: ['me'], sideBIds: ['SKX-10519']),
  );
  return m.isOver ? m.copyWith(finishedAt: start.add(Duration(seconds: 20 * sides.length + 5))) : m;
}

/// Rallies reaching [a]–[b], alternating so the game never ends early.
List<Side> points(int a, int b) {
  final common = a < b ? a : b;
  return [
    for (var i = 0; i < common; i++) ...[Side.a, Side.b],
    ...List.filled(a - common, Side.a),
    ...List.filled(b - common, Side.b),
  ];
}

/// SkorX's sync endpoint, answering as [respond] says (synced by default).
class FakeSyncServer implements CasualVerificationRepository {
  final sent = <List<SyncItem>>[];
  SyncOutcome Function(SyncItem item)? respond;
  Object? error;
  int version = 0;

  @override
  Future<List<SyncOutcome>> sync(List<SyncItem> items, {required String deviceId, Map<String, dynamic>? client}) async {
    sent.add(items);
    if (error != null) throw error!;
    return [
      for (final i in items)
        respond?.call(i) ?? SyncOutcome(clientRef: i.match.id, status: SyncStatus.synced, matchId: 'srv-${i.match.id}', syncVersion: ++version),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class Net {
  bool online = true;
  Future<bool> probe() async => online;
}

ProviderContainer container(FakeSyncServer server, Net net) {
  final c = ProviderContainer(overrides: [
    casualVerificationRepositoryProvider.overrideWithValue(server),
    // No file system in tests: the store keeps one preference per match.
    matchStoreProvider.overrideWith((ref) => MatchStore(ref.watch(preferencesProvider), directory: () async => throw UnsupportedError('no files'))),
    currentUserProvider.overrideWithValue(user(id: 'u1')),
    reachabilityProbeProvider.overrideWithValue(net.probe),
  ]);
  addTearDown(c.dispose);
  return c;
}

/// A finished match on the phone, in the ledger, with one sync run done.
Future<LocalMatch> scoredAndTracked(ProviderContainer c, LocalMatch m) async {
  await c.read(playedMatchesProvider.notifier).record(m);
  await c.read(casualSyncProvider.notifier).track(m);
  await c.read(casualSyncProvider.notifier).run();
  return m;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(useInMemoryPreferences);

  group('MatchStore', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('skorx_store'));
    tearDown(() async => dir.delete(recursive: true));

    MatchStore store() => MatchStore(SharedPreferencesAsync(), directory: () async => dir);

    test('keeps the active match and each played match in its own file', () async {
      final s = store();
      await s.writeActive(match('live', sides: points(10, 8)));
      await s.writePlayed(match('p1', sides: points(11, 3)));
      await s.writePlayed(match('p2', sides: points(11, 5)));
      final again = store();
      expect((await again.readActive())!.score.currentGame, const GameScore(10, 8));
      expect({for (final m in await again.readPlayed()) m.id}, {'p1', 'p2'});
      expect(File('${dir.path}/played/p1.json').existsSync(), isTrue);
      expect(dir.listSync(recursive: true).where((f) => f.path.endsWith('.tmp')), isEmpty);
    });

    test('sets a damaged file aside and still loads the others (#17)', () async {
      final s = store();
      await s.writePlayed(match('good', sides: points(11, 2)));
      File('${dir.path}/played/bad.json').writeAsStringSync('{"id": "bad", "events": [');
      final loaded = await s.readPlayed();
      expect([for (final m in loaded) m.id], ['good']);
      expect(s.quarantined, 1);
      expect(Directory('${dir.path}/played').listSync().any((f) => f.path.endsWith('.corrupt')), isTrue);
    });

    test('recovers a write that died before its rename (#8)', () async {
      Directory('${dir.path}/played').createSync(recursive: true);
      File('${dir.path}/played/torn.json.tmp').writeAsStringSync(jsonEncode(match('torn', sides: points(11, 0)).toJson()));
      expect([for (final m in await store().readPlayed()) m.id], ['torn']);
    });

    test('moves matches saved by earlier versions out of preferences (#24)', () async {
      final prefs = SharedPreferencesAsync();
      await prefs.setString(MatchStore.legacyActiveKey, jsonEncode(match('old-live', sides: points(4, 4)).toJson()));
      await prefs.setString(MatchStore.legacyPlayedKey, jsonEncode([match('old-1', sides: points(11, 9)).toJson()]));
      final s = store();
      expect((await s.readActive())!.id, 'old-live');
      expect([for (final m in await s.readPlayed()) m.id], ['old-1']);
      expect(await prefs.getString(MatchStore.legacyActiveKey), isNull);
      expect(await prefs.getString(MatchStore.legacyPlayedKey), isNull);
    });
  });

  group('upload', () {
    test('carries each event with the score and server around it', () {
      final m = match('m', rules: _bestOf3, sides: [...points(11, 0), Side.b]);
      final events = eventsForUpload(m);
      expect(events[10], containsPair('gameNumber', 1));
      expect(events[10]['scoreAfter'], [11, 0]);
      expect(events[11], containsPair('gameNumber', 2));
      expect(events[11]['scoreBefore'], [0, 0]);
      expect(events[11]['scoreAfter'], [0, 1]);
      expect(events.first['id'], m.events.first.id);
    });

    test('sends the result only once the match is over, as the replay has it', () {
      expect(uploadOf(match('m', sides: points(5, 3)))['result'], isNull);
      final done = uploadOf(match('m', sides: points(11, 8)));
      expect(done['result'], containsPair('outcome', 'completed'));
      expect(done['result']['sideAScores'], [11]);
      expect(done['result']['sideBScores'], [8]);
      expect(done['match']['sideA'], [{'isMe': true}]);
      expect(done['match']['sideB'], [{'userId': 'SKX-10519'}]);
    });

    test('the signature changes with every point, undo and new point', () {
      final m = match('m', sides: points(3, 2));
      final undone = m.copyWith(events: m.events.sublist(0, 4));
      final redone = undone.copyWith(events: [...undone.events, RecordedEvent(id: 'new', event: const RallyWon(Side.a), recordedAt: DateTime(2026))]);
      expect({syncSignature(m), syncSignature(undone), syncSignature(redone)}, hasLength(3));
      expect(syncSignature(m), syncSignature(LocalMatch.fromJson(m.toJson())));
    });
  });

  group('sync engine', () {
    test('a match scored online is created and marked synced', () async {
      final server = FakeSyncServer();
      final c = container(server, Net());
      final m = await scoredAndTracked(c, match('m1', sides: points(11, 7)));
      final s = c.read(casualSyncProvider)['m1']!;
      expect(s.phase, SyncPhase.synced);
      expect(s.serverId, 'srv-m1');
      expect(s.syncedSignature, syncSignature(m));
      expect(c.read(syncBadgeProvider('m1')), SyncBadge.synced);
      // Nothing changed: nothing is sent again.
      final sent = server.sent.length;
      await c.read(casualSyncProvider.notifier).run();
      expect(server.sent.length, sent);
    });

    test('offline, the match waits on the phone and goes when SkorX is back (#1, #3)', () async {
      final server = FakeSyncServer()..error = const ApiException(ApiException.network, 'offline');
      final net = Net()..online = false;
      final c = container(server, net);
      await scoredAndTracked(c, match('m1', sides: points(11, 4)));
      await c.read(casualSyncProvider.notifier).syncNow();
      expect(c.read(casualSyncProvider)['m1']!.phase, SyncPhase.pending);
      expect(c.read(connectivityProvider), NetStatus.offline);
      expect(c.read(syncBadgeProvider('m1')), SyncBadge.offline);
      expect(c.read(playedMatchesProvider).single.id, 'm1', reason: 'the match is never dropped');

      server.error = null;
      net.online = true;
      await c.read(connectivityProvider.notifier).check();
      await c.read(casualSyncProvider.notifier).run();
      expect(c.read(casualSyncProvider)['m1']!.phase, SyncPhase.synced);
      expect(c.read(syncStatsProvider).networkFailures, greaterThan(0));
    });

    test('points scored while a send is out go in the next one', () async {
      final server = FakeSyncServer();
      final c = container(server, Net());
      final first = match('m1', sides: points(3, 1));
      await c.read(playedMatchesProvider.notifier).record(first);
      await c.read(casualSyncProvider.notifier).track(first);
      final later = first.copyWith(events: [...first.events, RecordedEvent(id: 'late', event: const RallyWon(Side.b), recordedAt: DateTime(2026, 9, 27, 11))]);
      server.respond = (i) {
        // The scorer taps again while this request is in flight.
        if (i.match.events.length == 4) c.read(playedMatchesProvider.notifier).record(later);
        return SyncOutcome(clientRef: i.match.id, status: SyncStatus.synced, matchId: 'srv', syncVersion: ++server.version);
      };
      await c.read(casualSyncProvider.notifier).run();
      await c.read(casualSyncProvider.notifier).run();
      expect(server.sent.last.single.match.events.length, 5);
      expect(c.read(casualSyncProvider)['m1']!.syncedSignature, syncSignature(later));
    });

    test('a refused match is kept, backed off, and retried on request (#15, #16)', () async {
      final server = FakeSyncServer()
        ..respond = (i) => SyncOutcome(clientRef: i.match.id, status: SyncStatus.rejected, errorCode: 'RESULT_MISMATCH', errorMessage: 'The result does not match the points scored.');
      final c = container(server, Net());
      await scoredAndTracked(c, match('m1', sides: points(11, 2)));
      final s = c.read(casualSyncProvider)['m1']!;
      expect(s.phase, SyncPhase.failed);
      expect(s.error, contains('does not match'));
      expect(s.nextAttemptAt, isNotNull);

      final sent = server.sent.length;
      await c.read(casualSyncProvider.notifier).run();
      expect(server.sent.length, sent, reason: 'waits out its backoff');

      server.respond = null;
      await c.read(casualSyncProvider.notifier).retryFailed();
      expect(server.sent.length, sent + 1);
      expect(c.read(casualSyncProvider)['m1']!.phase, SyncPhase.synced);
    });

    test('a conflict waits for the scorer; keeping this phone\'s score forces it (#21)', () async {
      final server = FakeSyncServer();
      final theirs = ServerLog(
        events: [RecordedEvent(id: 'other-device', event: const RallyWon(Side.b), recordedAt: DateTime(2026, 9, 27, 10, 0, 5))],
        games: const [(0, 1)],
        syncVersion: 7,
        deviceId: 'phone-2',
      );
      server.respond = (i) => i.force
          ? SyncOutcome(clientRef: i.match.id, status: SyncStatus.synced, matchId: 'srv', syncVersion: 8)
          : SyncOutcome(clientRef: i.match.id, status: SyncStatus.conflict, matchId: 'srv', server: theirs);
      final c = container(server, Net());
      await scoredAndTracked(c, match('m1', sides: points(5, 5)));
      expect(c.read(casualSyncProvider)['m1']!.phase, SyncPhase.conflict);
      expect(c.read(syncBadgeProvider('m1')), SyncBadge.attention);
      expect(c.read(offlineSummaryProvider).conflicts, 1);

      final sent = server.sent.length;
      await c.read(casualSyncProvider.notifier).run();
      expect(server.sent.length, sent, reason: 'never overwritten without a choice');

      await c.read(casualSyncProvider.notifier).keepMine('m1');
      expect(server.sent.last.single.force, isTrue);
      expect(c.read(casualSyncProvider)['m1']!.phase, SyncPhase.synced);
      expect(c.read(casualSyncProvider)['m1']!.forceNext, isFalse);
    });

    test("using SkorX's score replaces this phone's events", () async {
      final server = FakeSyncServer();
      final theirs = ServerLog(
        events: [RecordedEvent(id: 'srv-1', event: const RallyWon(Side.b), recordedAt: DateTime(2026, 9, 27, 10, 0, 5))],
        games: const [(0, 1)],
        syncVersion: 7,
      );
      server.respond = (i) => i.match.events.length == 1
          ? SyncOutcome(clientRef: i.match.id, status: SyncStatus.alreadyProcessed, matchId: 'srv', syncVersion: 7)
          : SyncOutcome(clientRef: i.match.id, status: SyncStatus.conflict, matchId: 'srv', server: theirs);
      final c = container(server, Net());
      await scoredAndTracked(c, match('m1', sides: points(4, 2)));
      await c.read(casualSyncProvider.notifier).useServer('m1');
      final m = c.read(playedMatchesProvider).single;
      expect([for (final e in m.events) e.id], ['srv-1']);
      expect(server.sent.last.single.baseVersion, 7);
      expect(c.read(casualSyncProvider)['m1']!.phase, SyncPhase.synced);
    });

    test("another account's matches stay on the phone and are not sent (#23)", () async {
      final m = match('theirs', sides: points(11, 1));
      await SharedPreferencesAsync().setString(
        'skorx.casualSync',
        jsonEncode([const CasualSync(localId: 'theirs', ownerUserId: 'someone-else').toJson()]),
      );
      final server = FakeSyncServer();
      final c = container(server, Net());
      await c.read(playedMatchesProvider.notifier).record(m);
      await c.read(casualSyncProvider.notifier).run();
      expect(server.sent, isEmpty);
      expect(c.read(offlineSummaryProvider).otherAccounts, 1);
    });

    test('a backlog goes 10 matches per request (#25)', () async {
      final server = FakeSyncServer();
      final c = container(server, Net())..read(connectivityProvider);
      server.error = const ApiException(ApiException.network, 'offline');
      for (var i = 0; i < 23; i++) {
        await scoredAndTracked(c, match('b$i', sides: points(11, i % 9)));
      }
      server
        ..error = null
        ..sent.clear();
      await c.read(casualSyncProvider.notifier).syncNow();
      expect([for (final r in server.sent) r.length], [10, 10, 3]);
      expect(c.read(offlineSummaryProvider).synced, 23);
    });

    test('only synced matches are trimmed from the phone', () async {
      final server = FakeSyncServer()..error = const ApiException(ApiException.network, 'offline');
      final c = container(server, Net());
      final base = DateTime(2026, 1, 1);
      // Two old matches SkorX never received.
      for (var i = 0; i < 2; i++) {
        await scoredAndTracked(c, match('unsent$i', sides: points(11, 0), at: base.add(Duration(minutes: i))));
      }
      for (var i = 0; i < 205; i++) {
        await c.read(playedMatchesProvider.notifier).record(match('m$i', sides: points(11, 1), at: base.add(Duration(days: 1, minutes: i))));
      }
      final ids = {for (final m in c.read(playedMatchesProvider)) m.id};
      expect(ids, containsAll(['unsent0', 'unsent1']));
      expect(ids.length, 202);
    });
  });

  testWidgets('the scoring chip says offline and saved while SkorX cannot be reached', (tester) async {
    final server = FakeSyncServer()..error = const ApiException(ApiException.network, 'offline');
    final net = Net()..online = false;
    final c = container(server, net);
    await tester.runAsync(() => scoredAndTracked(c, match('m1', sides: points(3, 2))));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: buildSkorxTheme(brightness: Brightness.dark, accent: WorkspaceAccent.player),
        home: const Scaffold(body: Center(child: SyncStatusChip(localId: 'm1'))),
      ),
    ));
    await tester.runAsync(() => c.read(connectivityProvider.notifier).check());
    await tester.pump();
    expect(find.byKey(const Key('syncBadge.offline')), findsOneWidget);
    await tester.tap(find.byKey(const Key('savedChip')));
    await tester.pumpAndSettle();
    expect(find.textContaining('scoring continues'), findsOneWidget);
    expect(find.byKey(const Key('syncNow')), findsOneWidget);
  });
}

