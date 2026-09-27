import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../design/design.dart';
import '../data/match.dart';

/// The match on video, when it is being streamed.
///
/// A poster first, so opening a live match costs no data and no web view:
/// the YouTube player is only made when the viewer taps play, and goes away
/// again with the close button. Rotating the phone, or the fullscreen
/// button, fills the screen.
class StreamWindow extends StatefulWidget {
  const StreamWindow({super.key, required this.broadcast});

  final LiveBroadcast broadcast;

  @override
  State<StreamWindow> createState() => _StreamWindowState();
}

class _StreamWindowState extends State<StreamWindow> {
  YoutubePlayerController? _player;

  /// The last try did not load (no internet, or YouTube did not answer).
  bool _failed = false;

  void _play() {
    final player = YoutubePlayerController(
      params: const YoutubePlayerParams(showFullscreenButton: true, strictRelatedVideos: true),
    );
    setState(() {
      _player = player;
      _failed = false;
    });
    // Back to the poster, saying why, rather than a black box that never plays.
    player.loadVideoById(videoId: widget.broadcast.videoId).catchError((Object _) {
      if (!mounted || _player != player) return;
      player.close();
      setState(() {
        _player = null;
        _failed = true;
      });
    });
  }

  void _stop() {
    _player?.close();
    setState(() => _player = null);
  }

  @override
  void didUpdateWidget(StreamWindow old) {
    super.didUpdateWidget(old);
    if (old.broadcast.videoId != widget.broadcast.videoId && _player != null) {
      _player!.close();
      _player = null;
    }
  }

  @override
  void dispose() {
    _player?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final player = _player;
    return Container(
      key: const Key('streamWindow'),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(Sx.radiusLg),
        border: Border.all(color: c.cardEdge),
        boxShadow: c.glowOf(c.live, strength: 0.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: player == null
                ? _Poster(broadcast: widget.broadcast, failed: _failed, onPlay: _play)
                : YoutubePlayer(controller: player, aspectRatio: 16 / 9),
          ),
          _Bar(broadcast: widget.broadcast, playing: player != null, onClose: _stop),
        ],
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.broadcast, required this.failed, required this.onPlay});

  final LiveBroadcast broadcast;

  /// The last try did not load: say so, and play means try again.
  final bool failed;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      button: true,
      label: failed
          ? 'The stream did not load. Try again'
          : 'Watch the live stream${broadcast.title == null ? '' : ', ${broadcast.title}'}',
      excludeSemantics: true,
      child: GestureDetector(
        key: const Key('streamPlay'),
        behavior: HitTestBehavior.opaque,
        onTap: onPlay,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [const Color(0xFF060A10), c.deep, Color.lerp(c.deep, c.blue, 0.5)!],
                ),
              ),
            ),
            // A court seen from the stands, faint behind the play button.
            ExcludeSemantics(
              child: CustomPaint(painter: _StandsCourt(Colors.white.withValues(alpha: 0.14), c.cyan.withValues(alpha: 0.12))),
            ),
            const Positioned(left: Sx.s12, top: Sx.s12, child: SxHeroTag(text: 'LIVE STREAM', live: true)),
            Center(
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: c.brand, boxShadow: c.glowOf(c.voltFill, strength: 1.4)),
                child: Icon(failed ? Icons.refresh_rounded : Icons.play_arrow_rounded, size: failed ? 36 : 42, color: c.onVolt),
              ),
            ),
            Positioned(
              left: Sx.s12,
              right: Sx.s12,
              bottom: Sx.s12,
              child: Text(
                failed ? 'The stream did not load. Check your internet and tap to try again.' : 'Tap to watch the match live',
                textAlign: TextAlign.center,
                style: SxType.caption(Colors.white.withValues(alpha: 0.8), size: 13).copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A court in perspective, as a camera behind the baseline sees it.
class _StandsCourt extends CustomPainter {
  _StandsCourt(this.line, this.kitchen);

  final Color line;
  final Color kitchen;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Offset p(double x, double y) {
      // x across (0–1), y from the far baseline (0) to the near one (1).
      final top = h * 0.3, bottom = h * 1.05;
      final yy = top + (bottom - top) * y;
      final half = w * (0.2 + 0.32 * y);
      return Offset(w / 2 + (x - 0.5) * 2 * half, yy);
    }

    Path quad(double y0, double y1) => Path()
      ..moveTo(p(0, y0).dx, p(0, y0).dy)
      ..lineTo(p(1, y0).dx, p(1, y0).dy)
      ..lineTo(p(1, y1).dx, p(1, y1).dy)
      ..lineTo(p(0, y1).dx, p(0, y1).dy)
      ..close();

    const k = 7 / 44;
    canvas.drawPath(quad(0.5 - k, 0.5 + k), Paint()..color = kitchen);
    final paint = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawPath(quad(0, 1), paint);
    for (final y in [0.5 - k, 0.5 + k]) {
      canvas.drawLine(p(0, y), p(1, y), paint);
    }
    canvas.drawLine(p(0.5, 0), p(0.5, 0.5 - k), paint);
    canvas.drawLine(p(0.5, 0.5 + k), p(0.5, 1), paint);
    canvas.drawLine(p(-0.04, 0.5), p(1.04, 0.5), paint..strokeWidth = 2.6);
  }

  @override
  bool shouldRepaint(_StandsCourt old) => old.line != line || old.kitchen != kitchen;
}

class _Bar extends StatelessWidget {
  const _Bar({required this.broadcast, required this.playing, required this.onClose});

  final LiveBroadcast broadcast;
  final bool playing;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      color: const Color(0xFF0B1320),
      padding: const EdgeInsets.fromLTRB(Sx.s12, Sx.s8, Sx.s4, Sx.s8),
      child: Row(
        children: [
          Icon(Icons.smart_display_rounded, size: 20, color: c.live),
          const SizedBox(width: Sx.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  broadcast.title ?? 'Live stream',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SxType.body(Colors.white, size: 14).copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  [?broadcast.channel, 'YouTube'].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SxType.caption(Colors.white.withValues(alpha: 0.6), size: 12),
                ),
              ],
            ),
          ),
          if (playing)
            Semantics(
              button: true,
              label: 'Close the stream',
              excludeSemantics: true,
              child: Tappable(
                key: const Key('streamClose'),
                onTap: onClose,
                radius: 20,
                child: const SizedBox.square(dimension: 40, child: Icon(Icons.close_rounded, color: Colors.white, size: 20)),
              ),
            ),
        ],
      ),
    );
  }
}
