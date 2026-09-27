import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../sports/core/score_state.dart';
import '../../auth/auth_controller.dart';
import '../local_match.dart';
import 'live_court.dart';

enum CommentaryLevel {
  off('Off'),

  /// The score only: "4, 3, 2".
  basic('Basic'),

  /// Names and context: "Kamal and Smit win the point. 4, 3, 2."
  advanced('Advanced');

  const CommentaryLevel(this.label);
  final String label;
}

/// How live scoring sounds. Kept on the phone.
@immutable
class LiveSettings {
  const LiveSettings({this.sound = true, this.commentary = CommentaryLevel.basic, this.tutorialSeen = false});

  /// Taps click and commentary speaks. Off silences everything.
  final bool sound;
  final CommentaryLevel commentary;

  /// The three-step "tap the winning side" guide has been shown.
  final bool tutorialSeen;

  bool get speaks => sound && commentary != CommentaryLevel.off;

  LiveSettings copyWith({bool? sound, CommentaryLevel? commentary, bool? tutorialSeen}) => LiveSettings(
        sound: sound ?? this.sound,
        commentary: commentary ?? this.commentary,
        tutorialSeen: tutorialSeen ?? this.tutorialSeen,
      );

  Map<String, dynamic> toJson() => {'sound': sound, 'commentary': commentary.name, 'tutorialSeen': tutorialSeen};

  factory LiveSettings.fromJson(Map<String, dynamic> json) => LiveSettings(
        sound: json['sound'] as bool? ?? true,
        commentary: CommentaryLevel.values.asNameMap()[json['commentary']] ?? CommentaryLevel.basic,
        tutorialSeen: json['tutorialSeen'] as bool? ?? false,
      );
}

final liveSettingsProvider = NotifierProvider<LiveSettingsController, LiveSettings>(LiveSettingsController.new);

class LiveSettingsController extends Notifier<LiveSettings> {
  static const _key = 'skorx.liveScoring';

  /// Resolves once saved settings (if any) have been read.
  late final Future<void> ready;

  @override
  LiveSettings build() {
    ready = _restore();
    return const LiveSettings();
  }

  Future<void> _restore() async {
    final raw = await ref.read(preferencesProvider).getString(_key);
    if (raw == null) return;
    try {
      state = LiveSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }

  Future<void> update(LiveSettings Function(LiveSettings) change) async {
    state = change(state);
    await ref.read(preferencesProvider).setString(_key, jsonEncode(state.toJson()));
  }
}

/// Speaks commentary. Tests replace it with a recorder.
abstract class Commentator {
  Future<void> say(String text);
  Future<void> stop();
}

final commentatorProvider = Provider<Commentator>((ref) {
  final commentator = TtsCommentator();
  ref.onDispose(commentator.stop);
  return commentator;
});

/// The phone's own text-to-speech voice: brisk, like a stadium announcer.
/// A new line cuts off the last one so commentary never lags the rally.
class TtsCommentator implements Commentator {
  FlutterTts? _tts;

  Future<FlutterTts> _voice() async {
    final existing = _tts;
    if (existing != null) return existing;
    final tts = FlutterTts();
    await tts.setSpeechRate(0.52);
    await tts.setPitch(1.0);
    await tts.setVolume(1.0);
    return _tts = tts;
  }

  @override
  Future<void> say(String text) async {
    try {
      final tts = await _voice();
      await tts.stop();
      await tts.speak(text);
    } catch (_) {
      // No voice on this device: scoring carries on silently.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}

// ─── What to say ────────────────────────────────────────────────────────

/// A side as the announcer says it: the team name, or first names joined
/// with "and".
String spokenSide(LocalMatch match, Side side) {
  final team = side == Side.a ? match.details.teamA : match.details.teamB;
  if (team != null) return team;
  return match.names(side).map((n) => n.trim().split(' ').first).join(' and ');
}

/// The score call spoken with pauses: "4, 3, 2".
String spokenCall(LocalMatch match, ScoreState score) =>
    match.sport.engine.scoreCall(match.setup, score).replaceAll('-', ', ');

/// The line for [step], at [level]; null when nothing should be said.
String? commentaryFor(LocalMatch match, LiveStep step, CommentaryLevel level, {LiveStep? before}) {
  if (level == CommentaryLevel.off) return null;
  final score = step.score;
  final winner = step.rallyWinner;
  final events = step.events;
  final advanced = level == CommentaryLevel.advanced;
  final plural = match.names(Side.a).length > 1;
  String name(Side s) => spokenSide(match, s);
  String verb(Side s, String one, String many) =>
      plural && (s == Side.a ? match.details.teamA : match.details.teamB) == null ? many : one;
  String wins(Side s) => verb(s, 'wins', 'win');

  if (events.contains(LiveEvent.serveCorrected)) {
    return advanced ? 'Service corrected. ${name(score.serve.side)} to serve. ${spokenCall(match, score)}.' : spokenCall(match, score);
  }
  if (winner == null) return null;

  if (events.contains(LiveEvent.matchWon)) {
    final games = '${score.gamesWon(winner)}, ${score.gamesWon(winner.opponent)}';
    final last = score.currentGame;
    final points = '${last.of(winner)}, ${last.of(winner.opponent)}';
    if (!advanced) return 'Game and match. $points.';
    return match.rules.bestOf == 1
        ? 'Game and match, ${name(winner)}. $points.'
        : 'Game, set and match, ${name(winner)}, $games games.';
  }
  if (events.contains(LiveEvent.gameWon)) {
    final done = score.games[score.games.length - 2];
    final points = '${done.of(winner)}, ${done.of(winner.opponent)}';
    return advanced
        ? '${name(winner)} ${wins(winner)} game ${score.gameNumber - 1}, $points.'
        : 'Game. $points.';
  }

  final call = spokenCall(match, score);
  final parts = <String>[];
  if (events.contains(LiveEvent.sideOut) && !events.contains(LiveEvent.point)) {
    parts.add(advanced ? 'Side out. ${name(winner)} to serve.' : 'Side out.');
    parts.add('$call.');
  } else if (events.contains(LiveEvent.secondServer)) {
    parts.add(advanced ? '${name(winner)} ${wins(winner)} the rally. Second server.' : 'Second server.');
    parts.add('$call.');
  } else {
    if (advanced) {
      final prev = before?.score.currentGame;
      final now = score.currentGame;
      final tookLead = prev != null && prev.of(winner) <= prev.of(winner.opponent) && now.of(winner) > now.of(winner.opponent);
      parts.add(tookLead ? '${name(winner)} ${verb(winner, 'takes', 'take')} the lead.' : '${name(winner)} ${wins(winner)} the point.');
    }
    parts.add('$call.');
  }
  if (events.contains(LiveEvent.endsSwitched)) parts.add('Change ends.');
  for (final side in Side.values) {
    if (isMatchPoint(match, score, side)) {
      parts.add(advanced ? 'Match point, ${name(side)}.' : 'Match point.');
    } else if (isGamePoint(match, score, side)) {
      parts.add(advanced ? 'Game point, ${name(side)}.' : 'Game point.');
    }
  }
  return parts.join(' ');
}

String earlyEndCommentary(LocalMatch match) {
  final outcome = match.outcome!;
  final winner = spokenSide(match, outcome.winner);
  return switch (outcome.kind) {
    EarlyEnd.walkover => 'Walkover. $winner, the match.',
    EarlyEnd.retired => 'Retirement. $winner, the match.',
  };
}
