import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../data/looking_for.dart';
import '../looking_for_controller.dart';
import 'lf_widgets.dart';
import 'post_detail_page.dart' show LfContactPanel;

/// Everyone who answered a request, in the order they answered, with the
/// facts that help decide. SkorX never ranks them (docs/LOOKING-FOR.md §7).
class LookingForResponsesPage extends ConsumerWidget {
  const LookingForResponsesPage({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final post = ref.watch(lfPostProvider(postId)).value;
    final responses = ref.watch(lfResponsesProvider(postId));
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(title: 'Responses', onBack: () => lfBack(context)),
              if (post != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s12),
                  child: Row(
                    children: [
                      Expanded(child: Text(post.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 16))),
                      LfStatusMark(post),
                    ],
                  ),
                ),
              Expanded(
                child: responses.when(
                  loading: () => ListView(padding: const EdgeInsets.all(Sx.gutter), children: const [SkeletonList(rows: 3, rowHeight: 140)]),
                  error: (e, _) => ErrorBlock(message: 'Could not load responses.', onRetry: () => ref.invalidate(lfResponsesProvider(postId))),
                  data: (list) => RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(lfResponsesProvider(postId));
                      await ref.read(lfResponsesProvider(postId).future);
                    },
                    child: list.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s32, Sx.gutter, Sx.s32),
                            children: const [
                              EmptyBlock(
                                icon: Icons.hourglass_empty_rounded,
                                title: 'No responses yet',
                                message: 'SkorX has told people it fits. Share the request to reach more.',
                              ),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s32),
                            itemCount: list.length + 1,
                            separatorBuilder: (_, _) => const SizedBox(height: Sx.s12),
                            itemBuilder: (context, i) => i == 0
                                ? Text(
                                    post == null
                                        ? '${list.length} responses'
                                        : '${list.length} ${list.length == 1 ? 'response' : 'responses'} · ${post.quantityFilled} of ${post.quantityRequired} accepted',
                                    style: SxType.caption(c.inkMuted),
                                  )
                                : _ResponseCard(postId: postId, response: list[i - 1], full: post != null && post.openPlaces == 0),
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

class _ResponseCard extends ConsumerStatefulWidget {
  const _ResponseCard({required this.postId, required this.response, required this.full});

  final String postId;
  final LfResponse response;

  /// Every place is taken: accepting is not possible until one frees up.
  final bool full;

  @override
  ConsumerState<_ResponseCard> createState() => _ResponseCardState();
}

class _ResponseCardState extends ConsumerState<_ResponseCard> {
  String? _busy;

  Future<void> _act(String action) async {
    setState(() => _busy = action);
    try {
      await ref.read(lfActionsProvider).act(widget.postId, widget.response.id, action);
    } catch (e) {
      if (mounted) lfError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final r = widget.response;
    final person = r.person;
    final name = person?.name ?? 'SkorX player';
    final facts = [
      ?person?.city,
      if (person?.skillLevel != null) 'Level ${person!.skillLevel}',
      if (person != null) '${person.matchesPlayed} ${person.matchesPlayed == 1 ? 'match' : 'matches'} on SkorX',
      if (person != null && person.recentMatches > 0) '${person.recentMatches} in the last 60 days',
      for (final role in person?.roles ?? const <String>[]) ?lfRoles[role],
    ];
    return Container(
      key: Key('lfResponse-${r.id}'),
      padding: const EdgeInsets.all(Sx.s16),
      decoration: BoxDecoration(
        gradient: c.card,
        borderRadius: BorderRadius.circular(Sx.radiusLg),
        border: Border.all(color: r.status == LfResponseStatus.accepted ? c.volt.withValues(alpha: 0.6) : c.cardEdge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SxAvatar(name: name, size: 44),
              const SizedBox(width: Sx.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: SxType.heading(c.ink, size: 16)),
                    Text(timeAgo(r.respondedAt, DateTime.now()), style: SxType.caption(c.inkFaint, size: 12)),
                  ],
                ),
              ),
              Text(
                switch (r.status) {
                  LfResponseStatus.pending => 'NEW',
                  LfResponseStatus.accepted => 'ACCEPTED',
                  LfResponseStatus.declined => 'DECLINED',
                  LfResponseStatus.withdrawn => 'WITHDRAWN',
                },
                style: SxType.label(
                  r.status == LfResponseStatus.accepted
                      ? c.volt
                      : r.status == LfResponseStatus.pending
                          ? c.info
                          : c.inkMuted,
                  size: 11,
                ),
              ),
            ],
          ),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: Sx.s12),
            Text(facts.join(' · '), style: SxType.caption(c.inkMuted)),
          ],
          if (r.availabilityConfirmed) ...[
            const SizedBox(height: Sx.s4),
            Row(
              children: [
                Icon(Icons.event_available_rounded, size: 15, color: c.volt),
                const SizedBox(width: 6),
                Flexible(child: Text('Confirmed they can make it', style: SxType.caption(c.ink, size: 12.5))),
              ],
            ),
          ],
          if (r.message != null && r.message!.trim().isNotEmpty) ...[
            const SizedBox(height: Sx.s12),
            Text('"${r.message!.trim()}"', style: SxType.body(c.ink, size: 14.5)),
          ],
          if (r.status == LfResponseStatus.pending) ...[
            const SizedBox(height: Sx.s16),
            Row(
              children: [
                Expanded(
                  child: SxButton.secondary(
                    key: Key('lfDecline-${r.id}'),
                    label: 'Decline',
                    height: 46,
                    busy: _busy == 'decline',
                    onPressed: _busy == null ? () => _act('decline') : null,
                  ),
                ),
                const SizedBox(width: Sx.s12),
                Expanded(
                  child: SxButton(
                    key: Key('lfAccept-${r.id}'),
                    label: 'Accept',
                    height: 46,
                    busy: _busy == 'accept',
                    onPressed: _busy == null && !widget.full ? () => _act('accept') : null,
                  ),
                ),
              ],
            ),
            if (widget.full) ...[
              const SizedBox(height: Sx.s8),
              Text('Every place is filled. Edit the request to take more people.', style: SxType.caption(c.inkMuted, size: 12.5)),
            ],
          ],
          if (r.status == LfResponseStatus.accepted) ...[
            const SizedBox(height: Sx.s16),
            LfContactPanel(postId: widget.postId, response: r, otherName: name),
          ],
        ],
      ),
    );
  }
}
