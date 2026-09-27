import 'dart:math';

import 'package:flutter/foundation.dart';

import 'match_setup.dart';

/// Where a match was played.
enum MatchContext {
  casual('C', 'Casual'),
  tournament('T', 'Tournament'),
  league('L', 'League');

  const MatchContext(this.letter, this.label);
  final String letter;
  final String label;
}

/// A match's public ID, readable by people and sortable by software:
///
///     SKX-PCMD-260927-7K3QX
///     │   ││└┴─ category: MD = Men's Doubles (see [categoryCode])
///     │   │└─── context: C casual, T tournament, L league
///     │   └──── sport: P pickleball, B badminton, T table tennis
///     │         date the match started, YYMMDD
///     └──────── brand                  5 random characters
///
/// Every kind of match is told apart from the ID alone: `SKX-PT??` is any
/// pickleball tournament match, `????XD` any mixed doubles, `KS`/`KD`/`KX`
/// any kids' match, `WS`/`WD` women's, `MS`/`MD` men's. The random part uses
/// Crockford base 32 (no I, L, O or U), so it is safe to read out loud and
/// hard to mistype.
@immutable
class MatchCode {
  const MatchCode({
    required this.sport,
    required this.context,
    required this.format,
    required this.division,
    required this.date,
    required this.suffix,
  });

  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const _sports = {'pickleball': 'P', 'badminton': 'B', 'table_tennis': 'T'};

  /// Sport id, e.g. "pickleball".
  final String sport;
  final MatchContext context;
  final MatchFormat format;
  final Division division;

  /// The day the match started (local time).
  final DateTime date;
  final String suffix;

  /// A new code for a match starting [at].
  factory MatchCode.generate({
    required String sport,
    required MatchContext context,
    required MatchFormat format,
    required Division division,
    required DateTime at,
    Random? random,
  }) {
    final r = random ?? Random.secure();
    final suffix = String.fromCharCodes([for (var i = 0; i < 5; i++) _alphabet.codeUnitAt(r.nextInt(_alphabet.length))]);
    return MatchCode(
      sport: sport,
      context: context,
      format: format,
      division: division,
      date: DateTime(at.year, at.month, at.day),
      suffix: suffix,
    );
  }

  /// Two letters for format and division.
  static String categoryCode(MatchFormat format, Division division) => switch ((format, division)) {
        (MatchFormat.mixed, Division.kids) => 'KX',
        (MatchFormat.mixed, _) => 'XD',
        (MatchFormat.singles, Division.men) => 'MS',
        (MatchFormat.singles, Division.women) => 'WS',
        (MatchFormat.singles, Division.kids) => 'KS',
        (MatchFormat.singles, Division.open) => 'OS',
        (MatchFormat.doubles, Division.men) => 'MD',
        (MatchFormat.doubles, Division.women) => 'WD',
        (MatchFormat.doubles, Division.kids) => 'KD',
        (MatchFormat.doubles, Division.open) => 'OD',
      };

  static (MatchFormat, Division)? _category(String code) {
    for (final f in MatchFormat.values) {
      for (final d in Division.forFormat(f)) {
        if (categoryCode(f, d) == code) return (f, d);
      }
    }
    return null;
  }

  @override
  String toString() {
    String two(int n) => n.toString().padLeft(2, '0');
    final day = '${two(date.year % 100)}${two(date.month)}${two(date.day)}';
    return 'SKX-${_sports[sport] ?? 'X'}${context.letter}${categoryCode(format, division)}-$day-$suffix';
  }

  /// Reads a code back; null if it is not a SkorX match ID.
  static MatchCode? tryParse(String input) {
    final m = RegExp(r'^SKX-([A-Z])([A-Z])([A-Z]{2})-(\d{2})(\d{2})(\d{2})-([0-9A-Z]{5})$').firstMatch(input.trim().toUpperCase());
    if (m == null) return null;
    final sport = _sports.entries.where((e) => e.value == m.group(1)).map((e) => e.key).firstOrNull;
    final context = MatchContext.values.where((c) => c.letter == m.group(2)).firstOrNull;
    final category = _category(m.group(3)!);
    if (sport == null || context == null || category == null) return null;
    return MatchCode(
      sport: sport,
      context: context,
      format: category.$1,
      division: category.$2,
      date: DateTime(2000 + int.parse(m.group(4)!), int.parse(m.group(5)!), int.parse(m.group(6)!)),
      suffix: m.group(7)!,
    );
  }

  @override
  bool operator ==(Object other) => other is MatchCode && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;
}
