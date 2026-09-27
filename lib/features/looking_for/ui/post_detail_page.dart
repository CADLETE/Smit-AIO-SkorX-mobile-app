import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../../community/ui/community_widgets.dart' show OverflowMenu;
import '../data/looking_for.dart';
import '../looking_for_controller.dart';
import 'lf_widgets.dart';

/// One requirement: everything needed to decide, and the one next step.
class LookingForPostPage extends ConsumerWidget {
  const LookingForPostPage({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final post = ref.watch(lfPostProvider(postId));
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: post.when(
            loading: () => const Column(children: [SxBackBar(), Expanded(child: Center(child: BallLoader()))]),
            error: (e, _) => Column(
              children: [
                SxBackBar(onBack: () => lfBack(context)),
                const Expanded(
                  child: EmptyBlock(
                    icon: Icons.search_off_rounded,
                    title: 'Request not available',
                    message: 'It may have been removed, or the link is wrong.',
                  ),
                ),
              ],
            ),
            data: (p) => Column(
              children: [
                SxBackBar(onBack: () => lfBack(context), actions: _actions(context, ref, p)),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(lfPostProvider(postId));
                      await ref.read(lfPostProvider(postId).future);
                    },
                    child: _Body(post: p),
                  ),
                ),
                _BottomBar(post: p),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context, WidgetRef ref, LfPost p) => [
        if (!p.isOwner)
          SxIconAction(
            key: const Key('lfSave'),
            icon: p.saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            label: p.saved ? 'Saved' : 'Save',
            onTap: () async {
              try {
                await ref.read(lfActionsProvider).save(p, on: !p.saved);
                if (context.mounted) lfNote(context, p.saved ? 'Removed from saved' : 'Saved to My Looking For');
              } catch (e) {
                if (context.mounted) lfError(context, e);
              }
            },
          ),
        SxIconAction(key: const Key('lfShare'), icon: Icons.ios_share_rounded, label: 'Share', onTap: () => shareLfPost(context, ref, p)),
        OverflowMenu(items: [
          ('Copy link', Icons.link_rounded, () => copyLfLink(context, ref, p), false),
          if (p.isOwner && p.status.active) ('Edit', Icons.edit_outlined, () => _edit(context, ref, p), false),
          if (p.isOwner && p.status.active) ('Mark as filled', Icons.task_alt_rounded, () => _state(context, ref, p, 'fill'), false),
          if (p.isOwner && (p.status == LfStatus.filled || p.status == LfStatus.cancelled) && p.expiresAt.isAfter(DateTime.now()))
            ('Reopen', Icons.replay_rounded, () => _state(context, ref, p, 'reopen'), false),
          if (p.isOwner && p.status.active) ('Cancel request', Icons.close_rounded, () => _confirmCancel(context, ref, p), true),
          if (!p.isOwner) ('Report', Icons.flag_outlined, () => showLfReportSheet(context, ref, p), true),
        ]),
      ];

  static Future<void> _state(BuildContext context, WidgetRef ref, LfPost p, String action) async {
    try {
      await ref.read(lfActionsProvider).setState(p.id, action);
      if (context.mounted) {
        lfNote(context, switch (action) {
          'fill' => 'Marked as filled. It is off the feed.',
          'reopen' => 'Reopened. It is back on the feed.',
          _ => 'Request cancelled.',
        });
      }
    } catch (e) {
      if (context.mounted) lfError(context, e);
    }
  }

  static Future<void> _confirmCancel(BuildContext context, WidgetRef ref, LfPost p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Cancel this request?'),
        content: Text(p.responseCount > 0 ? 'People who responded will be told it is no longer needed.' : 'It leaves the feed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep')),
          TextButton(key: const Key('lfConfirmCancel'), onPressed: () => Navigator.pop(d, true), child: const Text('Cancel request')),
        ],
      ),
    );
    if (ok == true && context.mounted) await _state(context, ref, p, 'cancel');
  }

  static Future<void> _edit(BuildContext context, WidgetRef ref, LfPost p) =>
      showSxSheet<void>(context, builder: (_) => _EditSheet(post: p));
}

class _Body extends ConsumerWidget {
  const _Body({required this.post});

  final LfPost post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final p = post;
    final when = lfWhen(p);
    final left = p.expiresAt.difference(DateTime.now());
    final facts = <(IconData, String, String)>[
      if (when != null) (Icons.schedule_rounded, 'When', when),
      (
        Icons.place_outlined,
        'Where',
        [p.placeLabel, if (p.distanceKm != null) '${lfDistance(p)} away${p.approximate ? ' (city centre)' : ''}'].join('\n'),
      ),
      if (p.quantityLabel != null) (Icons.group_outlined, p.quantityLabel!, '${p.quantityRequired}${p.quantityFilled > 0 ? ' · ${p.quantityFilled} filled' : ''}'),
      if (p.skillLabel != null) (Icons.trending_up_rounded, 'Level', p.skillLabel!),
      if (p.gender != 'any' || p.ageGroup != 'any')
        (
          Icons.person_outline_rounded,
          'Open to',
          [if (p.gender != 'any') p.gender == 'male' ? 'Men' : 'Women', if (p.ageGroup != 'any') p.ageGroup == 'junior' ? 'Juniors' : p.ageGroup].join(' · '),
        ),
      if (p.paymentLabel != null) (Icons.payments_outlined, p.paymentType == LfPaymentType.paid ? 'Payment' : 'Cost', p.paymentLabel!),
      for (final e in p.details.entries)
        if (e.value != null && '${e.value}'.isNotEmpty) (Icons.info_outline_rounded, p.detailLabels[e.key] ?? e.key, '${e.value}'),
      if (p.tournamentName != null) (Icons.emoji_events_outlined, 'Tournament', p.tournamentName!),
    ];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s32),
      children: [
        Row(
          children: [
            SxIconTile(icon: lfIcon(p.categoryIcon), size: 34, colors: lfColors(c, p.categoryId)),
            const SizedBox(width: Sx.s12),
            Expanded(
              child: Text((p.subcategoryLabel ?? p.categoryLabel).toUpperCase(), style: SxType.label(c.inkMuted)),
            ),
            LfStatusMark(p),
          ],
        ),
        const SizedBox(height: Sx.s16),
        Text(p.title, style: SxType.title(c.ink, size: 30)),
        const SizedBox(height: Sx.s12),
        Row(
          children: [
            SxAvatar(name: p.postedBy.name, size: 28),
            const SizedBox(width: Sx.s8),
            Expanded(
              child: Text(
                [
                  p.isOwner ? 'You' : p.postedBy.name,
                  if (p.postedBy.kind != 'self') p.postedBy.kind == 'organization' ? 'Organizer' : 'Tournament',
                  timeAgo(p.createdAt, DateTime.now()),
                ].join(' · '),
                style: SxType.caption(c.inkMuted),
              ),
            ),
          ],
        ),
        if (p.hidden) ...[
          const SizedBox(height: Sx.s16),
          _Notice(
            icon: Icons.visibility_off_outlined,
            text: 'Hidden from the feed while SkorX reviews reports about it.',
            color: c.caution,
          ),
        ],
        if (p.description != null && p.description!.trim().isNotEmpty) ...[
          const SizedBox(height: Sx.s20),
          Text(p.description!, style: SxType.body(c.ink)),
        ],
        const SizedBox(height: Sx.s20),
        SxRows(children: [
          for (final (icon, label, value) in facts)
            SxRow(icon: icon, label: label, subtitle: value),
        ]),
        if (p.status.active) ...[
          const SizedBox(height: Sx.s12),
          Text(
            left.inMinutes < 60
                ? 'Closes in ${left.inMinutes.clamp(1, 59)} min'
                : left.inHours < 48
                    ? 'Closes in ${left.inHours} h'
                    : 'Open until ${longDate(p.expiresAt)}',
            style: SxType.caption(c.inkMuted),
          ),
        ],
        if (p.isOwner) ...[const SizedBox(height: Sx.section), _OwnerPanel(post: p)],
        if (!p.isOwner && p.myResponse != null) ...[const SizedBox(height: Sx.section), _MyResponse(post: p)],
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      padding: const EdgeInsets.all(Sx.s12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Sx.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Sx.s8),
          Expanded(child: Text(text, style: SxType.caption(c.ink))),
        ],
      ),
    );
  }
}

/// The poster's view: who SkorX found, and who answered.
class _OwnerPanel extends StatelessWidget {
  const _OwnerPanel({required this.post});

  final LfPost post;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final m = post.matching;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SxSection('Potential matches'),
        SxBlock(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (m?.count ?? post.matchCount ?? 0) == 0
                    ? 'No one matches yet'
                    : '${m?.count ?? post.matchCount} ${(m?.count ?? post.matchCount) == 1 ? 'person' : 'people'} may match your requirement',
                style: SxType.heading(c.ink, size: 16),
              ),
              const SizedBox(height: Sx.s4),
              Text(
                (m?.count ?? 0) == 0
                    ? 'SkorX tells people nearby whose alerts and profile fit, as they join or change their settings.'
                    : 'SkorX alerted ${m!.alerted}${m.waitingForDigest > 0 ? ', and ${m.waitingForDigest} will see it in their daily digest' : ''}. Nobody gets more than a few alerts a day.',
                style: SxType.caption(c.inkMuted),
              ),
              if (m != null && m.summary.isNotEmpty) ...[
                const SizedBox(height: Sx.s12),
                Wrap(
                  spacing: Sx.s8,
                  runSpacing: Sx.s8,
                  children: [for (final (label, count) in m.summary) _Count(label: label, count: count)],
                ),
              ],
              if (post.viewCount != null) ...[
                const SizedBox(height: Sx.s12),
                Text('${post.viewCount} views', style: SxType.caption(c.inkFaint, size: 12)),
              ],
            ],
          ),
        ),
        const SizedBox(height: Sx.s16),
        SxRows(children: [
          SxRow(
            key: const Key('lfOpenResponses'),
            icon: Icons.front_hand_outlined,
            label: 'Responses',
            value: '${post.responseCount}',
            subtitle: post.fillLabel ?? (post.responseCount == 0 ? 'No one yet' : 'Accept or decline each person'),
            onTap: () => context.push('/player/looking-for/${post.id}/responses'),
          ),
        ]),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(20)),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: '$count ', style: SxType.number(13, c.ink, weight: FontWeight.w800)),
        TextSpan(text: label, style: SxType.caption(c.inkMuted, size: 12.5)),
      ])),
    );
  }
}

/// The responder's view of their own interest, and the contact step once accepted.
class _MyResponse extends ConsumerWidget {
  const _MyResponse({required this.post});

  final LfPost post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final interests = ref.watch(lfInterestsProvider).value;
    final mine = interests?.items.where((i) => i.post.id == post.id).firstOrNull?.response;
    final status = post.myResponse!.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SxSection('Your response'),
        SxBlock(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                switch (status) {
                  LfResponseStatus.pending => 'Waiting for ${post.postedBy.name.split(' ').first}',
                  LfResponseStatus.accepted => "You're in",
                  LfResponseStatus.declined => 'Not this time',
                  LfResponseStatus.withdrawn => 'You withdrew',
                },
                style: SxType.heading(status == LfResponseStatus.accepted ? c.volt : c.ink, size: 17),
              ),
              const SizedBox(height: Sx.s4),
              Text(
                switch (status) {
                  LfResponseStatus.pending => "We'll tell you as soon as they accept or decline.",
                  LfResponseStatus.accepted => 'Share your number to get in touch. It goes to them only.',
                  LfResponseStatus.declined => 'They went with someone else. There will be more.',
                  LfResponseStatus.withdrawn => 'You can send interest again while it is open.',
                },
                style: SxType.caption(c.inkMuted),
              ),
              if (status == LfResponseStatus.accepted && mine != null) ...[
                const SizedBox(height: Sx.s16),
                LfContactPanel(postId: post.id, response: mine, otherName: post.postedBy.name),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Consent-based contact on an accepted response: my number goes to them
/// only when I share it, and theirs shows only when they share it.
class LfContactPanel extends ConsumerStatefulWidget {
  const LfContactPanel({super.key, required this.postId, required this.response, required this.otherName});

  final String postId;
  final LfResponse response;
  final String otherName;

  @override
  ConsumerState<LfContactPanel> createState() => _LfContactPanelState();
}

class _LfContactPanelState extends ConsumerState<LfContactPanel> {
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      await ref.read(lfActionsProvider).act(widget.postId, widget.response.id, 'share-contact');
      if (mounted) lfNote(context, 'Your number is shared with ${widget.otherName.split(' ').first}.');
    } catch (e) {
      if (mounted) lfError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final contact = widget.response.contact;
    final first = widget.otherName.split(' ').first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (contact.phone != null)
          Row(
            children: [
              Icon(Icons.phone_rounded, size: 18, color: c.volt),
              const SizedBox(width: Sx.s8),
              Expanded(child: Text('$first · ${formatPhone(contact.phone!)}', style: SxType.heading(c.ink, size: 15))),
              SxButton.quiet(
                key: const Key('lfCopyPhone'),
                label: 'Copy',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: contact.phone!));
                  if (context.mounted) lfNote(context, 'Number copied');
                },
              ),
            ],
          )
        else
          Text('$first has not shared a number yet.', style: SxType.caption(c.inkMuted)),
        const SizedBox(height: Sx.s12),
        if (contact.iShared)
          Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 16, color: c.volt),
              const SizedBox(width: Sx.s8),
              Text('You shared your number', style: SxType.caption(c.inkMuted)),
            ],
          )
        else
          SxButton.secondary(
            key: const Key('lfShareContact'),
            icon: Icons.phone_forwarded_rounded,
            label: 'Share my number with $first',
            busy: _busy,
            onPressed: _share,
          ),
      ],
    );
  }
}

class _BottomBar extends ConsumerStatefulWidget {
  const _BottomBar({required this.post});

  final LfPost post;

  @override
  ConsumerState<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends ConsumerState<_BottomBar> {
  bool _busy = false;

  Future<void> _withdraw() async {
    final id = widget.post.myResponse?.id;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(lfActionsProvider).act(widget.post.id, id, 'withdraw');
      if (mounted) lfNote(context, 'Interest withdrawn.');
    } catch (e) {
      if (mounted) lfError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final p = widget.post;
    final mine = p.myResponse;
    final Widget? action;
    if (p.isOwner) {
      action = SxButton(
        key: const Key('lfManageResponses'),
        label: p.responseCount == 0 ? 'No responses yet' : 'View ${p.responseCount} ${p.responseCount == 1 ? 'response' : 'responses'}',
        onPressed: p.responseCount == 0 ? null : () => context.push('/player/looking-for/${p.id}/responses'),
      );
    } else if (mine != null && (mine.status == LfResponseStatus.pending || mine.status == LfResponseStatus.accepted)) {
      action = SxButton.secondary(key: const Key('lfWithdraw'), label: mine.status == LfResponseStatus.accepted ? "I can't make it" : 'Withdraw interest', busy: _busy, onPressed: _withdraw);
    } else if (p.status.active && mine?.status != LfResponseStatus.declined) {
      action = SxButton(
        key: const Key('lfInterestedDetail'),
        icon: Icons.front_hand_rounded,
        label: "I'm interested",
        onPressed: () => showInterestSheet(context, ref, p),
      );
    } else {
      action = null;
    }
    if (action == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s12, Sx.gutter, Sx.s12),
      decoration: BoxDecoration(color: c.canvas, border: Border(top: BorderSide(color: c.line))),
      child: action,
    );
  }
}

class _EditSheet extends ConsumerStatefulWidget {
  const _EditSheet({required this.post});

  final LfPost post;

  @override
  ConsumerState<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends ConsumerState<_EditSheet> {
  late final _title = TextEditingController(text: widget.post.title);
  late final _description = TextEditingController(text: widget.post.description ?? '');
  late int _quantity = widget.post.quantityRequired;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(lfActionsProvider).update(widget.post.id, {
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        if (widget.post.quantityLabel != null) 'quantityRequired': _quantity,
      });
      if (mounted) Navigator.of(context).pop();
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
          Text('Edit request', style: SxType.heading(c.ink, size: 20)),
          const SizedBox(height: Sx.s16),
          TextField(controller: _title, maxLength: 80, decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: Sx.s8),
          TextField(
            controller: _description,
            maxLength: 1000,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Details'),
          ),
          if (p.quantityLabel != null) ...[
            const SizedBox(height: Sx.s8),
            Row(
              children: [
                Expanded(child: Text(p.quantityLabel!, style: SxType.body(c.ink))),
                IconButton(
                  tooltip: 'Fewer',
                  onPressed: _quantity > (p.quantityFilled == 0 ? 1 : p.quantityFilled) ? () => setState(() => _quantity--) : null,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                ),
                Text('$_quantity', style: SxType.number(22, c.ink)),
                IconButton(
                  tooltip: 'More',
                  onPressed: _quantity < 50 ? () => setState(() => _quantity++) : null,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              ],
            ),
          ],
          const SizedBox(height: Sx.s16),
          SxButton(label: 'Save changes', busy: _busy, onPressed: _save),
        ],
      ),
    );
  }
}
