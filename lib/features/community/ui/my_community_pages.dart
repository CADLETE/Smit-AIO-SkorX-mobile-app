import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../community_controller.dart';
import '../data/community.dart';
import '../data/content.dart';
import '../data/community_query.dart';
import 'community_widgets.dart';

/// `/player/community/me`: what I do in pickleball (any number of roles),
/// how people can reach me, and whether I am listed (spec §21).
class MyCommunityPage extends ConsumerStatefulWidget {
  const MyCommunityPage({super.key});

  @override
  ConsumerState<MyCommunityPage> createState() => _MyCommunityPageState();
}

class _MyCommunityPageState extends ConsumerState<MyCommunityPage> {
  MyCommunityProfile? _draft;
  final _headline = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _headline.dispose();
    super.dispose();
  }

  void _edit(MyCommunityProfile Function(MyCommunityProfile) change) => setState(() => _draft = change(_draft!));

  Future<void> _save() async {
    final d = _draft!;
    if (d.roles.isEmpty) {
      showCommunityNote(context, 'Choose at least one role.');
      return;
    }
    setState(() => _saving = true);
    try {
      final headline = _headline.text.trim();
      await ref.read(myCommunityProfileProvider.notifier).save(d.copyWith(
            headline: () => headline.isEmpty ? null : headline,
            // Availability only means something for professional roles.
            availability: () => d.professional ? (d.availability ?? Availability.open) : null,
          ));
      if (!mounted) return;
      showCommunityNote(context, 'Your Community profile is saved.');
      context.canPop() ? context.pop() : context.go('/player/community');
    } catch (e) {
      if (mounted) showCommunityError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final loaded = ref.watch(myCommunityProfileProvider);
    if (_draft == null && loaded.hasValue) {
      _draft = loaded.value;
      _headline.text = _draft!.headline ?? '';
    }
    final d = _draft;
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(onBack: () => context.canPop() ? context.pop() : context.go('/player/community')),
              const SxTitleBar(title: 'My Community'),
              Expanded(
                child: d == null
                    ? const Center(child: BallLoader())
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
                        children: [
                          Text('I am a…', style: SxType.heading(c.ink, size: 18)),
                          const SizedBox(height: 2),
                          Text('Pick every role that fits. You can change this any time.', style: SxType.caption(c.inkMuted)),
                          for (final s in CommunitySector.values)
                            if (s.roles.isNotEmpty) ...[
                              const SizedBox(height: Sx.s16),
                              Text(s.title.toUpperCase(), style: SxType.label(c.inkMuted)),
                              const SizedBox(height: Sx.s8),
                              Wrap(
                                spacing: Sx.s8,
                                runSpacing: Sx.s8,
                                children: [
                                  for (final r in s.roles)
                                    SxChip(
                                      key: Key('myRole-${r.name}'),
                                      label: r.label,
                                      icon: r.icon,
                                      selected: d.roles.contains(r),
                                      onTap: () => _edit((p) => p.copyWith(
                                            roles: p.roles.contains(r) ? ({...p.roles}..remove(r)) : {...p.roles, r},
                                          )),
                                    ),
                                ],
                              ),
                            ],
                          const SizedBox(height: Sx.s12),
                          Text(
                            'Roles show on your profile. A verified badge comes only after SkorX checks your record.',
                            style: SxType.caption(c.inkFaint),
                          ),
                          const SizedBox(height: Sx.section),
                          TextField(
                            key: const Key('myHeadline'),
                            controller: _headline,
                            maxLength: 120,
                            decoration: const InputDecoration(
                              labelText: 'Headline',
                              hintText: 'e.g. Level 2 referee, travels across Gujarat',
                            ),
                          ),
                          if (d.professional) ...[
                            const SizedBox(height: Sx.s16),
                            Text('AVAILABILITY FOR WORK', style: SxType.label(c.inkMuted)),
                            const SizedBox(height: Sx.s8),
                            Wrap(
                              spacing: Sx.s8,
                              runSpacing: Sx.s8,
                              children: [
                                for (final a in Availability.values)
                                  SxChip(
                                    key: Key('availability-${a.name}'),
                                    label: a.label,
                                    selected: (d.availability ?? Availability.open) == a,
                                    onTap: () => _edit((p) => p.copyWith(availability: () => a)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: Sx.s16),
                            Text('CITIES YOU WORK IN', style: SxType.label(c.inkMuted)),
                            const SizedBox(height: Sx.s8),
                            Wrap(
                              spacing: Sx.s8,
                              runSpacing: Sx.s8,
                              children: [
                                for (final city in communityCities.keys)
                                  SxChip(
                                    label: city,
                                    selected: d.serviceArea.contains(city),
                                    onTap: () => _edit((p) => p.copyWith(
                                          serviceArea: p.serviceArea.contains(city)
                                              ? ([...p.serviceArea]..remove(city))
                                              : [...p.serviceArea, city],
                                        )),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: Sx.s16),
                          Text('LANGUAGES', style: SxType.label(c.inkMuted)),
                          const SizedBox(height: Sx.s8),
                          Wrap(
                            spacing: Sx.s8,
                            runSpacing: Sx.s8,
                            children: [
                              for (final l in communityLanguages)
                                SxChip(
                                  label: l,
                                  selected: d.languages.contains(l),
                                  onTap: () => _edit((p) => p.copyWith(
                                        languages: p.languages.contains(l) ? ([...p.languages]..remove(l)) : [...p.languages, l],
                                      )),
                                ),
                            ],
                          ),
                          const SizedBox(height: Sx.section),
                          const _Verification(),
                          SxRows(title: 'Privacy', children: [
                            for (final m in MessagePermission.values)
                              SxRow(
                                key: Key('messagesFrom-${m.name}'),
                                icon: m == MessagePermission.everyone ? Icons.public_rounded : Icons.people_alt_outlined,
                                label: 'Messages from ${m.label.toLowerCase()}',
                                trailing: d.messagesFrom == m ? Icon(Icons.check_rounded, color: c.volt) : const SizedBox(width: 24),
                                onTap: () => _edit((p) => p.copyWith(messagesFrom: m)),
                              ),
                            SxRow(
                              key: const Key('listedSwitch'),
                              icon: Icons.visibility_outlined,
                              label: 'Show me in search',
                              subtitle: d.listed ? 'Anyone on SkorX can find you' : 'Only your connections can find you',
                              trailing: Switch(
                                value: d.listed,
                                onChanged: (v) => _edit((p) => p.copyWith(listed: v)),
                              ),
                            ),
                          ]),
                          const SizedBox(height: Sx.s8),
                          Text('Your phone number is never shown. People reach you through SkorX messages.',
                              style: SxType.caption(c.inkFaint)),
                        ],
                      ),
              ),
              if (d != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s16),
                  child: SxButton(
                    key: const Key('saveMyCommunity'),
                    label: 'Save',
                    busy: _saving,
                    onPressed: d.roles.isEmpty ? null : _save,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum ConnectionsView { requests, connected, sent }

/// `/player/community/connections?tab=requests|connected|sent`
class ConnectionsPage extends ConsumerStatefulWidget {
  const ConnectionsPage({super.key, this.initial = ConnectionsView.connected});

  final ConnectionsView initial;

  @override
  ConsumerState<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends ConsumerState<ConnectionsPage> {
  late ConnectionsView _view = widget.initial;

  @override
  Widget build(BuildContext context) {
    final graph = ref.watch(communityGraphProvider).value ?? const CommunityGraph();
    final status = switch (_view) {
      ConnectionsView.requests => ConnectionStatus.pendingIn,
      ConnectionsView.connected => ConnectionStatus.connected,
      ConnectionsView.sent => ConnectionStatus.pendingOut,
    };
    // Keep the list stable while rows change state (accept, withdraw), so
    // the row stays put and shows its new state.
    final ids = graph.idsWith(status).toList()..sort();
    final members = ref.watch(communityMembersByIdProvider(ids.join(',')));
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(onBack: () => context.canPop() ? context.pop() : context.go('/player/community')),
              const SxTitleBar(title: 'Connections'),
              SxTabs<ConnectionsView>(
                tabs: [
                  (ConnectionsView.requests, 'Requests', graph.incomingCount),
                  (ConnectionsView.connected, 'Connected', graph.connectedCount),
                  (ConnectionsView.sent, 'Sent', graph.idsWith(ConnectionStatus.pendingOut).length),
                ],
                selected: _view,
                onSelect: (v) => setState(() => _view = v),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48),
                  children: [
                    if (ids.isEmpty)
                      EmptyBlock(
                        key: const Key('connectionsEmpty'),
                        icon: Icons.people_outline_rounded,
                        title: switch (_view) {
                          ConnectionsView.requests => 'No requests',
                          ConnectionsView.connected => 'No connections yet',
                          ConnectionsView.sent => 'No pending requests',
                        },
                        message: 'Connect with players, officials and coaches you know or want to work with.',
                        action: SxButton.secondary(
                          label: 'Find people',
                          expand: false,
                          onPressed: () => context.push('/player/community/search'),
                        ),
                      )
                    else
                      members.when(
                        loading: () => const SkeletonList(),
                        error: (_, _) => const SizedBox.shrink(),
                        data: (list) => ListCard(children: [for (final m in list) MemberRow(member: m)]),
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

/// `/player/community/saved`: people, places and communities kept for later.
class SavedPage extends ConsumerWidget {
  const SavedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final graph = ref.watch(communityGraphProvider).value ?? const CommunityGraph();
    final saved = graph.saved;
    final memberIds = graph.savedOf(CommunityTarget.member).toList()..sort();
    final placeIds = graph.savedOf(CommunityTarget.place).toList()..sort();
    final people = ref.watch(communityMembersByIdProvider(memberIds.join(','))).value ?? const [];
    final places = ref.watch(communityPlacesByIdProvider(placeIds.join(','))).value ?? const [];
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(onBack: () => context.canPop() ? context.pop() : context.go('/player/community')),
              const SxTitleBar(title: 'Saved'),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48),
                  children: [
                    if (saved.isEmpty)
                      const EmptyBlock(
                        key: Key('savedEmpty'),
                        icon: Icons.bookmark_border_rounded,
                        title: 'Nothing saved',
                        message: 'Tap the bookmark on a profile, club or venue to keep it here.',
                      ),
                    if (people.isNotEmpty) ...[
                      const SxSection('People'),
                      ListCard(children: [for (final m in people) MemberRow(member: m, showConnect: false)]),
                      const SizedBox(height: Sx.s24),
                    ],
                    if (places.isNotEmpty) ...[
                      const SxSection('Places'),
                      ListCard(children: [for (final p in places) PlaceRow(place: p)]),
                    ],
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

/// Ask SkorX to verify a role. Only saved professional roles can be
/// verified; the badge comes after staff check the evidence.
class _Verification extends ConsumerWidget {
  const _Verification();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final saved = ref.watch(myCommunityProfileProvider).value;
    final roles = [for (final r in saved?.roles ?? const <CommunityRole>{}) if (r != CommunityRole.player) r];
    if (saved == null || !saved.rolesChosen || roles.isEmpty) return const SizedBox.shrink();
    final requests = ref.watch(myVerificationsProvider).value ?? const [];
    return Padding(
      padding: const EdgeInsets.only(bottom: Sx.section),
      child: SxRows(
        title: 'Verification',
        children: [
          for (final r in roles)
            () {
              final latest = requests.where((v) => v.role == r).firstOrNull;
              final (value, canAsk) = switch (latest?.status) {
                null => ('Not verified', true),
                VerificationStatus.pending => ('With the SkorX team', false),
                VerificationStatus.approved => ('Verified', false),
                VerificationStatus.rejected => ('Needs more evidence', true),
              };
              return SxRow(
                key: Key('verify-${r.name}'),
                icon: r.icon,
                label: r.label,
                value: value,
                subtitle: latest?.status == VerificationStatus.rejected ? latest?.reviewNote : null,
                trailing: latest?.status == VerificationStatus.approved
                    ? VerifiedMark(size: 20, label: '${r.label}, verified')
                    : canAsk
                        ? Icon(Icons.chevron_right_rounded, color: c.inkFaint)
                        : Icon(Icons.hourglass_top_rounded, size: 18, color: c.caution),
                onTap: canAsk ? () => showVerificationSheet(context, ref, r) : null,
              );
            }(),
        ],
      ),
    );
  }
}

Future<void> showVerificationSheet(BuildContext context, WidgetRef ref, CommunityRole role) => showSxSheet<void>(
      context,
      builder: (ctx) => _VerificationSheet(role: role),
    );

class _VerificationSheet extends ConsumerStatefulWidget {
  const _VerificationSheet({required this.role});

  final CommunityRole role;

  @override
  ConsumerState<_VerificationSheet> createState() => _VerificationSheetState();
}

class _VerificationSheetState extends ConsumerState<_VerificationSheet> {
  final _evidence = TextEditingController();
  final _link = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _evidence.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await ref.read(communityRepositoryProvider).requestVerification(
            role: widget.role,
            evidence: _evidence.text.trim(),
            links: [if (_link.text.trim().isNotEmpty) _link.text.trim()],
          );
      ref.invalidate(myVerificationsProvider);
      if (mounted) {
        Navigator.pop(context);
        showCommunityNote(context, 'Sent. The SkorX team usually replies within a few days.');
      }
    } catch (e) {
      if (mounted) showCommunityError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final hint = switch (widget.role) {
      CommunityRole.referee || CommunityRole.official => 'Certification level, tournaments you have officiated, who can vouch for you',
      CommunityRole.coach || CommunityRole.trainer => 'Coaching certificates, where you coach, how long',
      CommunityRole.organizer || CommunityRole.eventManager => 'Events you have run, your organisation',
      _ => 'Events you have worked and where to see your work',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Verify: ${widget.role.label}', style: SxType.title(c.ink, size: 26)),
            const SizedBox(height: Sx.s4),
            Text('A SkorX team member checks what you send. The badge means your record was checked, not that you are popular.',
                style: SxType.body(c.inkMuted, size: 14)),
            const SizedBox(height: Sx.s16),
            TextField(
              key: const Key('verifyEvidence'),
              controller: _evidence,
              minLines: 4,
              maxLines: 8,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Your evidence', hintText: hint, alignLabelWithHint: true),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _link,
              maxLength: 300,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Link to certificate or portfolio (optional)'),
            ),
            const SizedBox(height: Sx.s8),
            SxButton(
              key: const Key('submitVerification'),
              label: 'Send to SkorX',
              busy: _busy,
              onPressed: _evidence.text.trim().length < 20 ? null : _submit,
            ),
            const SizedBox(height: Sx.s8),
            Text('At least 20 characters.', textAlign: TextAlign.center, style: SxType.caption(c.inkFaint)),
          ],
        ),
      ),
    );
  }
}
