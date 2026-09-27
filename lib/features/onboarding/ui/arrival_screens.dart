import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/typography.dart';
import '../../../shared/widgets.dart';
import '../../auth/auth_controller.dart';
import '../../settings/app_settings.dart';
import '../../workspace/workspace_controller.dart';
import '../onboarding_controller.dart';
import 'onboarding_kit.dart';
import 'player_photo.dart';

/// Where a signed-in player goes once they are through the door: the
/// workspace they were last in, or Player home.
String? _entryLocation(WidgetRef ref) {
  final workspaces = ref.read(workspaceControllerProvider);
  return workspaces.ready ? workspaces.entryLocation(workspaces.current) : null;
}

/// Goes to [_entryLocation] as soon as the workspaces are known.
Future<void> _enterApp(BuildContext context, WidgetRef ref) async {
  for (var i = 0; i < 50 && _entryLocation(ref) == null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
  if (context.mounted) context.go(_entryLocation(ref) ?? '/player/home');
}

// ─── Profile complete ────────────────────────────────────────────────────

/// A new player's profile is done: their player card builds itself on the
/// court, then SkorX welcomes them by name. Enter SkorX turns the card into
/// Home.
class ProfileCompleteScreen extends ConsumerStatefulWidget {
  const ProfileCompleteScreen({super.key});

  @override
  ConsumerState<ProfileCompleteScreen> createState() => _ProfileCompleteScreenState();
}

class _ProfileCompleteScreenState extends ConsumerState<ProfileCompleteScreen> with TickerProviderStateMixin {
  late final AnimationController _build = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  late final AnimationController _exit = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  bool _started = false;

  @override
  void dispose() {
    _build.dispose();
    _exit.dispose();
    super.dispose();
  }

  Future<void> _enter() async {
    if (_exit.isAnimating) return;
    HapticFeedback.mediumImpact();
    if (!reduceMotion(context)) await _exit.forward();
    if (mounted) await _enterApp(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    final user = ref.watch(currentUserProvider);
    final settings = ref.watch(appSettingsProvider);
    final name = user?.name ?? '';
    final first = user?.firstName ?? '';

    if (!_started && (ref.watch(launchIntroDoneProvider) || reduceMotion(context))) {
      _started = true;
      if (reduceMotion(context)) {
        _build.value = 1;
      } else {
        _build.forward();
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted) HapticFeedback.lightImpact();
        });
      }
    }

    return PopScope(
      canPop: false,
      child: OnboardScaffold(
        courtTop: 0.6,
        // The card and welcome sit in the middle of the screen, over the
        // court, rather than at the top with a gap under them.
        fillBody: true,
        body: AnimatedBuilder(
          animation: Listenable.merge([_build, _exit]),
          builder: (context, _) {
            final t = _build.value;
            final e = Curves.easeInOutCubic.transform(_exit.value);
            final text = _seg(t, 0.62, 0.9) * (1 - _seg(e, 0, 0.4));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),
                Center(
                  child: Transform.scale(
                    scale: 1 + e * 0.35,
                    child: Opacity(
                      opacity: 1 - _seg(e, 0.55, 1),
                      child: _PlayerCard(
                        key: const Key('playerCard'),
                        t: t,
                        morph: _seg(e, 0.15, 0.6),
                        name: name,
                        photoPath: settings.photoPath,
                        level: PlayerLevel.values.asNameMap()[settings.level],
                        formats: settings.formats,
                        hand: settings.hand,
                        city: settings.homeCity,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                Opacity(
                  opacity: text,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - text)),
                    child: Semantics(
                      header: true,
                      label: 'Welcome to SkorX, $first',
                      excludeSemantics: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('WELCOME TO SKORX,', style: OnboardType.statement(context, palette.ink, max: 44)),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${first.toUpperCase()}.',
                              maxLines: 1,
                              style: OnboardType.statement(context, palette.accentText, max: 64),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Opacity(
                  opacity: text,
                  child: Text('Your pickleball journey starts here.', style: OnboardType.body(palette.inkMuted)),
                ),
                const Spacer(flex: 3),
              ],
            );
          },
        ),
        bottom: AnimatedBuilder(
          animation: Listenable.merge([_build, _exit]),
          builder: (context, child) {
            final show = _seg(_build.value, 0.8, 1) * (1 - _seg(_exit.value, 0, 0.3));
            return IgnorePointer(
              ignoring: show < 0.5,
              child: Opacity(opacity: show, child: child),
            );
          },
          child: OnboardButton(
            key: const Key('enterSkorx'),
            label: 'Enter SkorX',
            icon: Icons.arrow_forward_rounded,
            onPressed: _enter,
          ),
        ),
      ),
    );
  }
}

double _seg(double t, double from, double to) => ((t - from) / (to - from)).clamp(0.0, 1.0);

/// The new player's card: photo, name, level, how they play and where.
/// Each part builds in with [t]; [morph] turns it into the SkorX Home mark
/// on the way into the app.
class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    super.key,
    required this.t,
    required this.morph,
    required this.name,
    required this.photoPath,
    required this.level,
    required this.formats,
    required this.hand,
    required this.city,
  });

  final double t;
  final double morph;
  final String name;
  final String? photoPath;
  final PlayerLevel? level;
  final List<String> formats;

  /// "Right" or "Left".
  final String? hand;
  final String? city;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    final width = math.min(MediaQuery.sizeOf(context).width - 48, 340.0);
    final card = Curves.easeOutCubic.transform(_seg(t, 0, 0.25));
    final photo = Curves.easeOutBack.transform(_seg(t, 0.15, 0.4));
    final nameIn = Curves.easeOutCubic.transform(_seg(t, 0.3, 0.52));
    final tags = Curves.easeOutCubic.transform(_seg(t, 0.45, 0.68));
    final parts = name.trim().split(RegExp(r'\s+'));
    final firstName = parts.first.toUpperCase();
    final rest = parts.skip(1).join(' ').toUpperCase();
    final play = switch ((formats.contains('singles'), formats.contains('doubles'))) {
      (true, true) => 'Singles & doubles',
      (true, false) => 'Singles',
      (false, true) => 'Doubles',
      _ => null,
    };

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const SkorxLogo(height: 26),
            const Spacer(),
            Text(hand == null ? 'PICKLEBALL PLAYER' : '${hand!.toUpperCase()}-HANDED PLAYER', style: SkorxType.label(color: palette.inkMuted, size: 11)),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Transform.scale(
              scale: photo,
              child: PlayerPhoto(name: name, photoPath: photoPath, size: 76),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Opacity(
                opacity: nameIn,
                child: Transform.translate(
                  offset: Offset(16 * (1 - nameIn), 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(firstName, maxLines: 1, style: SkorxType.headline(40, color: palette.ink)),
                      ),
                      if (rest.isNotEmpty)
                        Text(rest, maxLines: 1, overflow: TextOverflow.ellipsis, style: SkorxType.label(color: palette.inkMuted, size: 16)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Opacity(
          opacity: tags,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (level != null) _Tag(icon: Icons.signal_cellular_alt_rounded, label: level!.label),
              if (play != null) _Tag(icon: Icons.sports_tennis_rounded, label: play),
              if (city != null) _Tag(icon: Icons.place_outlined, label: city!),
              if (level == null && play == null && city == null) const _Tag(icon: Icons.bolt_rounded, label: 'New player'),
            ],
          ),
        ),
      ],
    );

    return Opacity(
      opacity: card,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..rotateX((1 - card) * 0.5)
          ..translateByDouble(0, 30 * (1 - card), 0, 1),
        child: Container(
          width: width,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: palette.isDark
                  ? [const Color(0xFF12243B), const Color(0xFF0A111B)]
                  : [Colors.white, const Color(0xFFEAF2FC)],
            ),
            border: Border.all(color: palette.isDark ? palette.court.withValues(alpha: 0.35) : palette.glassBorder),
            boxShadow: [
              BoxShadow(
                color: (palette.isDark ? palette.accent : Colors.black).withValues(alpha: palette.isDark ? 0.18 : 0.08),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Stack(
            children: [
              Opacity(opacity: 1 - morph, child: content),
              if (morph > 0)
                Positioned.fill(
                  child: Opacity(
                    opacity: morph,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SkorxLogo(height: 72, glow: true),
                          const SizedBox(height: 10),
                          Text('HOME', style: SkorxType.label(color: palette.ink, size: 16).copyWith(letterSpacing: 6)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.isDark ? const Color(0x14FFFFFF) : const Color(0x0F0B1C33),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: palette.isDark ? palette.ball : palette.accent),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: palette.ink, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─── Welcome back ────────────────────────────────────────────────────────

/// An existing player just verified their number on this phone: a moment
/// of recognition, then straight into the app. No questions.
class WelcomeBackScreen extends ConsumerStatefulWidget {
  const WelcomeBackScreen({super.key});

  static const hold = Duration(milliseconds: 1400);

  @override
  ConsumerState<WelcomeBackScreen> createState() => _WelcomeBackScreenState();
}

class _WelcomeBackScreenState extends ConsumerState<WelcomeBackScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(WelcomeBackScreen.hold, () {
      if (mounted) _enterApp(context, ref);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    final user = ref.watch(currentUserProvider);
    final photo = ref.watch(appSettingsProvider.select((s) => s.photoPath));
    return PopScope(
      canPop: false,
      child: OnboardScaffold(
        courtTop: 0.62,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.08),
            Reveal(child: PlayerPhoto(name: user?.name ?? '', photoPath: photo, size: 96)),
            const SizedBox(height: 28),
            Reveal(
              delay: const Duration(milliseconds: 120),
              child: Text('WELCOME BACK,', style: OnboardType.statement(context, palette.ink, max: 44)),
            ),
            Reveal(
              delay: const Duration(milliseconds: 200),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '${(user?.firstName ?? '').toUpperCase()}.',
                  maxLines: 1,
                  style: OnboardType.statement(context, palette.accentText, max: 72),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Reveal(
              delay: const Duration(milliseconds: 320),
              child: Row(
                children: [
                  BallLoader(color: palette.accent, width: 40, label: 'Opening SkorX'),
                  const SizedBox(width: 12),
                  Text('Getting your game ready', style: TextStyle(color: palette.inkMuted, fontSize: 15)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
