import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../data/tournaments.dart';

/// The tournament's state, told in the status language.
(SxState, String) tournamentState(Tournament t, DateTime now, {bool registered = false}) {
  final phase = t.phase(now);
  if (phase == TournamentPhase.live) return (SxState.live, 'LIVE NOW');
  if (phase == TournamentPhase.completed) return (SxState.completed, 'COMPLETED');
  if (registered) return (SxState.registered, 'REGISTERED');
  return switch (t.window(now)) {
    RegistrationWindow.open => (SxState.upcoming, 'REGISTRATION OPEN'),
    RegistrationWindow.closingSoon => (SxState.upcoming, 'CLOSES ${_closes(t.registrationDeadline, now)}'),
    RegistrationWindow.full => (SxState.cancelled, 'FULL'),
    RegistrationWindow.closed => (SxState.completed, 'ENTRIES CLOSED'),
  };
}

/// "TODAY", "TOMORROW", "SUN".
String _closes(DateTime d, DateTime now) => switch (daysBetween(now, d)) {
      0 => 'TODAY',
      1 => 'TOMORROW',
      _ => weekdaysShort[d.weekday - 1].toUpperCase(),
    };

String formatsLabel(Tournament t) =>
    t.formats.map((f) => f.label).join(' · ') + (t.levels.length == 1 ? ' · ${t.levels.first}' : '');

/// The SkorX tournament card: a date block, the net, and only what decides
/// whether to open it. Name, date, venue, format, fee, status.
class TournamentCard extends StatelessWidget {
  const TournamentCard({super.key, required this.tournament, required this.onTap, this.registered = false});

  final Tournament tournament;
  final VoidCallback onTap;
  final bool registered;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final t = tournament;
    final now = DateTime.now();
    final (state, word) = tournamentState(t, now, registered: registered);
    return Semantics(
      button: true,
      label: '${t.name}, ${dateRange(t.start, t.end)}, ${t.venue}, ${t.city}, ${word.toLowerCase()}',
      excludeSemantics: true,
      child: SxBlock(
        onTap: onTap,
        padding: const EdgeInsets.all(Sx.s16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 62,
                decoration: BoxDecoration(
                  gradient: state == SxState.live ? c.heat : c.hero,
                  borderRadius: BorderRadius.circular(Sx.radius),
                  boxShadow: c.glowOf(state == SxState.live ? c.live : c.blue, strength: 0.6),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${t.start.day}', style: SxType.hero(40, Colors.white)),
                    const SizedBox(height: 2),
                    Text(monthsShort[t.start.month - 1].toUpperCase(),
                        style: SxType.label(Colors.white.withValues(alpha: 0.85), size: 12)),
                  ],
                ),
              ),
              const SizedBox(width: Sx.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name.toUpperCase(), maxLines: 2, style: SxType.title(c.ink, size: 21)),
                    const SizedBox(height: Sx.s4),
                    Text('${t.venue}, ${t.city}', maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted)),
                    Text(formatsLabel(t), maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted)),
                    const SizedBox(height: Sx.s12),
                    Row(
                      children: [
                        Expanded(child: Align(alignment: Alignment.centerLeft, child: StateMark(state, word: word, size: 12))),
                        const SizedBox(width: Sx.s8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: c.voltFill.withValues(alpha: c.isDark ? 0.14 : 0.3),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            t.minFee == 0 ? 'Free' : 'from ${formatInr(t.minFee)}',
                            style: SxType.heading(c.isDark ? c.volt : c.ink, size: 14),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
