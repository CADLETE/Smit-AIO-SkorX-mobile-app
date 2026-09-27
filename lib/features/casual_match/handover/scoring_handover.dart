import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local_match.dart';

/// A request for another SkorX player to take over scoring on their own
/// phone. Only one phone scores a match at a time: while the request is
/// open, scoring is paused on this phone.
@immutable
class ScoringHandover {
  const ScoringHandover({required this.toName, required this.toPlayerId, required this.fromName, required this.requestedAt});

  final String toName;
  final String toPlayerId;
  final String fromName;
  final DateTime requestedAt;

  Map<String, dynamic> toJson() =>
      {'toName': toName, 'toPlayerId': toPlayerId, 'fromName': fromName, 'requestedAt': requestedAt.toIso8601String()};

  factory ScoringHandover.fromJson(Map<String, dynamic> json) => ScoringHandover(
        toName: json['toName'] as String,
        toPlayerId: json['toPlayerId'] as String,
        fromName: json['fromName'] as String,
        requestedAt: DateTime.parse(json['requestedAt'] as String),
      );
}

/// A request that has arrived for this player: the accept prompt shows it.
@immutable
class IncomingHandover {
  const IncomingHandover({required this.match, required this.request, this.simulated = false});

  /// The match as it stands, so the new scorer carries on from exactly here.
  final LocalMatch match;
  final ScoringHandover request;

  /// Debug builds deliver the request on the same phone to try the flow.
  final bool simulated;
}

enum HandoverAnswer { accepted, declined }

/// Moves scoring between phones. Becomes `POST /casual-matches/:id/handover`,
/// a push to the new scorer (FCM), and `POST /handovers/:id/accept|decline`
/// once casual matches sync; the sender learns the answer over the realtime
/// channel.
abstract class ScoringHandoverService {
  /// Whether requests can reach another phone. When false, scoring can
  /// still be handed over by giving someone this phone.
  bool get available;

  /// Sends [request] for [match] to the new scorer.
  Future<void> send(LocalMatch match, ScoringHandover request);

  /// Withdraws an unanswered request.
  Future<void> cancel(String matchId);

  /// Answers a request that arrived on this phone.
  Future<void> respond(IncomingHandover incoming, HandoverAnswer answer);

  /// Requests arriving for the signed-in player.
  Stream<IncomingHandover> get incoming;

  /// Answers to requests this phone sent, by match id.
  Stream<(String, HandoverAnswer)> get answers;

  void dispose();
}

final scoringHandoverServiceProvider = Provider<ScoringHandoverService>((ref) {
  final service = kDebugMode ? SimulatedHandoverService() : const OfflineHandoverService();
  ref.onDispose(service.dispose);
  return service;
});

/// Release builds until casual matches sync: no way to reach another phone.
class OfflineHandoverService implements ScoringHandoverService {
  const OfflineHandoverService();

  @override
  bool get available => false;

  @override
  Future<void> send(LocalMatch match, ScoringHandover request) async =>
      throw UnsupportedError('Handover to another phone needs match sync.');

  @override
  Future<void> cancel(String matchId) async {}

  @override
  Future<void> respond(IncomingHandover incoming, HandoverAnswer answer) async {}

  @override
  Stream<IncomingHandover> get incoming => const Stream.empty();

  @override
  Stream<(String, HandoverAnswer)> get answers => const Stream.empty();

  @override
  void dispose() {}
}

/// Debug builds: the "other phone" is this one. A sent request arrives here
/// after a moment, as it would on the new scorer's phone, so the whole flow
/// (paused scoring, accept prompt, carrying on) can be tried on one device.
class SimulatedHandoverService implements ScoringHandoverService {
  SimulatedHandoverService({this.delay = const Duration(milliseconds: 1200)});

  final Duration delay;
  final _incoming = StreamController<IncomingHandover>.broadcast();
  final _answers = StreamController<(String, HandoverAnswer)>.broadcast();
  final _pending = <String, Timer>{};

  @override
  bool get available => true;

  @override
  Future<void> send(LocalMatch match, ScoringHandover request) async {
    _pending[match.id]?.cancel();
    _pending[match.id] = Timer(delay, () {
      _pending.remove(match.id);
      _incoming.add(IncomingHandover(match: match, request: request, simulated: true));
    });
  }

  @override
  Future<void> cancel(String matchId) async => _pending.remove(matchId)?.cancel();

  @override
  Future<void> respond(IncomingHandover incoming, HandoverAnswer answer) async => _answers.add((incoming.match.id, answer));

  @override
  Stream<IncomingHandover> get incoming => _incoming.stream;

  @override
  Stream<(String, HandoverAnswer)> get answers => _answers.stream;

  @override
  void dispose() {
    for (final t in _pending.values) {
      t.cancel();
    }
    _incoming.close();
    _answers.close();
  }
}
