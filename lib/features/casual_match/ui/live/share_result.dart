import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../design/design.dart';
import '../../../../shared/widgets.dart' show SkorxLogo;
import '../../../auth/auth_controller.dart';
import '../../live/match_analytics.dart';
import '../../local_match.dart';
import '../../scoring_controller.dart';
import '../scoring_labels.dart';
import 'live_sheets.dart' show showBlurredSheet;

/// Where shared results send people. One place to change it.
const skorxWebsite = 'https://skorx.in';

/// The message that travels with the image: the result in two lines, then a
/// line about SkorX and where to get it.
String shareText(LocalMatch match) {
  final winner = match.winner!;
  final score = match.score;
  final where = match.details.courtLabel;
  final head = switch (match.outcome?.kind) {
    EarlyEnd.walkover => '🏆 ${match.teamLabel(winner)} won by walkover against ${match.teamLabel(winner.opponent)}',
    EarlyEnd.retired =>
      '🏆 ${match.teamLabel(winner)} won against ${match.teamLabel(winner.opponent)} (retired)',
    null => '🏆 ${match.teamLabel(winner)} beat ${match.teamLabel(winner.opponent)} '
        '${match.rules.bestOf == 1 ? '${score.games.last.of(winner)}–${score.games.last.of(winner.opponent)}' : '${score.gamesWon(winner)}–${score.gamesWon(winner.opponent)}'}',
  };
  final games = match.outcome?.kind == EarlyEnd.walkover
      ? null
      : score.games.map((g) => '${g.of(winner)}-${g.of(winner.opponent)}').join(', ');
  return [
    head,
    [matchTypeLabel(match), ?where, if (games != null && match.rules.bestOf > 1) games].join(' · '),
    'Match ID: ${match.displayCode}',
    '',
    'Scored live on SkorX, the app for pickleball scoring, ratings and tournaments. Get SkorX: $skorxWebsite',
  ].join('\n');
}

/// Shows the share card, then hands it and [shareText] to the phone's share sheet.
Future<void> shareMatchResult(BuildContext context, LocalMatch match, MatchAnalytics analytics) =>
    showBlurredSheet<void>(context, (_) => _SharePreview(match: match, analytics: analytics));

class _SharePreview extends StatefulWidget {
  const _SharePreview({required this.match, required this.analytics});

  final LocalMatch match;
  final MatchAnalytics analytics;

  @override
  State<_SharePreview> createState() => _SharePreviewState();
}

class _SharePreviewState extends State<_SharePreview> {
  final _card = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final boundary = _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      // 360 x 450 logical at 3x: a 1080 x 1350 image, the 4:5 feeds prefer.
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/skorx-${widget.match.displayCode}.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: shareText(widget.match),
        subject: 'Match result · ${matchTypeLabel(widget.match)}',
      ));
    } catch (_) {
      // No share target or no image: fall back to the text on the clipboard.
      await Clipboard.setData(ClipboardData(text: shareText(widget.match)));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open sharing. Result copied instead.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Share result', style: SxType.title(c.ink, size: 28)),
          const SizedBox(height: 4),
          Text('This image and a short summary go to WhatsApp, Instagram or wherever you pick.', style: SxType.body(c.inkMuted, size: 14)),
          const SizedBox(height: Sx.s16),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: AspectRatio(
                aspectRatio: 360 / 450,
                child: FittedBox(
                  child: RepaintBoundary(
                    key: _card,
                    child: ShareCard(match: widget.match, analytics: widget.analytics),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: Sx.s16),
          SxButton(key: const Key('shareNow'), label: 'Share', icon: Icons.ios_share_rounded, busy: _busy, onPressed: _share),
        ],
      ),
    );
  }
}

/// The shareable result: 360 x 450, always on the dark SkorX look so it
/// reads the same in any feed.
class ShareCard extends ConsumerWidget {
  const ShareCard({super.key, required this.match, required this.analytics});

  final LocalMatch match;
  final MatchAnalytics analytics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const c = SxColors.dark;
    final winner = match.winner!;
    final loser = winner.opponent;
    final score = match.score;
    final walkover = match.outcome?.kind == EarlyEnd.walkover;
    final single = match.rules.bestOf == 1;
    final big = walkover
        ? null
        : single
            ? (score.games.last.of(winner), score.games.last.of(loser), 'POINTS')
            : (score.gamesWon(winner), score.gamesWon(loser), 'GAMES');
    final where = match.details.courtLabel;
    final scorers = scorersOf(match, ref.watch(currentUserProvider));
    final scorer = scorers.isEmpty ? null : scorers.map((s) => s.name).join(', ');
    final white = Colors.white;

    return SizedBox(
      width: 360,
      height: 450,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFF060A10), c.deep, Color.lerp(c.deep, c.blue, 0.55)!],
            stops: const [0, 0.55, 1],
          ),
        ),
        child: Stack(
          children: [
            // Court lines behind everything, and the ball.
            Positioned.fill(child: CustomPaint(painter: CourtPainter(color: white.withValues(alpha: 0.07), topInset: 0.26))),
            const Positioned(right: -26, top: 70, child: SxBall(size: 110, float: false, glow: true)),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SkorxLogo(height: 24),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: c.voltFill, borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          match.outcome == null ? 'MATCH RESULT' : match.outcome!.kind.label.toUpperCase(),
                          style: SxType.label(c.onVolt, size: 11),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text([matchTypeLabel(match), ?where].join(' · ').toUpperCase(),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.label(white.withValues(alpha: 0.7), size: 11.5)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.emoji_events_rounded, color: c.voltFill, size: 18),
                      const SizedBox(width: 6),
                      Text('WINNER', style: SxType.label(c.voltFill, size: 12)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      SideDps(names: match.names(winner), size: 34, edge: c.voltFill),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(match.teamLabel(winner),
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: SxType.title(white, size: 26)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('def. ${match.teamLabel(loser)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.body(white.withValues(alpha: 0.75), size: 13.5)),
                  const Spacer(),
                  if (big != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${big.$1}', style: SxType.hero(78, c.voltFill)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          child: Text('–', style: SxType.hero(44, white.withValues(alpha: 0.55))),
                        ),
                        Text('${big.$2}', style: SxType.hero(78, white)),
                        const SizedBox(width: 10),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(big.$3, style: SxType.label(white.withValues(alpha: 0.7), size: 11)),
                        ),
                      ],
                    )
                  else
                    Text('WON BY WALKOVER', style: SxType.verdict(34, c.voltFill)),
                  if (!walkover && !single) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final (i, g) in score.games.indexed)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: white.withValues(alpha: 0.18)),
                            ),
                            child: Text('G${i + 1}  ${g.of(winner)}–${g.of(loser)}', style: SxType.label(white, size: 11.5)),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (analytics.hasRallies)
                    Row(
                      children: [
                        _CardStat(value: clockText(analytics.duration), label: 'TIME'),
                        _CardStat(value: '${analytics.rallies.length}', label: 'RALLIES'),
                        _CardStat(value: '${analytics.stats[winner]!.bestRun}', label: 'BEST RUN'),
                        _CardStat(value: '${analytics.leadChanges}', label: 'LEAD CHANGES'),
                      ],
                    ),
                  const SizedBox(height: 14),
                  Container(height: 1, color: white.withValues(alpha: 0.16)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(match.displayCode, style: SxType.label(white.withValues(alpha: 0.85), size: 11)),
                            if (scorer != null)
                              Text('Scored by $scorer',
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(white.withValues(alpha: 0.6), size: 10.5)),
                          ],
                        ),
                      ),
                      Text('skorx.in', style: SxType.label(c.voltFill, size: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardStat extends StatelessWidget {
  const _CardStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: SxType.number(20, Colors.white, weight: FontWeight.w800)),
            Text(label, maxLines: 1, style: SxType.label(Colors.white.withValues(alpha: 0.6), size: 9)),
          ],
        ),
      );
}
