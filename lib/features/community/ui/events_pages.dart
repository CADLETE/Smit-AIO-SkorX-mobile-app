import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../community_controller.dart';
import '../data/community.dart';
import '../data/community_query.dart';
import '../data/content.dart';
import '../data/messages.dart';
import 'community_widgets.dart';

String eventRoute(String id) => '/player/community/events/$id';

/// "Sat, 4 Oct · 7–9 AM".
String eventWhen(CommunityEvent e) {
  final sameDay = e.startsAt.year == e.endsAt.year && e.startsAt.month == e.endsAt.month && e.startsAt.day == e.endsAt.day;
  return sameDay
      ? '${dayDate(e.startsAt)} · ${timeShort(e.startsAt)}–${timeShort(e.endsAt)}'
      : '${dayDate(e.startsAt)} – ${dayDate(e.endsAt)}';
}

/// An event in a sideways strip on the hub, a place or a community.
class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, this.width = 236});

  final CommunityEvent event;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final e = event;
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        label: '${e.kind.label}: ${e.title}, ${eventWhen(e)}, ${e.placeName ?? e.city}',
        excludeSemantics: true,
        child: Tappable(
          key: Key('eventCard-${e.id}'),
          onTap: () => context.push(eventRoute(e.id)),
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
                    _DateBlock(date: e.startsAt),
                    const SizedBox(width: Sx.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(e.kind.icon, size: 13, color: c.inkMuted),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(e.kind.label.toUpperCase(),
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.label(c.inkMuted, size: 10.5)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(timeShort(e.startsAt), style: SxType.caption(c.ink, size: 12.5).copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Sx.s12),
                Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 16)),
                const SizedBox(height: 2),
                Text(e.placeName ?? e.city, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted, size: 12.5)),
                const Spacer(),
                const SizedBox(height: Sx.s8),
                _Attendance(event: e),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      width: 46,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(gradient: c.brand, borderRadius: BorderRadius.circular(Sx.radiusSm)),
      child: Column(
        children: [
          Text(monthsShort[date.month - 1].toUpperCase(), style: SxType.label(c.onVolt, size: 10.5, weight: FontWeight.w800)),
          Text('${date.day}', style: SxType.number(22, c.onVolt, weight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// "9 going · 3 spots left", "Full", "You're going".
class _Attendance extends StatelessWidget {
  const _Attendance({required this.event});

  final CommunityEvent event;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final e = event;
    final (text, color) = e.cancelled
        ? ('Cancelled', c.inkFaint)
        : e.myRsvp == RsvpStatus.going
            ? ("You're going", c.volt)
            : e.full
                ? ('Full · ${e.going} going', c.caution)
                : ('${e.going} going${e.spotsLeft != null ? ' · ${e.spotsLeft} left' : ''}', c.inkMuted);
    return Text(text,
        maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(color, size: 12.5).copyWith(fontWeight: FontWeight.w700));
  }
}

/// `/player/community/events`: clinics, open play, meetups near you.
class EventsPage extends ConsumerStatefulWidget {
  const EventsPage({super.key});

  @override
  ConsumerState<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends ConsumerState<EventsPage> {
  EventKind? _kind;

  @override
  Widget build(BuildContext context) {
    final city = ref.watch(communityLocationProvider).city;
    final events = ref.watch(communityEventsProvider((city: city, groupId: null, placeId: null)));
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(onBack: () => context.canPop() ? context.pop() : context.go('/player/community')),
              SxTitleBar(
                title: 'Events',
                actions: [
                  SxIconAction(
                    key: const Key('hostEvent'),
                    icon: Icons.add_rounded,
                    label: 'Host an event',
                    onTap: () => context.push('/player/community/events/new'),
                  ),
                ],
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(Sx.gutter, 2, Sx.gutter, 8),
                  children: [
                    SxChip(label: 'All', selected: _kind == null, onTap: () => setState(() => _kind = null)),
                    for (final k in EventKind.values) ...[
                      const SizedBox(width: Sx.s8),
                      SxChip(
                        key: Key('eventKind-${k.name}'),
                        label: k.label,
                        icon: k.icon,
                        selected: _kind == k,
                        onTap: () => setState(() => _kind = _kind == k ? null : k),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: events.when(
                  loading: () => const Padding(padding: EdgeInsets.all(Sx.gutter), child: SkeletonList()),
                  error: (_, _) => ErrorBlock(message: 'Could not load events.', onRetry: () => ref.invalidate(communityEventsProvider)),
                  data: (all) {
                    final list = [for (final e in all) if (_kind == null || e.kind == _kind) e];
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48),
                      children: [
                        if (list.isEmpty)
                          EmptyBlock(
                            key: const Key('eventsEmpty'),
                            icon: Icons.event_busy_rounded,
                            title: 'Nothing on yet',
                            message: city == null
                                ? 'No events coming up. Start one for your crew.'
                                : 'No events in $city yet. Start one for your crew.',
                            action: SxButton(
                              label: 'Host an event',
                              expand: false,
                              onPressed: () => context.push('/player/community/events/new'),
                            ),
                          )
                        else
                          ListCard(children: [for (final e in list) _EventRow(event: e)]),
                        const SizedBox(height: Sx.s16),
                        Text('Tournaments are in Explore › Tournaments.', style: SxType.caption(context.sx.inkFaint)),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final CommunityEvent event;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final e = event;
    return Tappable(
      key: Key('eventRow-${e.id}'),
      onTap: () => context.push(eventRoute(e.id)),
      radius: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Sx.s12),
        child: Row(
          children: [
            _DateBlock(date: e.startsAt),
            const SizedBox(width: Sx.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 16)),
                  const SizedBox(height: 2),
                  Text('${e.kind.label} · ${timeShort(e.startsAt)} · ${e.placeName ?? e.city}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted, size: 12.5)),
                  const SizedBox(height: 2),
                  _Attendance(event: e),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// `/player/community/events/:id`
class EventPage extends ConsumerWidget {
  const EventPage({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(communityEventProvider(eventId));
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: event.when(
            loading: () => const Column(children: [SxBackBar(), Expanded(child: Center(child: BallLoader()))]),
            error: (_, _) => const Column(
              children: [
                SxBackBar(),
                Expanded(child: EmptyBlock(icon: Icons.event_busy_rounded, title: 'Event not found', message: 'It may have been cancelled.')),
              ],
            ),
            data: (e) => Column(
              children: [
                SxBackBar(
                  actions: [
                    OverflowMenu(items: [
                      if (e.mine && !e.cancelled) ('Cancel event', Icons.event_busy_rounded, () => _cancel(context, ref), true),
                      ('Report', Icons.flag_outlined, () => showReportSheet(context, ref, ReportTarget.event, e.id, e.title), true),
                    ]),
                  ],
                ),
                Expanded(child: _EventBody(event: e)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this event?'),
        content: const Text('Everyone going is told straight away.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          FilledButton(key: const Key('confirmCancelEvent'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel event')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(communityEventProvider(eventId).notifier).cancel();
    } catch (e) {
      if (context.mounted) showCommunityError(context, e);
    }
  }
}

class _EventBody extends ConsumerStatefulWidget {
  const _EventBody({required this.event});

  final CommunityEvent event;

  @override
  ConsumerState<_EventBody> createState() => _EventBodyState();
}

class _EventBodyState extends ConsumerState<_EventBody> {
  bool _busy = false;

  Future<void> _rsvp(RsvpStatus? status) async {
    setState(() => _busy = true);
    try {
      await ref.read(communityEventProvider(widget.event.id).notifier).rsvp(status);
      if (mounted && status == RsvpStatus.going) showCommunityNote(context, "You're going. See you there!");
    } catch (e) {
      if (mounted) showCommunityError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final e = widget.event;
    final going = e.myRsvp == RsvpStatus.going;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48),
      children: [
        Row(
          children: [
            Icon(e.kind.icon, size: 16, color: c.inkMuted),
            const SizedBox(width: 6),
            Text(e.kind.label.toUpperCase(), style: SxType.label(c.inkMuted)),
            if (e.cancelled) ...[
              const SizedBox(width: Sx.s8),
              Text('CANCELLED', key: const Key('eventCancelled'), style: SxType.label(c.caution, weight: FontWeight.w800)),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Semantics(header: true, child: Text(e.title, style: SxType.title(c.ink, size: 30))),
        const SizedBox(height: Sx.s12),
        ListCard(children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Sx.s8),
            child: Column(
              children: [
                FactLine(icon: Icons.schedule_rounded, label: 'When', value: eventWhen(e)),
                FactLine(icon: Icons.place_outlined, label: 'Where', value: [?e.placeName, ?e.address, e.city].join(', ')),
                FactLine(icon: Icons.person_outline_rounded, label: 'Host', value: e.organizerName),
                if (e.level != null) FactLine(icon: Icons.bar_chart_rounded, label: 'Level', value: e.level!),
                FactLine(icon: Icons.currency_rupee_rounded, label: 'Fee', value: e.feeInr == null || e.feeInr == 0 ? 'Free' : formatInr(e.feeInr!)),
                FactLine(
                  icon: Icons.groups_2_outlined,
                  label: 'People',
                  value: [
                    '${e.going} going',
                    if (e.interested > 0) '${e.interested} interested',
                    if (e.capacity != null) '${e.capacity} spots',
                  ].join(' · '),
                ),
              ],
            ),
          ),
        ]),
        if (e.about.isNotEmpty) ...[
          const SizedBox(height: Sx.s16),
          Text(e.about, style: SxType.body(c.ink)),
        ],
        const SizedBox(height: Sx.s20),
        if (!e.cancelled) ...[
          if (e.mine)
            Text("You're hosting this event.", style: SxType.body(c.inkMuted, size: 14))
          else if (going)
            SxButton.secondary(
              key: const Key('leaveEvent'),
              label: "Going · Can't make it",
              icon: Icons.check_circle_rounded,
              busy: _busy,
              onPressed: () => _rsvp(null),
            )
          else
            SxButton(
              key: const Key('rsvpGoing'),
              label: e.full ? 'Full' : "I'm going",
              icon: Icons.event_available_rounded,
              busy: _busy,
              onPressed: e.full ? null : () => _rsvp(RsvpStatus.going),
            ),
          if (!e.mine && !going) ...[
            const SizedBox(height: Sx.s8),
            SxButton.secondary(
              key: const Key('rsvpInterested'),
              label: e.myRsvp == RsvpStatus.interested ? 'Interested · Undo' : 'Interested',
              icon: e.myRsvp == RsvpStatus.interested ? Icons.star_rounded : Icons.star_border_rounded,
              onPressed: _busy ? null : () => _rsvp(e.myRsvp == RsvpStatus.interested ? null : RsvpStatus.interested),
            ),
          ],
          if (e.mine || e.myRsvp != null) ...[
            const SizedBox(height: Sx.s8),
            SxButton.quiet(
              key: const Key('eventChat'),
              label: 'Event chat',
              icon: Icons.forum_outlined,
              onPressed: () => openConversation(context, ref, ConversationKind.event, e.id),
            ),
          ],
        ],
        if (e.placeId != null || e.tournamentId != null || e.groupId != null)
          DetailSection(
            title: 'Linked',
            child: SxRows(children: [
              if (e.placeId != null)
                SxRow(icon: Icons.stadium_outlined, label: e.placeName ?? 'Venue', onTap: () => context.push(placeRoute(e.placeId!))),
              if (e.groupId != null) SxRow(icon: Icons.diversity_3_outlined, label: 'Community', onTap: () => context.push(groupRoute(e.groupId!))),
              if (e.tournamentId != null)
                SxRow(icon: Icons.emoji_events_outlined, label: 'Tournament', onTap: () => context.push('/player/tournament/${e.tournamentId}')),
            ]),
          ),
      ],
    );
  }
}

/// `/player/community/events/new?placeId&groupId`: host a clinic, open play or meetup.
class CreateEventPage extends ConsumerStatefulWidget {
  const CreateEventPage({super.key, this.placeId, this.groupId});

  final String? placeId;
  final String? groupId;

  @override
  ConsumerState<CreateEventPage> createState() => _CreateEventPageState();
}

class _CreateEventPageState extends ConsumerState<CreateEventPage> {
  final _title = TextEditingController();
  final _about = TextEditingController();
  final _address = TextEditingController();
  EventKind _kind = EventKind.openPlay;
  late DateTime _day = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _start = const TimeOfDay(hour: 7, minute: 0);
  int _hours = 2;
  int? _capacity;
  int _fee = 0;
  String? _level;
  late String _city = ref.read(communityLocationProvider).city ?? communityCities.keys.first;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _about.dispose();
    _address.dispose();
    super.dispose();
  }

  DateTime get _startsAt => DateTime(_day.year, _day.month, _day.day, _start.hour, _start.minute);

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final e = await ref.read(communityRepositoryProvider).createEvent(EventDraft(
            kind: _kind,
            title: _title.text,
            about: _about.text,
            startsAt: _startsAt,
            endsAt: _startsAt.add(Duration(hours: _hours)),
            city: _city,
            address: _address.text.trim().isEmpty ? null : _address.text.trim(),
            placeId: widget.placeId,
            groupId: widget.groupId,
            capacity: _capacity,
            feeInr: _fee == 0 ? null : _fee,
            level: _level,
          ));
      ref.invalidate(communityEventsProvider);
      if (!mounted) return;
      context.pushReplacement(eventRoute(e.id));
    } catch (e) {
      if (mounted) showCommunityError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: Sx.s20, bottom: Sx.s8),
          child: Text(t.toUpperCase(), style: SxType.label(c.inkMuted)),
        );
    Widget chips<T>(List<T> values, T selected, String Function(T) name, ValueChanged<T> onPick, {String keyPrefix = ''}) => Wrap(
          spacing: Sx.s8,
          runSpacing: Sx.s8,
          children: [
            for (final v in values)
              SxChip(key: Key('$keyPrefix${name(v)}'), label: name(v), selected: v == selected, onTap: () => setState(() => onPick(v))),
          ],
        );
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(onBack: () => context.canPop() ? context.pop() : context.go('/player/community/events')),
              const SxTitleBar(title: 'Host an event'),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
                  children: [
                    label('What'),
                    chips(EventKind.values, _kind, (k) => k.label, (k) => _kind = k, keyPrefix: 'newKind-'),
                    const SizedBox(height: Sx.s16),
                    TextField(
                      key: const Key('eventTitle'),
                      controller: _title,
                      maxLength: 80,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Sunday open play'),
                      onChanged: (_) => setState(() {}),
                    ),
                    TextField(
                      controller: _about,
                      maxLength: 1000,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(labelText: 'Details (optional)', hintText: 'Level, what to bring, how to find you'),
                    ),
                    label('When'),
                    Wrap(
                      spacing: Sx.s8,
                      runSpacing: Sx.s8,
                      children: [
                        SxChip(
                          key: const Key('eventDay'),
                          icon: Icons.calendar_today_rounded,
                          label: dayDate(_day),
                          selected: false,
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _day,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 180)),
                            );
                            if (picked != null) setState(() => _day = picked);
                          },
                        ),
                        SxChip(
                          icon: Icons.schedule_rounded,
                          label: _start.format(context),
                          selected: false,
                          onTap: () async {
                            final picked = await showTimePicker(context: context, initialTime: _start);
                            if (picked != null) setState(() => _start = picked);
                          },
                        ),
                        for (final h in [1, 2, 3, 4])
                          SxChip(label: '$h h', selected: _hours == h, onTap: () => setState(() => _hours = h)),
                      ],
                    ),
                    label('Where'),
                    chips(communityCities.keys.toList(), _city, (x) => x, (x) => _city = x),
                    const SizedBox(height: Sx.s12),
                    TextField(
                      controller: _address,
                      maxLength: 160,
                      decoration: const InputDecoration(labelText: 'Venue or address (optional)'),
                    ),
                    label('Spots'),
                    chips<int?>([null, 8, 12, 16, 24, 32], _capacity, (x) => x == null ? 'No limit' : '$x', (x) => _capacity = x),
                    label('Fee per person'),
                    chips([0, 200, 300, 500, 800], _fee, (x) => x == 0 ? 'Free' : formatInr(x), (x) => _fee = x),
                    label('Level'),
                    chips<String?>([null, ...communityLevels], _level, (x) => x ?? 'All levels', (x) => _level = x),
                    const SizedBox(height: Sx.s16),
                    Text('Tournaments are created in the organiser app, not here.', style: SxType.caption(c.inkFaint)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s16),
                child: SxButton(
                  key: const Key('createEvent'),
                  label: 'Post event',
                  busy: _busy,
                  onPressed: _title.text.trim().length < 3 ? null : _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
