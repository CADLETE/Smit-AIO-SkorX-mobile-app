import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../design/design.dart';
import '../community_controller.dart';
import '../data/community.dart';
import '../data/messages.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────

/// 1840 → "1.8K".
String compactCount(int n) {
  if (n < 1000) return '$n';
  final k = n / 1000;
  return '${k >= 10 ? k.round() : (k * 10).round() / 10}K'.replaceAll('.0K', 'K');
}

/// Shows why an action failed, in the player's words.
void showCommunityError(BuildContext context, Object error) {
  final message = error is ApiException ? error.message : 'Something went wrong. Please try again.';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

void showCommunityNote(BuildContext context, String message) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));

/// Opens the thread with a member, place or group, starting one if needed.
Future<void> openConversation(BuildContext context, WidgetRef ref, ConversationKind kind, String targetId,
    {String? draft}) async {
  try {
    final c = await ref.read(conversationsProvider.notifier).open(kind, targetId);
    if (!context.mounted) return;
    final q = draft == null ? '' : '?draft=${Uri.encodeQueryComponent(draft)}';
    context.push('/player/community/messages/${c.id}$q');
  } catch (e) {
    if (context.mounted) showCommunityError(context, e);
  }
}

String placeRoute(String id) => '/player/community/places/$id';
String memberRoute(String id) => '/player/community/people/$id';
String groupRoute(String id) => '/player/community/groups/$id';

// ─── Marks ────────────────────────────────────────────────────────────────

/// SkorX checked it: a small filled seal. Never shown for popularity.
class VerifiedMark extends StatelessWidget {
  const VerifiedMark({super.key, this.size = 16, this.label = 'SkorX verified'});

  final double size;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      label: label,
      child: ExcludeSemantics(child: Icon(Icons.verified_rounded, size: size, color: c.isDark ? c.cyan : c.blue)),
    );
  }
}

/// A role as a small tag, sealed when SkorX verified it.
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role, this.verified = false, this.selected = false});

  final CommunityRole role;
  final bool verified;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final fg = selected ? c.onVolt : c.ink;
    return Semantics(
      label: verified ? '${role.label}, verified' : role.label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          gradient: selected ? c.brand : null,
          color: selected ? null : c.surfaceAlt.withValues(alpha: c.isDark ? 0.9 : 1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.transparent : c.cardEdge),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(role.icon, size: 14, color: selected ? fg : c.inkMuted),
            const SizedBox(width: 5),
            Flexible(
              child: Text(role.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SxType.caption(fg, size: 12.5).copyWith(fontWeight: FontWeight.w700)),
            ),
            if (verified) ...[const SizedBox(width: 4), const VerifiedMark(size: 13)],
          ],
        ),
      ),
    );
  }
}

/// Available · Limited · Not available, as a dot and a word.
class AvailabilityMark extends StatelessWidget {
  const AvailabilityMark(this.availability, {super.key});

  final Availability availability;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final color = switch (availability) {
      Availability.open => c.volt,
      Availability.limited => c.caution,
      Availability.busy => c.inkFaint,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(availability.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SxType.caption(c.inkMuted, size: 12.5).copyWith(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// A place's mark: its kind's icon on a tile, coloured from its id so
/// neighbours differ.
class PlaceMark extends StatelessWidget {
  const PlaceMark({super.key, required this.place, this.size = 44});

  final CommunityPlace place;
  final double size;

  @override
  Widget build(BuildContext context) =>
      SxIconTile(icon: place.kind.icon, size: size, colors: sxTileColors(context.sx, place.id.codeUnits.fold(0, (a, b) => a + b)));
}

// ─── Connect ──────────────────────────────────────────────────────────────

/// Connect → Pending → Connected, or Accept / Decline when they asked first.
/// Never exposes a phone number: connecting only opens messaging.
class ConnectButton extends ConsumerStatefulWidget {
  const ConnectButton({super.key, required this.member, this.compact = false});

  final CommunityMember member;

  /// A small pill for cards and rows.
  final bool compact;

  @override
  ConsumerState<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends ConsumerState<ConnectButton> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showCommunityError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  CommunityGraphController get _graph => ref.read(communityGraphProvider.notifier);

  Future<void> _connect() => _run(() async {
        HapticFeedback.lightImpact();
        final status = await _graph.connect(widget.member.id);
        if (mounted && status == ConnectionStatus.connected) {
          showCommunityNote(context, 'You and ${widget.member.name.split(' ').first} are connected.');
        }
      });

  Future<void> _confirm(String title, String body, String action, Future<void> Function() run) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    if (ok == true) await _run(run);
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(communityGraphProvider.select((g) => g.value?.connectionWith(widget.member.id))) ??
        ConnectionStatus.none;
    final first = widget.member.name.split(' ').first;
    final key = Key('connect-${widget.member.id}');
    switch (status) {
      case ConnectionStatus.none:
        return _pill(key, 'Connect', Icons.person_add_alt_1_rounded, primary: true, onTap: _connect);
      case ConnectionStatus.pendingOut:
        return _pill(key, 'Pending', Icons.schedule_rounded,
            onTap: () => _confirm('Withdraw request?', '$first will no longer see your request.', 'Withdraw',
                () => _graph.disconnect(widget.member.id)));
      case ConnectionStatus.pendingIn:
        if (widget.compact) return _pill(key, 'Accept', Icons.check_rounded, primary: true, onTap: _connect);
        return Row(
          children: [
            Expanded(child: _pill(key, 'Accept', Icons.check_rounded, primary: true, onTap: _connect)),
            const SizedBox(width: Sx.s8),
            Expanded(
              child: _pill(Key('decline-${widget.member.id}'), 'Decline', Icons.close_rounded,
                  onTap: () => _run(() => _graph.disconnect(widget.member.id))),
            ),
          ],
        );
      case ConnectionStatus.connected:
        return _pill(key, 'Connected', Icons.check_circle_rounded,
            onTap: () => _confirm('Remove connection?', 'You and $first will no longer be connected. They are not told.',
                'Remove', () => _graph.disconnect(widget.member.id)));
    }
  }

  Widget _pill(Key key, String label, IconData icon, {bool primary = false, required VoidCallback onTap}) {
    if (!widget.compact) {
      return primary
          ? SxButton(key: key, label: label, icon: icon, busy: _busy, onPressed: onTap, height: 48)
          : SxButton.secondary(key: key, label: label, icon: icon, busy: _busy, onPressed: onTap, height: 48);
    }
    final c = context.sx;
    final fg = primary ? c.onVolt : c.ink;
    return Semantics(
      button: true,
      label: '$label, ${widget.member.name}',
      excludeSemantics: true,
      child: Tappable(
        key: key,
        onTap: _busy ? null : onTap,
        radius: 20,
        child: AnimatedContainer(
          duration: Sx.medium,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            gradient: primary ? c.brand : null,
            color: primary ? null : c.surfaceAlt,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: primary ? Colors.transparent : c.cardEdge),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 5),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: SxType.sans, fontSize: 12.5, fontWeight: FontWeight.w800, color: fg)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Cards and rows ───────────────────────────────────────────────────────

/// A person in a horizontal strip: who, what they do, and why they are
/// suggested.
class MemberCard extends StatelessWidget {
  const MemberCard({super.key, required this.member, this.reason});

  final CommunityMember member;
  final String? reason;

  static const width = 172.0;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = member;
    return SizedBox(
      width: width,
      child: Semantics(
        container: true,
        child: Tappable(
          key: Key('member-${m.id}'),
          onTap: () => context.push(memberRoute(m.id)),
          radius: Sx.radiusLg,
          child: Container(
            padding: const EdgeInsets.all(Sx.s12),
            decoration: BoxDecoration(
              gradient: c.card,
              borderRadius: BorderRadius.circular(Sx.radiusLg),
              border: Border.all(color: c.cardEdge),
              boxShadow: c.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SxAvatar(name: m.name, size: 48),
                    const Spacer(),
                    if (m.verified) const VerifiedMark(size: 18),
                  ],
                ),
                const SizedBox(height: Sx.s8),
                Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 16)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(m.primaryRole.icon, size: 13, color: c.inkMuted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(m.primaryRole.label,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted, size: 12.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(reason ?? m.placeLabel,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkFaint, size: 12)),
                const Spacer(),
                const SizedBox(height: Sx.s8),
                SizedBox(width: double.infinity, child: ConnectButton(member: m, compact: true)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A person in a list: name, roles, where, and availability for work.
class MemberRow extends StatelessWidget {
  const MemberRow({super.key, required this.member, this.trailing, this.showConnect = true});

  final CommunityMember member;
  final Widget? trailing;
  final bool showConnect;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = member;
    return Tappable(
      key: Key('memberRow-${m.id}'),
      onTap: () => context.push(memberRoute(m.id)),
      radius: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Sx.s12),
        child: Row(
          children: [
            SxAvatar(name: m.name, size: 46),
            const SizedBox(width: Sx.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(m.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 16)),
                      ),
                      if (m.verified) ...[const SizedBox(width: 4), const VerifiedMark(size: 15)],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(m.rolesLabel,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted, size: 12.5)),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: Sx.s8,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(m.placeLabel, style: SxType.caption(c.inkFaint, size: 12)),
                      if (m.availability != null) AvailabilityMark(m.availability!),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: Sx.s8),
            trailing ?? (showConnect ? ConnectButton(member: m, compact: true) : Icon(Icons.chevron_right_rounded, color: c.inkFaint)),
          ],
        ),
      ),
    );
  }
}

/// A club, academy, venue or business in a list.
class PlaceRow extends StatelessWidget {
  const PlaceRow({super.key, required this.place});

  final CommunityPlace place;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final p = place;
    final facts = [
      p.kind.label,
      if (p.courts != null) '${p.courts} courts',
      if (p.setting != null) p.setting!.label,
      if (p.kind == PlaceKind.academy && p.programs.isNotEmpty) '${p.programs.length} programs',
    ].join(' · ');
    return Tappable(
      key: Key('placeRow-${p.id}'),
      onTap: () => context.push(placeRoute(p.id)),
      radius: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Sx.s12),
        child: Row(
          children: [
            PlaceMark(place: p, size: 46),
            const SizedBox(width: Sx.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 16)),
                      ),
                      if (p.verified) ...[const SizedBox(width: 4), const VerifiedMark(size: 15)],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(facts, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted, size: 12.5)),
                  const SizedBox(height: 2),
                  Text(p.placeLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkFaint, size: 12)),
                ],
              ),
            ),
            const SizedBox(width: Sx.s8),
            if (p.bookable)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: c.info.withValues(alpha: c.isDark ? 0.16 : 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('BOOK', style: SxType.label(c.info, size: 11, weight: FontWeight.w800)),
              )
            else
              Icon(Icons.chevron_right_rounded, color: c.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// A community in a horizontal strip, with how alive it is this week.
class GroupCard extends ConsumerWidget {
  const GroupCard({super.key, required this.group});

  final CommunityGroup group;

  static const width = 216.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final g = group;
    final status = ref.watch(communityGraphProvider.select((x) => x.value?.groupStatus(g.id))) ?? GroupStatus.none;
    return SizedBox(
      width: width,
      child: Tappable(
        key: Key('group-${g.id}'),
        onTap: () => context.push(groupRoute(g.id)),
        radius: Sx.radiusLg,
        child: Container(
          padding: const EdgeInsets.all(Sx.s16),
          decoration: BoxDecoration(
            gradient: c.card,
            borderRadius: BorderRadius.circular(Sx.radiusLg),
            border: Border.all(color: c.cardEdge),
            boxShadow: c.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SxIconTile(
                    icon: g.focus?.icon ?? Icons.diversity_3_rounded,
                    size: 38,
                    colors: sxTileColors(c, g.id.codeUnits.fold(0, (a, b) => a + b)),
                  ),
                  const Spacer(),
                  GroupAccessMark(access: g.access),
                ],
              ),
              const SizedBox(height: Sx.s12),
              Text(g.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 16)),
              const SizedBox(height: 2),
              Text('${g.placeLabel} · ${compactCount(g.members)} members',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted, size: 12.5)),
              const Spacer(),
              const SizedBox(height: Sx.s8),
              ActivityBar(group: g),
              const SizedBox(height: Sx.s8),
              Text(
                switch (status) {
                  GroupStatus.member => 'Joined',
                  GroupStatus.requested => 'Requested',
                  GroupStatus.none => '${compactCount(g.activeThisWeek)} active this week',
                },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SxType.caption(status == GroupStatus.none ? c.inkFaint : c.volt, size: 12)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Public / Private / Verified.
class GroupAccessMark extends StatelessWidget {
  const GroupAccessMark({super.key, required this.access});

  final GroupAccess access;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final (icon, color) = switch (access) {
      GroupAccess.public => (Icons.public_rounded, c.inkMuted),
      GroupAccess.private => (Icons.lock_rounded, c.caution),
      GroupAccess.verified => (Icons.verified_rounded, c.isDark ? c.cyan : c.blue),
    };
    return Semantics(
      label: '${access.label} community',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(access.label.toUpperCase(), style: SxType.label(color, size: 10.5, weight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Share of members active this week, as a thin bar.
class ActivityBar extends StatelessWidget {
  const ActivityBar({super.key, required this.group});

  final CommunityGroup group;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      label: '${(group.activity * 100).round()} percent active this week',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 5,
          child: Stack(
            children: [
              Container(color: c.surfaceAlt),
              FractionallySizedBox(
                widthFactor: group.activity.clamp(0.04, 1),
                child: Container(decoration: BoxDecoration(gradient: c.brand)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A group in a list.
class GroupRow extends ConsumerWidget {
  const GroupRow({super.key, required this.group});

  final CommunityGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final g = group;
    final status = ref.watch(communityGraphProvider.select((x) => x.value?.groupStatus(g.id))) ?? GroupStatus.none;
    return Tappable(
      key: Key('groupRow-${g.id}'),
      onTap: () => context.push(groupRoute(g.id)),
      radius: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Sx.s12),
        child: Row(
          children: [
            SxIconTile(
              icon: g.focus?.icon ?? Icons.diversity_3_rounded,
              size: 46,
              colors: sxTileColors(c, g.id.codeUnits.fold(0, (a, b) => a + b)),
            ),
            const SizedBox(width: Sx.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 16)),
                  const SizedBox(height: 2),
                  Text('${g.placeLabel} · ${compactCount(g.members)} members · ${compactCount(g.activeThisWeek)} active',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted, size: 12.5)),
                  const SizedBox(height: 6),
                  ActivityBar(group: g),
                ],
              ),
            ),
            const SizedBox(width: Sx.s12),
            if (status == GroupStatus.member)
              Icon(Icons.check_circle_rounded, color: c.volt, size: 20)
            else
              GroupAccessMark(access: g.access),
          ],
        ),
      ),
    );
  }
}

/// A role's evidence as number tiles, two to a row.
class MetricGrid extends StatelessWidget {
  const MetricGrid({super.key, required this.metrics});

  final List<(String, String)> metrics;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final rows = [for (var i = 0; i < metrics.length; i += 2) metrics.sublist(i, (i + 2).clamp(0, metrics.length))];
    return Column(
      children: [
        for (final (r, row) in rows.indexed) ...[
          if (r > 0) const SizedBox(height: Sx.s8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, (label, value)) in row.indexed) ...[
                  if (i > 0) const SizedBox(width: Sx.s8),
                  Expanded(
                    child: Semantics(
                      label: '$label: $value',
                      excludeSemantics: true,
                      child: Container(
                        padding: const EdgeInsets.all(Sx.s12),
                        decoration: BoxDecoration(
                          color: c.surfaceAlt.withValues(alpha: c.isDark ? 0.7 : 1),
                          borderRadius: BorderRadius.circular(Sx.radiusSm),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(value,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: _isNumber(value)
                                    ? SxType.number(26, c.ink, weight: FontWeight.w800)
                                    : SxType.heading(c.ink, size: 15)),
                            const SizedBox(height: 4),
                            Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted, size: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                if (row.length == 1) ...[const SizedBox(width: Sx.s8), const Expanded(child: SizedBox())],
              ],
            ),
          ),
        ],
      ],
    );
  }

  static bool _isNumber(String v) => RegExp(r'^[\d.,%]+$').hasMatch(v);
}

/// A strip of cards that scrolls sideways, bleeding to the screen edges.
class SideStrip extends StatelessWidget {
  const SideStrip({super.key, required this.children, this.height = 196});

  final List<Widget> children;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: ListView.separated(
          // Out to the screen edges, then the gutter again inside.
          clipBehavior: Clip.none,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: Sx.s12),
          itemCount: children.length,
          separatorBuilder: (_, _) => const SizedBox(width: Sx.s12),
          itemBuilder: (_, i) => children[i],
        ),
      );
}

// ─── Safety ───────────────────────────────────────────────────────────────

/// Why are you reporting this? Reports go to SkorX moderators, never to the
/// person reported.
Future<void> showReportSheet(BuildContext context, WidgetRef ref, ReportTarget target, String id, String name) async {
  final reason = await showSxSheet<ReportReason>(
    context,
    builder: (ctx) {
      final c = ctx.sx;
      return Padding(
        padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Report $name', style: SxType.title(c.ink, size: 26)),
            const SizedBox(height: Sx.s4),
            Text('SkorX moderators review every report. $name is not told who reported.',
                style: SxType.body(c.inkMuted, size: 14)),
            const SizedBox(height: Sx.s16),
            SxRows(children: [
              for (final r in ReportReason.values)
                SxRow(key: Key('report-${r.name}'), label: r.label, onTap: () => Navigator.pop(ctx, r)),
            ]),
          ],
        ),
      );
    },
  );
  if (reason == null) return;
  try {
    await ref.read(communityRepositoryProvider).report(target, id, reason);
    if (context.mounted) showCommunityNote(context, 'Thanks. Our team will review this report.');
  } catch (e) {
    if (context.mounted) showCommunityError(context, e);
  }
}

/// Blocks a member after saying what that does.
Future<bool> confirmBlock(BuildContext context, WidgetRef ref, CommunityMember m) async {
  final first = m.name.split(' ').first;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Block $first?'),
      content: Text('$first will not be able to find you, connect or message you. '
          'Your connection and conversation are removed. They are not told.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(key: const Key('confirmBlock'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Block')),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await ref.read(communityGraphProvider.notifier).block(m.id, on: true);
    if (context.mounted) showCommunityNote(context, '$first is blocked.');
    return true;
  } catch (e) {
    if (context.mounted) showCommunityError(context, e);
    return false;
  }
}

/// ⋯ menu on profiles, places and groups.
class OverflowMenu extends StatelessWidget {
  const OverflowMenu({super.key, required this.items});

  /// (label, icon, action, danger)
  final List<(String, IconData, VoidCallback, bool)> items;

  @override
  Widget build(BuildContext context) => SxIconAction(
        key: const Key('overflow'),
        icon: Icons.more_horiz_rounded,
        label: 'More',
        onTap: () => showSxSheet<void>(
          context,
          builder: (ctx) => Padding(
            padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
            child: SxRows(children: [
              for (final (label, icon, action, danger) in items)
                SxRow(
                  key: Key('menu-$label'),
                  icon: icon,
                  label: label,
                  danger: danger,
                  onTap: () {
                    Navigator.pop(ctx);
                    action();
                  },
                ),
            ]),
          ),
        ),
      );
}

/// Save / saved toggle for the top bar.
class SaveAction extends ConsumerWidget {
  const SaveAction({super.key, required this.targetId, required this.type});

  final String targetId;
  final CommunityTarget type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(communityGraphProvider.select((g) => g.value?.hasSaved(targetId))) ?? false;
    return SxIconAction(
      key: const Key('save'),
      icon: saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
      label: saved ? 'Saved' : 'Save',
      onTap: () async {
        try {
          await ref.read(communityGraphProvider.notifier).save(targetId, on: !saved, type: type);
          if (context.mounted) showCommunityNote(context, saved ? 'Removed from saved.' : 'Saved to your Community.');
        } catch (e) {
          if (context.mounted) showCommunityError(context, e);
        }
      },
    );
  }
}

/// A block with a heading, for sections of a detail page.
class DetailSection extends StatelessWidget {
  const DetailSection({super.key, required this.title, required this.child, this.action, this.onAction});

  final String title;
  final Widget child;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Sx.section),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [SxSection(title, action: action, onAction: onAction), child],
        ),
      );
}

/// Label: value lines ("Languages  English, Hindi").
class FactLine extends StatelessWidget {
  const FactLine({super.key, required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: c.inkMuted),
            const SizedBox(width: Sx.s12),
            SizedBox(width: 96, child: Text(label, style: SxType.caption(c.inkMuted))),
            Expanded(child: Text(value, style: SxType.body(c.ink, size: 14))),
          ],
        ),
      ),
    );
  }
}

/// A list inside a card, rows split by hairlines.
class ListCard extends StatelessWidget {
  const ListCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sx.s16),
      decoration: BoxDecoration(
        gradient: c.card,
        borderRadius: BorderRadius.circular(Sx.radiusLg),
        border: Border.all(color: c.cardEdge),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: c.line.withValues(alpha: 0.6)),
            children[i],
          ],
        ],
      ),
    );
  }
}
