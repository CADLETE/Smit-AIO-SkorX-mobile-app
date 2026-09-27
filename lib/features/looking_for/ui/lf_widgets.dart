import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/api/api_exception.dart';
import '../../../design/design.dart';
import '../data/looking_for.dart';
import '../looking_for_controller.dart';

IconData lfIcon(String icon) => switch (icon) {
  'player' => Icons.person_add_alt_1_rounded,
  'team' => Icons.groups_rounded,
  'match' => Icons.sports_tennis_rounded,
  'tournament' => Icons.emoji_events_rounded,
  'ground' => Icons.stadium_rounded,
  'club' => Icons.holiday_village_rounded,
  'referee' => Icons.sports_rounded,
  'scorer' => Icons.scoreboard_rounded,
  'commentator' => Icons.mic_rounded,
  'streamer' => Icons.videocam_rounded,
  'academy' => Icons.school_rounded,
  'sponsor' => Icons.handshake_rounded,
  _ => Icons.radar_rounded,
};

/// A category's accent pair; groups share one so the feed reads at a glance.
List<Color> lfColors(SxColors c, String categoryId) => switch (categoryId) {
  'player' || 'team' || 'match' => [c.voltFill, c.olive],
  'tournament' || 'sponsor' => [c.deep, c.blue],
  'referee' || 'scorer' => [c.blue, c.cyan],
  'commentator' || 'streamer' => [c.cyan, c.blue],
  _ => [c.olive, c.deep],
};

(SxState, String) lfState(LfPost p) => switch (p.status) {
  LfStatus.open => (SxState.upcoming, 'OPEN'),
  LfStatus.responsesReceived => (SxState.upcoming, p.responseCount == 1 ? '1 RESPONSE' : '${p.responseCount} RESPONSES'),
  LfStatus.partiallyFilled => (SxState.registered, '${p.quantityFilled} OF ${p.quantityRequired} FILLED'),
  LfStatus.filled => (SxState.won, 'FILLED'),
  LfStatus.expired => (SxState.completed, 'EXPIRED'),
  LfStatus.cancelled => (SxState.cancelled, 'CANCELLED'),
};

class LfStatusMark extends StatelessWidget {
  const LfStatusMark(this.post, {super.key});

  final LfPost post;

  @override
  Widget build(BuildContext context) {
    final (state, word) = lfState(post);
    return StateMark(state, word: word, size: 11);
  }
}

/// Back, or to Explore when the screen was opened directly (shared link, notification).
void lfBack(BuildContext context) => context.canPop() ? context.pop() : context.go('/player/explore');

void lfNote(BuildContext context, String message) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));

void lfError(BuildContext context, Object error) =>
    lfNote(context, error is ApiException ? error.message : 'Something went wrong. Please try again.');

/// "Today 8:00 PM · 90 min", or null when the post has no time.
String? lfWhen(LfPost p) {
  if (p.whenLabel == null) return null;
  final end = p.endsAt;
  if (end != null && p.startsAt != null && end.day == p.startsAt!.day) {
    final h = end.hour % 12 == 0 ? 12 : end.hour % 12;
    return '${p.whenLabel}–$h:${end.minute.toString().padLeft(2, '0')} ${end.hour < 12 ? 'AM' : 'PM'}';
  }
  if (p.durationMins != null) {
    final d = p.durationMins!;
    return '${p.whenLabel} · ${d >= 60 && d % 60 == 0
        ? '${d ~/ 60} h'
        : d >= 60
        ? '${d ~/ 60} h ${d % 60} min'
        : '$d min'}';
  }
  return p.whenLabel;
}

String lfDistance(LfPost p) {
  final d = p.distanceKm;
  if (d == null) return p.city;
  if (p.approximate && d < 1) return p.city;
  return '${p.approximate ? '~' : ''}${d < 10 ? d.toStringAsFixed(1).replaceAll('.0', '') : d.round()} km';
}

/// One requirement in a feed: a big category badge, the title, one strip
/// of when / where / cost, and the one action. A faint court in the
/// category's colour ties the card to the sport.
class LfPostCard extends ConsumerWidget {
  const LfPostCard({super.key, required this.post, this.onChanged, this.showReasons = false});

  final LfPost post;

  /// Called after an action changed this post (so a list can patch it).
  final ValueChanged<LfPost>? onChanged;
  final bool showReasons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final p = post;
    final colors = lfColors(c, p.categoryId);
    final when = lfWhen(p);
    final place = p.placeName ?? p.city;
    return Semantics(
      container: true,
      label: '${p.categoryLabel}: ${p.title}',
      child: Tappable(
        key: Key('lfCard-${p.id}'),
        onTap: () => context.push('/player/looking-for/${p.id}'),
        child: Container(
          decoration: BoxDecoration(
            gradient: c.card,
            borderRadius: BorderRadius.circular(Sx.radiusLg),
            border: Border.all(color: c.cardEdge),
            boxShadow: c.cardShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Sx.radiusLg),
            child: Stack(
              children: [
                Positioned(
                  right: -26,
                  top: -8,
                  width: 150,
                  height: 96,
                  child: ExcludeSemantics(
                    child: Transform.rotate(
                      angle: -0.2,
                      child: CustomPaint(
                        painter: CourtPainter(color: colors.first.withValues(alpha: c.isDark ? 0.16 : 0.22)),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Sx.s16, Sx.s16, Sx.s16, Sx.s12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LfCategoryBadge(categoryId: p.categoryId, icon: p.categoryIcon),
                          const SizedBox(width: Sx.s12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        (p.subcategoryLabel ?? p.categoryLabel).toUpperCase(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: SxType.label(c.inkMuted, size: 10.5),
                                      ),
                                    ),
                                    LfStatusMark(p),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 17)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Sx.s12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: Sx.s12, vertical: 10),
                        decoration: BoxDecoration(
                          color: c.surfaceAlt.withValues(alpha: c.isDark ? 0.45 : 0.75),
                          borderRadius: BorderRadius.circular(Sx.radiusSm),
                        ),
                        child: Wrap(
                          spacing: Sx.s16,
                          runSpacing: 6,
                          children: [
                            if (when != null) _Meta(icon: Icons.schedule_rounded, text: when),
                            _Meta(
                              icon: Icons.place_outlined,
                              text: p.distanceKm == null || p.distanceKm! < 1 && p.approximate ? place : '$place · ${lfDistance(p)}',
                            ),
                            if (p.paymentLabel != null)
                              _Meta(icon: Icons.currency_rupee_rounded, text: p.paymentLabel!.replaceFirst('₹', '')),
                            if (p.skillLabel != null) _Meta(icon: Icons.trending_up_rounded, text: p.skillLabel!),
                            if (p.gender != 'any') _Meta(icon: Icons.person_outline_rounded, text: p.gender == 'male' ? 'Men' : 'Women'),
                          ],
                        ),
                      ),
                      if (showReasons && p.reasons.isNotEmpty) ...[
                        const SizedBox(height: Sx.s8),
                        Row(
                          children: [
                            Icon(Icons.auto_awesome_rounded, size: 14, color: c.volt),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Fits you · ${p.reasons.join(' · ')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SxType.caption(c.volt, size: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: Sx.s12),
                      Row(
                        children: [
                          Expanded(child: _Footer(post: p)),
                          const SizedBox(width: Sx.s8),
                          LfCardAction(post: p, onChanged: onChanged),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A category's mark: its icon on its gradient, with a court corner.
class LfCategoryBadge extends StatelessWidget {
  const LfCategoryBadge({super.key, required this.categoryId, required this.icon, this.size = 46});

  final String categoryId;
  final String icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final colors = lfColors(c, categoryId);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(colors[0], Colors.white, 0.12)!, colors[1]],
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: c.glowOf(colors[0], strength: 0.45),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.3),
        child: Stack(
          children: [
            Positioned(
              right: -size * 0.3,
              bottom: -size * 0.22,
              width: size * 0.95,
              height: size * 0.72,
              child: ExcludeSemantics(
                child: CustomPaint(painter: CourtPainter(color: Colors.white.withValues(alpha: 0.22), topInset: 0.14)),
              ),
            ),
            Center(
              child: Icon(lfIcon(icon), size: size * 0.48, color: colors[0] == c.voltFill ? c.onVolt : Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c.inkMuted),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SxType.caption(c.ink, size: 13).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// Places as dots (●●○ "1 left") when there are a few; otherwise who posted it.
class _Footer extends StatelessWidget {
  const _Footer({required this.post});

  final LfPost post;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final p = post;
    // Dots stay readable (and beside the action button) up to four places.
    if (p.quantityRequired >= 2 && p.quantityRequired <= 4 && p.status.active) {
      return LayoutBuilder(
        builder: (context, box) {
          final label = Text(
            '${p.openPlaces} of ${p.quantityRequired} open',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SxType.caption(c.inkMuted, size: 12.5),
          );
          // Too narrow for the dots beside the action: the words alone.
          if (box.maxWidth < p.quantityRequired * 14 + 48) return label;
          return Row(
            children: [
              for (var i = 0; i < p.quantityRequired; i++)
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < p.quantityFilled ? c.volt : null,
                    border: Border.all(color: i < p.quantityFilled ? c.volt : c.inkFaint, width: 1.5),
                  ),
                ),
              const SizedBox(width: 4),
              Flexible(child: label),
            ],
          );
        },
      );
    }
    if (p.quantityRequired > 4 && p.status.active) {
      return Text(
        '${p.openPlaces} of ${p.quantityRequired} places open',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: SxType.caption(c.inkMuted, size: 12.5),
      );
    }
    return LayoutBuilder(
      builder: (context, box) => Row(
        children: [
          // Beside a wide action there may be room for the name only.
          if (box.maxWidth >= 90) ...[SxAvatar(name: p.postedBy.name, size: 22), const SizedBox(width: 6)],
          Flexible(
            child: Text(
              p.postedBy.kind == 'self'
                  ? p.postedBy.name
                  : '${p.postedBy.name} · ${p.postedBy.kind == 'organization' ? 'Organizer' : 'Tournament'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SxType.caption(c.inkMuted, size: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// The card's one action: I'm Interested, or where things stand.
class LfCardAction extends ConsumerWidget {
  const LfCardAction({super.key, required this.post, this.onChanged});

  final LfPost post;
  final ValueChanged<LfPost>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final p = post;
    Widget note(String text, Color color) => Text(text, style: SxType.label(color, size: 12));
    if (p.isOwner) return note(p.responseCount == 0 ? 'YOUR REQUEST' : 'YOURS · ${p.responseCount}', c.info);
    final mine = p.myResponse;
    if (mine != null && mine.status != LfResponseStatus.withdrawn) {
      return switch (mine.status) {
        LfResponseStatus.accepted => note("YOU'RE IN", c.volt),
        LfResponseStatus.declined => note('NOT THIS TIME', c.inkMuted),
        _ => note('INTERESTED ✓', c.info),
      };
    }
    if (!p.status.active) return const SizedBox.shrink();
    // A quiet pill: every card has one, so it must not outshout Post.
    return Semantics(
      button: true,
      label: "I'm interested",
      excludeSemantics: true,
      child: Tappable(
        key: Key('lfInterested-${p.id}'),
        radius: 18,
        haptic: true,
        onTap: () async {
          final r = await showInterestSheet(context, ref, p);
          if (r != null) onChanged?.call(p.copyWith(myResponse: LfMyResponseRef(r.id, r.status)));
        },
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: c.volt.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.volt.withValues(alpha: 0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.front_hand_rounded, size: 15, color: c.volt),
              const SizedBox(width: 6),
              Text("I'm interested", style: SxType.label(c.volt, size: 12.5, weight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The lightweight response form. Returns the response, or null if closed.
Future<LfResponse?> showInterestSheet(BuildContext context, WidgetRef ref, LfPost post) {
  return showSxSheet<LfResponse>(context, builder: (_) => _InterestSheet(post: post));
}

class _InterestSheet extends ConsumerStatefulWidget {
  const _InterestSheet({required this.post});

  final LfPost post;

  @override
  ConsumerState<_InterestSheet> createState() => _InterestSheetState();
}

class _InterestSheetState extends ConsumerState<_InterestSheet> {
  late final _message = TextEditingController(text: _suggested(widget.post));
  bool _available = true;
  bool _busy = false;

  static String _suggested(LfPost p) => switch (p.categoryId) {
    'player' || 'match' => "Hi, I'm interested in joining this match.",
    'team' => "Hi, I'd like to join your team.",
    'referee' => "Hi, I'm available to referee.",
    'scorer' => "Hi, I'm available to score.",
    'commentator' => "Hi, I'd like to commentate.",
    'streamer' => "Hi, I can help with the stream.",
    _ => "Hi, I'm interested.",
  };

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(lfActionsProvider).respond(widget.post.id, message: _message.text, availabilityConfirmed: _available);
      if (!mounted) return;
      Navigator.of(context).pop(r);
      lfNote(context, '${widget.post.postedBy.name.split(' ').first} will see your interest. We\'ll tell you when they answer.');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        lfError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final p = widget.post;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("I'M INTERESTED", style: SxType.label(c.inkMuted)),
          const SizedBox(height: Sx.s4),
          Text(p.title, style: SxType.heading(c.ink, size: 19)),
          if (lfWhen(p) != null) ...[
            const SizedBox(height: Sx.s4),
            Text('${lfWhen(p)} · ${p.placeLabel}', style: SxType.caption(c.inkMuted)),
          ],
          const SizedBox(height: Sx.s16),
          TextField(
            key: const Key('lfInterestMessage'),
            controller: _message,
            maxLength: 500,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Message (optional)'),
          ),
          if (p.startsAt != null)
            SwitchListTile.adaptive(
              key: const Key('lfAvailable'),
              contentPadding: EdgeInsets.zero,
              value: _available,
              onChanged: (v) => setState(() => _available = v),
              title: Text('I can make ${p.whenLabel ?? 'it'}', style: SxType.body(c.ink)),
            ),
          const SizedBox(height: Sx.s8),
          Text(
            'Your name, level and SkorX record are shared with the poster. Your phone number is not, unless you choose to share it after they accept.',
            style: SxType.caption(c.inkMuted, size: 12.5),
          ),
          const SizedBox(height: Sx.s16),
          SxButton(key: const Key('lfSendInterest'), label: 'Send interest', busy: _busy, onPressed: _send),
        ],
      ),
    );
  }
}

Future<void> showLfReportSheet(BuildContext context, WidgetRef ref, LfPost post) async {
  final reason = await showSxSheet<String>(
    context,
    builder: (sheet) {
      final c = sheet.sx;
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
        children: [
          Text('REPORT', style: SxType.label(c.inkMuted)),
          const SizedBox(height: Sx.s4),
          Text("What's wrong with this request?", style: SxType.heading(c.ink)),
          const SizedBox(height: Sx.s12),
          SxRows(
            children: [
              for (final e in lfReportReasons.entries)
                SxRow(key: Key('lfReport-${e.key}'), label: e.value, onTap: () => Navigator.of(sheet).pop(e.key)),
            ],
          ),
          const SizedBox(height: Sx.s12),
          Text(
            'Reports are private. SkorX reviews them, and posts reported by several people are hidden until then.',
            style: SxType.caption(c.inkMuted, size: 12.5),
          ),
        ],
      );
    },
  );
  if (reason == null || !context.mounted) return;
  try {
    await ref.read(lfActionsProvider).report(post.id, reason);
    if (context.mounted) lfNote(context, 'Thanks. SkorX will review this request.');
  } catch (e) {
    if (context.mounted) lfError(context, e);
  }
}

/// Shares the SkorX link with the request's key facts, so it reads well even
/// where the link does not open the app.
Future<void> shareLfPost(BuildContext context, WidgetRef ref, LfPost p) async {
  try {
    final url = await ref.read(lfActionsProvider).shareLink(p.id, channel: 'system');
    final lines = [
      'Looking For on SkorX: ${p.title}',
      [?lfWhen(p), p.placeLabel].join(' · '),
      ?p.paymentLabel,
      url,
    ];
    await SharePlus.instance.share(ShareParams(text: lines.join('\n'), subject: p.title));
  } catch (e) {
    if (context.mounted) lfError(context, e);
  }
}

Future<void> copyLfLink(BuildContext context, WidgetRef ref, LfPost p) async {
  final url = await ref.read(lfActionsProvider).shareLink(p.id, channel: 'copy');
  await Clipboard.setData(ClipboardData(text: url));
  if (context.mounted) lfNote(context, 'Link copied');
}

/// A row of small selectable options (skill, gender, radius…).
class LfChoiceRow<T> extends StatelessWidget {
  const LfChoiceRow({super.key, required this.options, required this.isSelected, required this.onTap, this.keyPrefix = 'lfOpt'});

  final List<(T, String)> options;
  final bool Function(T) isSelected;
  final ValueChanged<T> onTap;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: Sx.s8,
    runSpacing: Sx.s8,
    children: [
      for (final (v, label) in options) SxChip(key: Key('$keyPrefix-$label'), label: label, selected: isSelected(v), onTap: () => onTap(v)),
    ],
  );
}
