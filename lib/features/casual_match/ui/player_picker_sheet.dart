import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/design.dart';
import '../../auth/auth_controller.dart';
import '../../player/data/x_code.dart';
import '../data/match_setup.dart';

/// Picks one player for a court spot. Only players who fit [division] (and
/// [requiredGender], for a mixed partner) are offered: starred players first,
/// then "me", then the SkorX search, and anyone else can be added by name.
/// Typing a player's X code finds exactly that player.
Future<MatchPlayer?> showPlayerPicker(
  BuildContext context, {
  required Division division,
  required String title,
  required Set<String> taken,
  Gender? requiredGender,
  bool askGender = false,
}) =>
    showModalBottomSheet<MatchPlayer>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.sx.canvas,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Sx.radiusLg))),
      builder: (_) => SxKeyboardSafe(
        child: _PlayerPicker(
          division: division,
          title: title,
          taken: taken,
          requiredGender: requiredGender,
          askGender: askGender,
        ),
      ),
    );

class _PlayerPicker extends ConsumerStatefulWidget {
  const _PlayerPicker({
    required this.division,
    required this.title,
    required this.taken,
    required this.requiredGender,
    required this.askGender,
  });

  final Division division;
  final String title;
  final Set<String> taken;
  final Gender? requiredGender;

  /// Mixed doubles with no partner yet: a guest's gender must be asked.
  final bool askGender;

  @override
  ConsumerState<_PlayerPicker> createState() => _PlayerPickerState();
}

class _PlayerPickerState extends ConsumerState<_PlayerPicker> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool _fits(MatchPlayer p) => p.fits(widget.division, requiredGender: widget.requiredGender);

  /// The X code typed in the search box, if that is what it is.
  String? get _code => XCode.parse(_query.text);

  bool _matches(MatchPlayer p) {
    final code = _code;
    if (code != null) return p.xCode == code;
    final q = _query.text.trim().toLowerCase();
    return q.isEmpty || '${p.name} ${p.id} ${p.city ?? ''}'.toLowerCase().contains(q);
  }

  /// Enter adds the one player an X code found, or else a guest by name.
  void _submit(List<MatchPlayer> found) {
    if (_code == null) {
      if (!widget.askGender) _addGuest(null);
      return;
    }
    final fitting = found.where((p) => _fits(p) && !widget.taken.contains(p.id)).toList();
    if (fitting.length == 1) Navigator.pop(context, fitting.single);
  }

  String get _poolLabel {
    final gender = switch (widget.requiredGender) {
      Gender.male => widget.division == Division.kids ? 'Boys' : 'Men',
      Gender.female => widget.division == Division.kids ? 'Girls' : 'Women',
      null => null,
    };
    return gender ?? switch (widget.division) {
      Division.men => 'Men',
      Division.women => 'Women',
      Division.kids => 'Kids',
      Division.open => 'Adults',
    };
  }

  void _addGuest(Gender? gender) {
    final name = _query.text.trim();
    if (name.isEmpty) return;
    final g = gender ??
        widget.requiredGender ??
        switch (widget.division) {
          Division.men => Gender.male,
          Division.women => Gender.female,
          _ => null,
        };
    Navigator.pop(context, MatchPlayer.guest(name, gender: g, kid: widget.division == Division.kids));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final user = ref.watch(currentUserProvider);
    final starred = ref.watch(starredPlayersProvider).where(_fits).where(_matches).toList();
    final starredIds = {for (final p in starred) p.id};
    final search = ref.watch(matchPlayerSearchProvider(_query.text.trim()));
    final me = user == null ? null : MatchPlayer(id: MatchPlayer.meId, name: user.name.isEmpty ? 'You' : user.name, xCode: user.xCode);
    final showMe = me != null && _matches(me) && _fits(me);
    final q = _query.text.trim();
    final code = _code;
    // Everyone this X code could be, before the division filter.
    final codeHits = code == null
        ? const <MatchPlayer>[]
        : [
            ...ref.watch(starredPlayersProvider).where(_matches),
            if (me != null && _matches(me)) me,
            ...?search.value?.where((p) => !starredIds.contains(p.id)),
          ];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          // The theme draws the drag handle.
          Padding(
            padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title, style: SxType.title(c.ink, size: 26)),
                      const SizedBox(height: 2),
                      Text('Showing $_poolLabel only', style: SxType.caption(c.inkMuted)),
                    ],
                  ),
                ),
                SxIconAction(icon: Icons.close_rounded, label: 'Close', onTap: () => Navigator.pop(context)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sx.gutter),
            child: TextField(
              key: const Key('playerSearch'),
              controller: _query,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(codeHits),
              decoration: InputDecoration(
                hintText: 'Search name, X code or city',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(_query.clear),
                      ),
              ),
            ),
          ),
          const SizedBox(height: Sx.s8),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s32),
              children: [
                if (code != null && search.hasValue && !codeHits.any(_fits)) ...[
                  _CodeMiss(
                    code: code,
                    wrongPool: codeHits.isEmpty ? null : codeHits.first.name,
                    pool: _poolLabel,
                  ),
                  const SizedBox(height: Sx.s16),
                ],
                if (q.isNotEmpty && code == null) ...[
                  _GuestRow(name: q, askGender: widget.askGender, kids: widget.division == Division.kids, onAdd: _addGuest),
                  const SizedBox(height: Sx.s16),
                ],
                if (showMe) ...[
                  _PlayerRow(
                    key: const Key('pickMe'),
                    player: me,
                    subtitle: 'Add my profile',
                    taken: widget.taken.contains(me.id),
                    me: true,
                  ),
                  const SizedBox(height: Sx.s16),
                ],
                _Header(icon: Icons.star_rounded, text: 'STARRED', color: c.voltFill),
                if (starred.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Sx.s8),
                    child: Text(
                      q.isEmpty
                          ? 'Star the people you play with most and they will be here, one tap away.'
                          : 'No starred $_poolLabel match "$q".',
                      style: SxType.caption(c.inkMuted),
                    ),
                  )
                else
                  for (final p in starred) _PlayerRow(player: p, taken: widget.taken.contains(p.id)),
                const SizedBox(height: Sx.s16),
                _Header(icon: Icons.groups_rounded, text: 'SKORX PLAYERS', color: c.cyan),
                ...search.when(
                  loading: () => [const Padding(padding: EdgeInsets.all(Sx.s16), child: Center(child: BallLoader()))],
                  error: (_, _) => [Text('Search is not available right now.', style: SxType.caption(c.inkMuted))],
                  data: (all) {
                    final list = all.where(_fits).where((p) => !starredIds.contains(p.id)).toList();
                    if (list.isEmpty) {
                      return [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: Sx.s8),
                          child: Text(
                            q.isEmpty
                                ? 'No players to show yet. Type a name or X code.'
                                : code != null
                                    ? 'No SkorX player with this X code.'
                                    : 'No $_poolLabel found. Add "$q" as a guest above.',
                            style: SxType.caption(c.inkMuted),
                          ),
                        ),
                      ];
                    }
                    return [for (final p in list) _PlayerRow(player: p, taken: widget.taken.contains(p.id))];
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Sx.s8),
        child: Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(text, style: SxType.label(context.sx.inkMuted)),
          ],
        ),
      );
}

class _PlayerRow extends ConsumerWidget {
  const _PlayerRow({super.key, required this.player, required this.taken, this.subtitle, this.me = false});

  final MatchPlayer player;
  final bool taken;
  final String? subtitle;
  final bool me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final starred = ref.watch(starredPlayersProvider).contains(player);
    final detail = subtitle ??
        [
          if (player.isGuest) 'Guest',
          if (player.level != null) player.level,
          if (player.city != null) player.city,
          if (player.xCode != null) XCode.display(player.xCode!),
        ].join(' · ');
    return Opacity(
      opacity: taken ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: Sx.s8),
        child: SxBlock(
          key: Key('pick-${player.id}'),
          padding: const EdgeInsets.fromLTRB(Sx.s12, Sx.s8, Sx.s4, Sx.s8),
          semanticLabel: '${player.name}${taken ? ', already on court' : ''}',
          onTap: taken ? null : () => Navigator.pop(context, player),
          child: Row(
            children: [
              if (me)
                PlayerDp(name: 'You', size: 42, edge: c.voltFill)
              else
                PlayerDp(name: player.name, size: 42),
              const SizedBox(width: Sx.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(player.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 16)),
                    if (detail.isNotEmpty || taken)
                      Text(taken ? 'On court' : detail,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted, size: 12)),
                  ],
                ),
              ),
              if (!me)
                IconButton(
                  key: Key('star-${player.id}'),
                  tooltip: starred ? 'Unstar' : 'Star',
                  onPressed: () => ref.read(starredPlayersProvider.notifier).toggle(player),
                  icon: AnimatedSwitcher(
                    duration: Sx.fast,
                    transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                    child: Icon(
                      starred ? Icons.star_rounded : Icons.star_outline_rounded,
                      key: ValueKey(starred),
                      color: starred ? c.voltFill : c.inkFaint,
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

/// An X code that found nobody who can take this spot.
class _CodeMiss extends StatelessWidget {
  const _CodeMiss({required this.code, required this.wrongPool, required this.pool});

  final String code;

  /// The player the code belongs to, when they are outside [pool].
  final String? wrongPool;
  final String pool;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return SxBlock(
      key: const Key('xCodeMiss'),
      padding: const EdgeInsets.all(Sx.s12),
      child: Row(
        children: [
          SxIconTile(icon: Icons.tag_rounded, size: 42, colors: [c.blue, c.cyan]),
          const SizedBox(width: Sx.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wrongPool == null ? 'No player with ${XCode.display(code)}' : '$wrongPool can\'t take this spot',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SxType.heading(c.ink, size: 16),
                ),
                Text(
                  wrongPool == null ? 'Check the code with them: 4 letters and digits.' : 'This spot is for $pool only.',
                  style: SxType.caption(c.inkMuted, size: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuestRow extends StatelessWidget {
  const _GuestRow({required this.name, required this.askGender, required this.kids, required this.onAdd});

  final String name;
  final bool askGender;
  final bool kids;
  final ValueChanged<Gender?> onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return SxBlock(
      key: const Key('addGuest'),
      padding: const EdgeInsets.all(Sx.s12),
      onTap: askGender ? null : () => onAdd(null),
      semanticLabel: 'Add $name as a guest',
      child: Row(
        children: [
          SxIconTile(icon: Icons.person_add_alt_1_rounded, size: 42, colors: [c.blue, c.cyan]),
          const SizedBox(width: Sx.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add "$name"', maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 16)),
                Text('Guest, not on SkorX', style: SxType.caption(c.inkMuted, size: 12)),
              ],
            ),
          ),
          if (askGender) ...[
            SxChip(key: const Key('guestMale'), label: kids ? 'Boy' : 'Man', selected: false, onTap: () => onAdd(Gender.male)),
            const SizedBox(width: 6),
            SxChip(key: const Key('guestFemale'), label: kids ? 'Girl' : 'Woman', selected: false, onTap: () => onAdd(Gender.female)),
          ] else
            Icon(Icons.add_circle_rounded, color: c.voltFill),
        ],
      ),
    );
  }
}
