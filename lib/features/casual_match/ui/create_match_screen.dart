import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../../../sports/core/match_rules.dart';
import '../../../sports/core/score_state.dart';
import '../../../sports/core/sport_definition.dart';
import '../../../sports/sport_registry.dart';
import '../../auth/auth_controller.dart';
import '../../settings/app_settings.dart';
import '../data/match_setup.dart';
import '../scoring_controller.dart';
import 'court_top_view.dart';
import 'player_picker_sheet.dart';
import 'rules_controls.dart';

/// Sports a player can start a match in. Mirrors the API's `playable` flag
/// (only pickleball today); becomes `GET /sports` once the sport list syncs.
final playableSportsProvider = Provider<List<SportDefinition>>((ref) => [pickleball]);

/// Starting a casual match, built for speed at the courtside:
///
/// 1. What are you playing: format (singles, doubles, mixed) and division
///    (men's, women's, kids), two taps. The division decides the player pool.
/// 2. Setup on one screen: court, players placed straight onto a top-down
///    court (starred players first), who serves, the rules, and an optional
///    YouTube stream.
///
/// The last type, rules, court and stream settings are remembered, so a
/// regular's next match is "Continue", four players, "Start".
class CreateMatchScreen extends ConsumerStatefulWidget {
  const CreateMatchScreen({super.key, this.initialCategoryId});

  /// Match type chosen from a shortcut ("mens_doubles", "singles"...).
  final String? initialCategoryId;

  @override
  ConsumerState<CreateMatchScreen> createState() => _CreateMatchScreenState();
}

class _CreateMatchScreenState extends ConsumerState<CreateMatchScreen> {
  late SportDefinition _sport;
  MatchFormat _format = MatchFormat.doubles;
  Division? _division;
  bool _onSetup = false;

  /// Set once the player changes anything, so remembered settings that load
  /// late never overwrite their choices.
  bool _touched = false;
  bool _starting = false;

  late MatchRules _rules;
  final _court = TextEditingController(text: 'Court 1');
  final _venue = TextEditingController();
  String? _teamA;
  String? _teamB;

  /// Court order: index 0 stands in the right-hand service court.
  List<MatchPlayer?> _a = [null, null];
  List<MatchPlayer?> _b = [null, null];
  bool _aOnLeft = true;
  Side _server = Side.a;

  bool _streamOn = false;
  final _streamTitle = TextEditingController();
  final _streamKey = TextEditingController();
  final _streamServer = TextEditingController(text: YouTubeStream.defaultServer);
  StreamPrivacy _privacy = StreamPrivacy.unlisted;
  bool _overlay = true;
  bool _showKey = false;

  @override
  void initState() {
    super.initState();
    _sport = ref.read(playableSportsProvider).first;
    // The player's own defaults (Settings › Default match settings) win;
    // otherwise a single game, with best of 3 one tap away.
    final defaults = ref.read(appSettingsProvider);
    final preferred = defaults.matchRules;
    _rules = preferred != null && _sport.rulesProblem(preferred) == null
        ? preferred
        : _sport.defaultRules.copyWith(bestOf: 1);
    final preferredFormat = MatchFormat.values.asNameMap()[defaults.matchFormat];
    if (preferredFormat != null) _format = preferredFormat;
    final initial = widget.initialCategoryId == null ? null : parseCategoryId(widget.initialCategoryId!);
    if (initial != null) {
      _format = initial.$1;
      _division = initial.$2;
      _onSetup = _division != null;
    }
    _resizeTeams();
    _loadMemory();
  }

  Future<void> _loadMemory() async {
    await ref.read(matchSetupMemoryProvider.notifier).ready;
    final m = ref.read(matchSetupMemoryProvider);
    if (!mounted || _touched) return;
    final defaults = ref.read(appSettingsProvider);
    setState(() {
      if (widget.initialCategoryId == null && defaults.matchFormat == null) {
        _format = m.format ?? _format;
        final division = m.division;
        _division = division != null && Division.forFormat(_format).contains(division) ? division : null;
        _resizeTeams();
      }
      final rules = m.rules;
      if (defaults.matchRules == null && rules != null && _sport.rulesProblem(rules) == null) _rules = rules;
      if (m.court != null) _court.text = m.court!;
      if (m.venue != null) _venue.text = m.venue!;
      final s = m.stream;
      if (s != null) {
        _privacy = s.privacy;
        _streamKey.text = s.streamKey;
        _streamServer.text = s.serverUrl;
        _overlay = s.showScoreOverlay;
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_court, _venue, _streamTitle, _streamKey, _streamServer]) {
      c.dispose();
    }
    super.dispose();
  }

  void _update(VoidCallback change) => setState(() {
        _touched = true;
        change();
      });

  // ─── Players ─────────────────────────────────────────────────────────

  List<MatchPlayer?> _team(Side side) => side == Side.a ? _a : _b;

  List<MatchPlayer> get _onCourt => [..._a, ..._b].whereType<MatchPlayer>().toList();

  /// Keeps players who still fit after the format or division changed.
  void _resizeTeams() {
    final n = _format.playersPerSide;
    final division = _division;
    List<MatchPlayer?> fit(List<MatchPlayer?> team) => [
          for (var i = 0; i < n; i++)
            i < team.length && team[i] != null && (division == null || team[i]!.fits(division)) ? team[i] : null,
        ];
    _a = fit(_a);
    _b = fit(_b);
  }

  /// In mixed doubles a partner of known gender needs the other gender.
  Gender? _requiredGender(Side side, int index) {
    if (_format != MatchFormat.mixed || _format.playersPerSide < 2) return null;
    final partner = _team(side)[1 - index];
    return switch (partner?.gender) {
      Gender.male => Gender.female,
      Gender.female => Gender.male,
      null => null,
    };
  }

  String _emptyLabel(Side side, int index) {
    if (_format != MatchFormat.mixed) return 'Add player';
    final kids = _division == Division.kids;
    return switch (_requiredGender(side, index)) {
      Gender.male => kids ? 'Add boy' : 'Add man',
      Gender.female => kids ? 'Add girl' : 'Add woman',
      null => 'Add player',
    };
  }

  String _teamName(Side side) => (side == Side.a ? _teamA : _teamB) ?? (side == Side.a ? 'Team A' : 'Team B');

  Future<void> _pick(Side side, int index) async {
    final division = _division;
    if (division == null) return;
    final current = _team(side)[index];
    final required = _requiredGender(side, index);
    final picked = await showPlayerPicker(
      context,
      division: division,
      title: _format.playersPerSide == 1 ? 'Add ${side == Side.a ? 'player 1' : 'player 2'}' : 'Add to ${_teamName(side)}',
      taken: {for (final p in _onCourt) if (p != current) p.id},
      requiredGender: required,
      askGender: _format == MatchFormat.mixed && required == null,
    );
    if (picked == null || !mounted) return;
    HapticFeedback.selectionClick();
    _update(() {
      final team = [..._team(side)]..[index] = picked;
      side == Side.a ? _a = team : _b = team;
    });
  }

  void _swapPartners(Side side) => _update(() {
        final team = _team(side).reversed.toList();
        side == Side.a ? _a = team : _b = team;
      });

  /// [side]'s [index] player serves first: in pickleball the first serve is
  /// hit from the right-hand court, so they move there.
  void _setServer(Side side, int index) {
    HapticFeedback.selectionClick();
    _update(() {
      _server = side;
      if (index != 0) {
        final team = _team(side).reversed.toList();
        side == Side.a ? _a = team : _b = team;
      }
    });
  }

  Future<void> _slotTapped(Side side, int index) async {
    final player = _team(side)[index];
    if (player == null) return _pick(side, index);
    final serving = side == _server && index == 0;
    final doubles = _format.playersPerSide == 2;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.sx.canvas,
      builder: (context) => _SlotActions(player: player, serving: serving, doubles: doubles),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'serve':
        _setServer(side, index);
      case 'switch':
        _swapPartners(side);
      case 'replace':
        await _pick(side, index);
      case 'remove':
        _update(() {
          final team = [..._team(side)]..[index] = null;
          side == Side.a ? _a = team : _b = team;
        });
    }
  }

  Future<void> _renameTeam(Side side) async {
    final controller = TextEditingController(text: side == Side.a ? _teamA : _teamB);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Name ${side == Side.a ? 'Team A' : 'Team B'}'),
        content: TextField(
          key: const Key('teamNameField'),
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Net Ninjas'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    final trimmed = name.trim();
    _update(() => side == Side.a ? _teamA = trimmed.isEmpty ? null : trimmed : _teamB = trimmed.isEmpty ? null : trimmed);
  }

  // ─── Start ───────────────────────────────────────────────────────────

  int get _missing => [..._a, ..._b].where((p) => p == null).length;

  /// Why the match cannot start yet, or null.
  String? get _blocker {
    if (_missing > 0) return _missing == 1 ? 'Add 1 more player' : 'Add $_missing more players';
    if (_format == MatchFormat.mixed) {
      for (final side in Side.values) {
        final g = _team(side).map((p) => p?.gender).toList();
        if (g[0] != null && g[0] == g[1]) return '${_teamName(side)} needs a man and a woman';
      }
    }
    if (_streamOn && _streamKey.text.trim().isEmpty) return 'Add the YouTube stream key, or turn streaming off';
    return null;
  }

  String _nameOf(MatchPlayer p) {
    if (!p.isMe) return p.name;
    final user = ref.read(currentUserProvider);
    return user == null || user.name.isEmpty ? 'You' : user.name;
  }

  String get _autoStreamTitle {
    String side(List<MatchPlayer?> t) => t.map((p) => p == null ? '?' : _nameOf(p).split(' ').first).join(' / ');
    final court = _court.text.trim();
    return '${side(_a)} vs ${side(_b)}${court.isEmpty ? '' : ' · $court'}';
  }

  Future<void> _start() async {
    final division = _division;
    if (_starting || _blocker != null || division == null) return;
    setState(() => _starting = true);
    final a = _a.whereType<MatchPlayer>().toList();
    final b = _b.whereType<MatchPlayer>().toList();
    final stream = _streamOn
        ? YouTubeStream(
            title: _streamTitle.text.trim().isEmpty ? _autoStreamTitle : _streamTitle.text.trim(),
            privacy: _privacy,
            streamKey: _streamKey.text.trim(),
            serverUrl: _streamServer.text.trim().isEmpty ? YouTubeStream.defaultServer : _streamServer.text.trim(),
            showScoreOverlay: _overlay,
          )
        : null;
    String? blank(String s) => s.trim().isEmpty ? null : s.trim();
    final details = MatchDetails(
      division: division,
      court: blank(_court.text),
      venue: blank(_venue.text),
      teamA: _teamA,
      teamB: _teamB,
      aStartsLeft: _aOnLeft,
      sideAIds: [for (final p in a) p.id],
      sideBIds: [for (final p in b) p.id],
      stream: stream,
    );
    await ref.read(matchSetupMemoryProvider.notifier).remember(MatchSetupMemory(
          format: _format,
          division: division,
          rules: _rules,
          court: blank(_court.text),
          venue: blank(_venue.text),
          stream: YouTubeStream(
            title: '',
            privacy: _privacy,
            streamKey: _streamKey.text.trim(),
            serverUrl: _streamServer.text.trim(),
            showScoreOverlay: _overlay,
          ),
        ));
    await ref.read(scoringControllerProvider.notifier).start(NewMatch(
          sportId: _sport.id,
          categoryId: categoryIdFor(_format, division),
          sideA: [for (final p in a) _nameOf(p)],
          sideB: [for (final p in b) _nameOf(p)],
          rules: _rules,
          firstServer: _server,
          locationName: details.courtLabel,
          details: details,
        ));
    if (mounted) context.go('/player/match');
  }

  // ─── Build ───────────────────────────────────────────────────────────

  String get _typeLabel {
    final d = _division;
    if (d == null) return _format.label;
    return switch (d) {
      Division.open => _format.label,
      Division.kids => 'Kids ${_format.label}',
      _ => '${d.label} ${_format.label}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return PopScope(
      canPop: !_onSetup || widget.initialCategoryId != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _onSetup = false);
      },
      child: Scaffold(
        backgroundColor: c.canvas,
        body: SafeArea(
          bottom: false,
          child: AnimatedSwitcher(
            duration: Sx.medium,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: Offset(child.key == const ValueKey('setup') ? 0.08 : -0.08, 0), end: Offset.zero)
                    .animate(a),
                child: child,
              ),
            ),
            child: _onSetup ? KeyedSubtree(key: const ValueKey('setup'), child: _setupStep(context)) : _typeStep(context),
          ),
        ),
      ),
    );
  }

  void _close() => context.canPop() ? context.pop() : context.go('/player/home');

  Widget _typeStep(BuildContext context) {
    final c = context.sx;
    final divisions = Division.forFormat(_format);
    return Column(
      key: const ValueKey('type'),
      children: [
        SxBackBar(title: 'New match', onBack: _close),
        Expanded(
          child: SxWidth(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s24),
              children: [
                SxReveal(child: Text('What are you\nplaying?', style: SxType.title(c.ink, size: 40))),
                const SizedBox(height: Sx.s8),
                SxReveal(
                  index: 1,
                  child: Text('Pick the format, then who is playing. The player search shows only that group.',
                      style: SxType.body(c.inkMuted)),
                ),
                const SizedBox(height: Sx.s24),
                _StepLabel(number: 1, text: 'FORMAT'),
                const SizedBox(height: Sx.s12),
                SxReveal(
                  index: 2,
                  child: Row(
                    children: [
                      for (final (i, f) in MatchFormat.values.indexed) ...[
                        if (i > 0) const SizedBox(width: Sx.s12),
                        Expanded(
                          child: _FormatTile(
                            format: f,
                            selected: _format == f,
                            onTap: () => _update(() {
                              _format = f;
                              if (_division != null && !Division.forFormat(f).contains(_division)) _division = null;
                              _resizeTeams();
                            }),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: Sx.s32),
                _StepLabel(number: 2, text: 'DIVISION'),
                const SizedBox(height: Sx.s12),
                SxReveal(
                  index: 3,
                  child: Row(
                    children: [
                      for (final (i, d) in divisions.indexed) ...[
                        if (i > 0) const SizedBox(width: Sx.s12),
                        Expanded(
                          child: _DivisionTile(
                            division: d,
                            format: _format,
                            selected: _division == d,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              _update(() {
                                _division = d;
                                _resizeTeams();
                                _onSetup = true;
                              });
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _BottomBar(
          child: SxButton(
            key: const Key('continueSetup'),
            label: _division == null ? 'Choose a division' : 'Continue · $_typeLabel',
            icon: Icons.arrow_forward_rounded,
            onPressed: _division == null ? null : () => setState(() => _onSetup = true),
          ),
        ),
      ],
    );
  }

  Widget _setupStep(BuildContext context) {
    final c = context.sx;
    final doubles = _format.playersPerSide == 2;
    final blocker = _blocker;
    return Column(
      children: [
        SxBackBar(
          title: _typeLabel,
          onBack: () => setState(() => _onSetup = false),
          actions: [
            SxChip(
              key: const Key('changeType'),
              label: 'Change',
              icon: Icons.tune_rounded,
              selected: false,
              onTap: () => setState(() => _onSetup = false),
            ),
          ],
        ),
        Expanded(
          child: SxWidth(
            child: ListView(
              key: const Key('setupList'),
              padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s32),
              children: [
                // Court
                const SxSection('Court'),
                SxReveal(
                  child: _CourtFields(
                    court: _court,
                    venue: _venue,
                    onChanged: () => _update(() {}),
                  ),
                ),
                const SizedBox(height: Sx.section),

                // Players on court
                SxSection(doubles ? 'Teams & positions' : 'Players & positions'),
                SxReveal(
                  index: 1,
                  child: CourtTopView(
                    teamA: _a,
                    teamB: _b,
                    aOnLeft: _aOnLeft,
                    server: _server,
                    onSlotTap: _slotTapped,
                    teamNameA: _teamA ?? (doubles ? null : 'Player 1'),
                    teamNameB: _teamB ?? (doubles ? null : 'Player 2'),
                    onTeamNameTap: doubles ? _renameTeam : null,
                    emptyLabel: _emptyLabel,
                  ),
                ),
                const SizedBox(height: Sx.s12),
                Wrap(
                  spacing: Sx.s8,
                  runSpacing: Sx.s8,
                  alignment: WrapAlignment.center,
                  children: [
                    SxChip(
                      key: const Key('swapEnds'),
                      label: 'Swap ends',
                      icon: Icons.swap_horiz_rounded,
                      selected: false,
                      onTap: () => _update(() => _aOnLeft = !_aOnLeft),
                    ),
                    if (doubles)
                      for (final side in Side.values)
                        SxChip(
                          key: Key('switch-${side.name}'),
                          label: 'Switch ${_teamName(side)}',
                          icon: Icons.swap_vert_rounded,
                          selected: false,
                          onTap: () => _swapPartners(side),
                        ),
                  ],
                ),
                const SizedBox(height: Sx.s8),
                Text(
                  'Tap a spot to add or change a player. The first serve is hit from the right-hand court.',
                  textAlign: TextAlign.center,
                  style: SxType.caption(c.inkMuted, size: 12),
                ),
                const SizedBox(height: Sx.section),

                // Who serves
                const SxSection('First serve'),
                _ServePicker(
                  teams: {Side.a: _a, Side.b: _b},
                  server: _server,
                  nameOf: (p) => p.isMe ? 'You' : p.name,
                  teamName: _teamName,
                  onServer: _setServer,
                  onPickSide: (side) => _update(() => _server = side),
                ),
                const SizedBox(height: Sx.section),

                // Rules
                const SxSection('Match format'),
                RulesBlock(sport: _sport, rules: _rules, onChanged: (r) => _update(() => _rules = r)),
                const SizedBox(height: Sx.section),

                // Stream
                const SxSection('Live stream'),
                _StreamBlock(
                  on: _streamOn,
                  onToggle: (v) => _update(() => _streamOn = v),
                  title: _streamTitle,
                  titleHint: _autoStreamTitle,
                  streamKey: _streamKey,
                  server: _streamServer,
                  privacy: _privacy,
                  onPrivacy: (p) => _update(() => _privacy = p),
                  overlay: _overlay,
                  onOverlay: (v) => _update(() => _overlay = v),
                  showKey: _showKey,
                  onShowKey: () => setState(() => _showKey = !_showKey),
                  onChanged: () => setState(() {}),
                ),
              ],
            ),
          ),
        ),
        _BottomBar(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Only SkorX players can confirm a match; a guest keeps it off
              // everyone's stats and rating (docs/CASUAL-VERIFICATION.md).
              if ([..._a, ..._b].any((p) => p?.isGuest ?? false)) ...[
                Row(
                  key: const Key('guestNotice'),
                  children: [
                    Icon(Icons.person_off_outlined, size: 16, color: c.caution),
                    const SizedBox(width: Sx.s8),
                    Expanded(
                      child: Text(
                        "Guests can't confirm, so this match won't count toward stats or rating.",
                        style: SxType.caption(c.inkMuted, size: 12.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Sx.s8),
              ] else if (_missing == 0) ...[
                Row(
                  children: [
                    Icon(Icons.verified_outlined, size: 16, color: c.inkMuted),
                    const SizedBox(width: Sx.s8),
                    Expanded(
                      child: Text(
                        'The other players get a request to confirm. It counts once they do.',
                        style: SxType.caption(c.inkMuted, size: 12.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Sx.s8),
              ],
              Row(
                children: [
                  Icon(blocker == null ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                      size: 16, color: blocker == null ? c.volt : c.inkMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      key: const Key('startHint'),
                      blocker ?? '$_typeLabel · ${_rules.describe()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SxType.caption(blocker == null ? c.ink : c.inkMuted, size: 12.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Sx.s8),
              SxButton(
                key: const Key('startMatch'),
                label: 'Start match',
                icon: Icons.sports_tennis_rounded,
                busy: _starting,
                onPressed: blocker == null ? _start : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Step 1 pieces ───────────────────────────────────────────────────────

class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(gradient: c.cool, shape: BoxShape.circle),
          child: Text('$number', style: SxType.number(13, Colors.white, weight: FontWeight.w800)),
        ),
        const SizedBox(width: Sx.s8),
        Text(text, style: SxType.label(c.inkMuted, size: 13)),
      ],
    );
  }
}

/// A big square choice: gradient and glow when chosen.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({super.key, required this.selected, required this.onTap, required this.label, required this.child, this.caption});

  final bool selected;
  final VoidCallback onTap;
  final String label;
  final String? caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final ink = selected ? c.onVolt : c.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Tappable(
        onTap: onTap,
        radius: Sx.radius,
        haptic: true,
        child: AnimatedContainer(
          duration: Sx.medium,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(Sx.s8, Sx.s16, Sx.s8, Sx.s12),
          decoration: BoxDecoration(
            gradient: selected ? c.brand : c.card,
            borderRadius: BorderRadius.circular(Sx.radius),
            border: Border.all(color: selected ? Colors.transparent : c.cardEdge),
            boxShadow: selected ? c.glowOf(c.voltFill) : c.cardShadow,
          ),
          child: Column(
            children: [
              IconTheme(data: IconThemeData(color: ink, size: 30), child: SizedBox(height: 40, child: Center(child: child))),
              const SizedBox(height: Sx.s8),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: SxType.heading(ink, size: 15).copyWith(fontWeight: FontWeight.w800)),
              if (caption != null)
                Text(caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: SxType.caption(selected ? c.onVolt.withValues(alpha: 0.75) : c.inkMuted, size: 11.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({required this.format, required this.selected, required this.onTap});

  final MatchFormat format;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return _ChoiceTile(
      key: Key('format-${format.name}'),
      selected: selected,
      onTap: onTap,
      label: format == MatchFormat.mixed ? 'Mixed' : format.label,
      caption: switch (format) {
        MatchFormat.singles => '1 v 1',
        MatchFormat.doubles => '2 v 2',
        MatchFormat.mixed => 'Man + woman',
      },
      child: CustomPaint(
        size: const Size(64, 34),
        painter: _MiniCourt(
          perSide: format.playersPerSide,
          line: selected ? c.onVolt.withValues(alpha: 0.6) : c.inkFaint,
          left: selected ? c.onVolt : c.cyan,
          right: selected ? c.onVolt : c.voltFill,
          mixed: format == MatchFormat.mixed,
          alt: selected ? c.deep : c.blue,
        ),
      ),
    );
  }
}

/// A tiny top-down court with dots for players.
class _MiniCourt extends CustomPainter {
  _MiniCourt({required this.perSide, required this.line, required this.left, required this.right, required this.mixed, required this.alt});

  final int perSide;
  final Color line;
  final Color left;
  final Color right;
  final bool mixed;
  final Color alt;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final p = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(1), const Radius.circular(3)), p);
    canvas.drawLine(Offset(r.center.dx, 0), Offset(r.center.dx, size.height), p..strokeWidth = 2);
    final ys = perSide == 1 ? [0.5] : [0.28, 0.72];
    for (final (i, y) in ys.indexed) {
      canvas.drawCircle(Offset(size.width * 0.24, size.height * y), 4.2, Paint()..color = mixed && i == 1 ? alt : left);
      canvas.drawCircle(Offset(size.width * 0.76, size.height * y), 4.2, Paint()..color = mixed && i == 1 ? alt : right);
    }
  }

  @override
  bool shouldRepaint(_MiniCourt old) =>
      old.perSide != perSide || old.line != line || old.left != left || old.right != right || old.mixed != mixed || old.alt != alt;
}

class _DivisionTile extends StatelessWidget {
  const _DivisionTile({required this.division, required this.format, required this.selected, required this.onTap});

  final Division division;
  final MatchFormat format;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _ChoiceTile(
        key: Key('division-${division.name}'),
        selected: selected,
        onTap: onTap,
        label: division.label,
        caption: switch (division) {
          Division.men => 'Men only',
          Division.women => 'Women only',
          Division.kids => format == MatchFormat.mixed ? 'Boys + girls' : 'Under 18',
          Division.open => 'Men + women',
        },
        child: Icon(switch (division) {
          Division.men => Icons.man_rounded,
          Division.women => Icons.woman_rounded,
          Division.kids => Icons.child_care_rounded,
          Division.open => Icons.wc_rounded,
        }),
      );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      decoration: BoxDecoration(
        color: c.canvas,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: SxWidth(
          child: Padding(padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s12, Sx.gutter, Sx.s12), child: child),
        ),
      ),
    );
  }
}

// ─── Step 2 pieces ───────────────────────────────────────────────────────

class _CourtFields extends StatelessWidget {
  const _CourtFields({required this.court, required this.venue, required this.onChanged});

  final TextEditingController court;
  final TextEditingController venue;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var n = 1; n <= 8; n++) ...[
                SxChip(
                  key: Key('court-$n'),
                  label: 'Court $n',
                  selected: court.text.trim() == 'Court $n',
                  onTap: () {
                    court.text = 'Court $n';
                    onChanged();
                  },
                ),
                const SizedBox(width: Sx.s8),
              ],
            ],
          ),
        ),
        const SizedBox(height: Sx.s12),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                key: const Key('courtName'),
                controller: court,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Court', prefixIcon: Icon(Icons.grid_on_rounded)),
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: Sx.s12),
            Expanded(
              flex: 3,
              child: TextField(
                key: const Key('venueName'),
                controller: venue,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Venue (optional)', prefixIcon: Icon(Icons.place_rounded)),
                onChanged: (_) => onChanged(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ServePicker extends StatelessWidget {
  const _ServePicker({
    required this.teams,
    required this.server,
    required this.nameOf,
    required this.teamName,
    required this.onServer,
    required this.onPickSide,
  });

  final Map<Side, List<MatchPlayer?>> teams;
  final Side server;
  final String Function(MatchPlayer) nameOf;
  final String Function(Side) teamName;
  final void Function(Side side, int index) onServer;
  final ValueChanged<Side> onPickSide;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final anyone = teams.values.expand((t) => t).any((p) => p != null);
    if (!anyone) {
      // Before players are added, choose the serving side.
      return Row(
        children: [
          for (final side in Side.values) ...[
            if (side == Side.b) const SizedBox(width: Sx.s12),
            Expanded(
              child: _ServeOption(
                key: Key('serve-${side.name}'),
                label: teamName(side),
                player: null,
                side: side,
                selected: server == side,
                onTap: () => onPickSide(side),
              ),
            ),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: Sx.s8,
          runSpacing: Sx.s8,
          children: [
            for (final side in Side.values)
              for (final (i, p) in teams[side]!.indexed)
                if (p != null)
                  SizedBox(
                    width: (MediaQuery.sizeOf(context).width.clamp(0, Sx.maxContent) - Sx.gutter * 2 - Sx.s8) / 2,
                    child: _ServeOption(
                      key: Key('serve-${p.id}'),
                      label: nameOf(p),
                      player: p,
                      side: side,
                      selected: server == side && i == 0,
                      onTap: () => onServer(side, i),
                    ),
                  ),
          ],
        ),
        const SizedBox(height: Sx.s8),
        Text(
          'Scoring starts from here: the server, their side of the court, and who receives.',
          style: SxType.caption(c.inkMuted, size: 12),
        ),
      ],
    );
  }
}

class _ServeOption extends StatelessWidget {
  const _ServeOption({super.key, required this.label, required this.player, required this.side, required this.selected, required this.onTap});

  final String label;
  final MatchPlayer? player;
  final Side side;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final color = CourtTopView.teamColor(c, side);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label serves first',
      excludeSemantics: true,
      child: Tappable(
        onTap: onTap,
        radius: Sx.radiusSm,
        child: AnimatedContainer(
          duration: Sx.medium,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: Sx.s8),
          decoration: BoxDecoration(
            gradient: c.card,
            borderRadius: BorderRadius.circular(Sx.radiusSm),
            border: Border.all(color: selected ? c.voltFill : c.cardEdge, width: selected ? 2 : 1),
            boxShadow: selected ? c.glowOf(c.voltFill, strength: 0.5) : null,
          ),
          child: Row(
            children: [
              if (player != null)
                PlayerDp(name: player!.isMe ? 'You' : player!.name, size: 30, edge: color)
              else
                Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: Sx.s8),
              Expanded(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 14.5)),
              ),
              AnimatedSwitcher(
                duration: Sx.fast,
                child: selected
                    ? const SxBall(key: ValueKey('on'), size: 20, float: false, glow: false)
                    : Icon(Icons.circle_outlined, key: const ValueKey('off'), size: 18, color: c.inkFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlotActions extends ConsumerWidget {
  const _SlotActions({required this.player, required this.serving, required this.doubles});

  final MatchPlayer player;
  final bool serving;
  final bool doubles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final starred = ref.watch(starredPlayersProvider).contains(player);
    Widget row(String key, IconData icon, String label, {Color? color}) => ListTile(
          key: Key('slot-$key'),
          leading: Icon(icon, color: color ?? c.ink),
          title: Text(label, style: SxType.heading(color ?? c.ink, size: 16)),
          onTap: () => Navigator.pop(context, key),
        );
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: PlayerDp(name: player.isMe ? 'You' : player.name, size: 40),
            title: Text(player.name, style: SxType.heading(c.ink, size: 17)),
            subtitle: Text(player.isGuest ? 'Guest' : (player.isMe ? 'You' : player.id), style: SxType.caption(c.inkMuted)),
            trailing: player.isMe
                ? null
                : IconButton(
                    tooltip: starred ? 'Unstar' : 'Star',
                    icon: Icon(starred ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: starred ? c.voltFill : c.inkMuted),
                    onPressed: () => ref.read(starredPlayersProvider.notifier).toggle(player),
                  ),
          ),
          Divider(color: c.line, height: 1),
          if (!serving) row('serve', Icons.sports_tennis_rounded, 'Serves first'),
          if (doubles) row('switch', Icons.swap_vert_rounded, 'Switch with partner'),
          row('replace', Icons.person_search_rounded, 'Replace player'),
          row('remove', Icons.person_remove_rounded, 'Remove from court', color: c.live),
          const SizedBox(height: Sx.s8),
        ],
      ),
    );
  }
}

class _StreamBlock extends StatelessWidget {
  const _StreamBlock({
    required this.on,
    required this.onToggle,
    required this.title,
    required this.titleHint,
    required this.streamKey,
    required this.server,
    required this.privacy,
    required this.onPrivacy,
    required this.overlay,
    required this.onOverlay,
    required this.showKey,
    required this.onShowKey,
    required this.onChanged,
  });

  final bool on;
  final ValueChanged<bool> onToggle;
  final TextEditingController title;
  final String titleHint;
  final TextEditingController streamKey;
  final TextEditingController server;
  final StreamPrivacy privacy;
  final ValueChanged<StreamPrivacy> onPrivacy;
  final bool overlay;
  final ValueChanged<bool> onOverlay;
  final bool showKey;
  final VoidCallback onShowKey;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return SxBlock(
      padding: const EdgeInsets.all(Sx.s16),
      child: AnimatedSize(
        duration: Sx.medium,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // YouTube's own mark and red: a third-party logo, not a brand colour.
                const FaIcon(FontAwesomeIcons.youtube, size: 26, color: Color(0xFFFF0000)),
                const SizedBox(width: Sx.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Stream on YouTube Live', style: SxType.heading(c.ink, size: 16)),
                      Text(on ? 'Score overlay and title go with the stream' : 'Off',
                          style: SxType.caption(c.inkMuted, size: 12)),
                    ],
                  ),
                ),
                Switch(key: const Key('streamToggle'), value: on, onChanged: onToggle),
              ],
            ),
            if (on) ...[
              const SizedBox(height: Sx.s16),
              TextField(
                key: const Key('streamTitle'),
                controller: title,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: 'Stream title', hintText: titleHint, floatingLabelBehavior: FloatingLabelBehavior.always),
              ),
              const SizedBox(height: Sx.s12),
              Text('WHO CAN WATCH', style: SxType.label(c.inkMuted)),
              const SizedBox(height: Sx.s8),
              SegmentedPills<StreamPrivacy>(
                keyPrefix: 'privacy',
                options: [for (final p in StreamPrivacy.values) (p, p.label)],
                selected: privacy,
                onChanged: onPrivacy,
              ),
              const SizedBox(height: Sx.s12),
              TextField(
                key: const Key('streamKey'),
                controller: streamKey,
                obscureText: !showKey,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => onChanged(),
                decoration: InputDecoration(
                  labelText: 'Stream key',
                  helperText: 'YouTube Studio › Create › Go live › Stream key',
                  helperMaxLines: 2,
                  prefixIcon: const Icon(Icons.key_rounded),
                  suffixIcon: IconButton(
                    tooltip: showKey ? 'Hide key' : 'Show key',
                    icon: Icon(showKey ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                    onPressed: onShowKey,
                  ),
                ),
              ),
              const SizedBox(height: Sx.s12),
              TextField(
                key: const Key('streamServer'),
                controller: server,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Stream URL (RTMP)', prefixIcon: Icon(Icons.link_rounded)),
              ),
              const SizedBox(height: Sx.s4),
              SwitchListTile(
                key: const Key('streamOverlay'),
                contentPadding: EdgeInsets.zero,
                value: overlay,
                onChanged: onOverlay,
                title: Text('Show live score on the video', style: SxType.body(c.ink)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
