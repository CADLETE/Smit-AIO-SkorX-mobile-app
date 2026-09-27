import 'package:flutter/material.dart';

import '../../../shared/format.dart';

/// A billing date on the India calendar ("27 Sep 2027"). Pro periods start
/// and end by India time (the server's rule), so this reads the same on
/// every phone, whatever its time zone.
String billingDate(DateTime t) => longDate(t.toUtc().add(const Duration(hours: 5, minutes: 30)));

/// SkorX Pro, as sold to players (SkorX 2026 pricing, page 2 "For Players").
/// Mirrors the server's `src/subscriptions/player-plans.ts`, which is what
/// prices every order and decides access: these values are only for showing
/// the plans before a price is quoted.

/// A billing option for SkorX Pro. Prices are rupees, before GST.
enum ProPlan {
  monthly('PLAYER_PRO_MONTHLY', 'Monthly', 'month', 99, 1),
  annual('PLAYER_PRO_ANNUAL', 'Annual', 'year', 999, 12);

  const ProPlan(this.id, this.label, this.per, this.price, this.months);

  /// The server's plan id.
  final String id;
  final String label;

  /// "month" / "year", as in "₹99 + GST / month".
  final String per;
  final int price;
  final int months;

  static ProPlan? fromId(String? id) => values.where((p) => p.id == id).firstOrNull;

  /// `?plan=annual` in routes.
  static ProPlan? fromName(String? name) => values.where((p) => p.name == name).firstOrNull;

  ProPlan get other => this == monthly ? annual : monthly;
}

/// What paying yearly saves against twelve monthly payments: ₹189.
final int annualSaving = ProPlan.monthly.price * 12 - ProPlan.annual.price;

/// What Pro adds. [key] is the server's feature id (`canAccessFeature`).
enum ProFeature {
  casualLiveStream(
    'CASUAL_LIVE_STREAM',
    'Live Streaming of Casual Matches',
    'Casual match live streaming',
    Icons.live_tv_rounded,
    'Watch casual matches live on video, with the SkorX scoreboard alongside.',
  ),
  rivalStats(
    'RIVAL_STATS',
    'Rival Player Stats & Match History',
    'Rival player stats',
    Icons.compare_arrows_rounded,
    'See any player’s full record, form and matches, and your head-to-head with them.',
  ),
  matchAnalytics(
    'MATCH_ANALYTICS',
    'Match Analytics',
    'Match analytics',
    Icons.insights_rounded,
    'Get deeper insights into your performance, matches and progress: momentum, game flow, serve stats and trends.',
  ),
  leaderboard(
    'LEADERBOARD',
    'Leaderboards',
    'Leaderboards',
    Icons.leaderboard_rounded,
    'See who leads in your city, state, country and the world, in every format.',
  ),
  localRanking(
    'LOCAL_RANKING',
    'Local Rankings',
    'Local rankings',
    Icons.military_tech_rounded,
    'Know exactly where you rank in your city and state, and how you are moving.',
  );

  const ProFeature(this.key, this.title, this.short, this.icon, this.pitch);

  final String key;

  /// As on the pricing sheet: "Rival Player Stats & Match History".
  final String title;

  /// For lists and buttons: "Rival player stats".
  final String short;
  final IconData icon;

  /// One sentence on what it gives the player, for the upgrade prompt.
  final String pitch;

  static ProFeature? fromKey(String? key) => values.where((f) => f.key == key).firstOrNull;

  /// `?feature=matchAnalytics` in routes.
  static ProFeature? fromName(String? name) => values.where((f) => f.name == name).firstOrNull;
}

/// Free, forever: everything a player needs to play and keep their history.
const freeFeatures = <(String, IconData)>[
  ('Live Match Scoring', Icons.scoreboard_outlined),
  ('Match History', Icons.history_rounded),
  ('Tournament History', Icons.emoji_events_outlined),
  ('Court Booking', Icons.calendar_month_outlined),
  ('Achievements', Icons.workspace_premium_outlined),
];

/// The Free vs Pro table, in the order of the pricing sheet.
final comparisonRows = <(String, bool)>[
  for (final (label, _) in freeFeatures) (label, true),
  ('Live Streaming — Casual Matches', false),
  ('Rival Player Stats', false),
  ('Match Analytics', false),
  ('Leaderboards', false),
  ('Local Rankings', false),
];
