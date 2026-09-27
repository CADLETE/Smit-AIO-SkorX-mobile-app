import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../../explore/explore_page.dart' show DateStrip;
import '../data/courts.dart';

/// A venue: what it is, what it costs, and one button to book.
class VenuePage extends ConsumerWidget {
  const VenuePage({super.key, required this.venueId, this.initialDate, this.initialHour});

  final String venueId;
  final DateTime? initialDate;
  final int? initialHour;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final venue = ref.watch(venueProvider(venueId));
    final c = context.sx;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(title: 'Venue', onBack: () => context.canPop() ? context.pop() : context.go('/player/explore?view=courts')),
              Expanded(
                child: switch (venue) {
                  AsyncData(:final value) => _VenueBody(venue: value),
                  AsyncError(:final error) => EmptyBlock(
                      icon: Icons.stadium_outlined,
                      title: 'Not available',
                      message: error is ApiException ? error.message : 'This venue did not load.',
                    ),
                  _ => const Padding(padding: EdgeInsets.all(Sx.gutter), child: SkeletonList(rows: 4, rowHeight: 90)),
                },
              ),
              if (venue.value case final v?)
                Container(
                  padding: EdgeInsets.fromLTRB(Sx.gutter, Sx.s12, Sx.gutter, Sx.s12 + MediaQuery.paddingOf(context).bottom),
                  decoration: BoxDecoration(color: c.canvas, border: Border(top: BorderSide(color: c.line))),
                  child: SxButton(
                    key: const Key('bookCourt'),
                    label: 'Book a court',
                    onPressed: () => showSxSheet<void>(
                      context,
                      builder: (_) => SlotSheet(venue: v, initialDate: initialDate, initialHour: initialHour),
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

class _VenueBody extends StatelessWidget {
  const _VenueBody({required this.venue});

  final Venue venue;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final v = venue;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48),
      children: [
        // Until venue photos come from the API: the venue's courts, drawn.
        ClipRRect(
          borderRadius: BorderRadius.circular(Sx.radiusLg),
          child: Container(
            height: 150,
            color: c.surface,
            child: CustomPaint(painter: _CourtsPlan(count: v.courts, line: c.line, ink: c.inkMuted)),
          ),
        ),
        const SizedBox(height: Sx.s24),
        Text(v.name.toUpperCase(), style: SxType.title(c.ink, size: 32)),
        const SizedBox(height: Sx.s8),
        Text(
          '${v.area}, ${v.city} · ${v.distanceKm.toStringAsFixed(1)} km away',
          style: SxType.body(c.inkMuted, size: 14),
        ),
        const SizedBox(height: Sx.s24),
        Row(
          children: [
            Expanded(child: Stat(value: '${v.courts}', label: 'Courts', size: 28)),
            Expanded(child: Stat(value: v.rating.toStringAsFixed(1), label: '${v.reviews} reviews', size: 28)),
            Expanded(child: Stat(value: v.indoor ? 'IN' : 'OUT', label: v.indoor ? 'Indoor' : 'Outdoor', size: 28)),
          ],
        ),
        const SizedBox(height: Sx.section),
        SxRows(
          title: 'Pricing',
          children: [
            SxRow(label: 'Off-peak', value: '${formatInr(v.pricePerHour)} / hour'),
            SxRow(label: 'Peak · 6–10 PM', value: '${formatInr(v.peakPricePerHour)} / hour'),
            SxRow(label: 'Open', value: '${timeShort(DateTime(2000, 1, 1, v.openHour))} – ${timeShort(DateTime(2000, 1, 1, v.closeHour))}'),
            SxRow(label: 'Surface', value: v.surface),
          ],
        ),
        if (v.facilities.isNotEmpty) ...[
          const SizedBox(height: Sx.section),
          const SxSection('Facilities'),
          Wrap(
            spacing: Sx.s8,
            runSpacing: Sx.s8,
            children: [
              for (final f in v.facilities)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Sx.s12, vertical: 7),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: c.line)),
                  child: Text(f, style: SxType.caption(c.ink)),
                ),
            ],
          ),
        ],
        const SizedBox(height: Sx.section),
        SxRows(
          title: 'Location',
          children: [
            SxRow(icon: Icons.place_outlined, label: v.address ?? '${v.area}, ${v.city}'),
            if (v.phone != null) SxRow(icon: Icons.call_outlined, label: v.phone!),
          ],
        ),
        if (v.rules.isNotEmpty) ...[
          const SizedBox(height: Sx.section),
          const SxSection('Booking rules'),
          for (final r in v.rules)
            Padding(
              padding: const EdgeInsets.only(bottom: Sx.s8),
              child: Text('— $r', style: SxType.body(c.ink, size: 14)),
            ),
        ],
      ],
    );
  }
}

class _CourtsPlan extends CustomPainter {
  _CourtsPlan({required this.count, required this.line, required this.ink});

  final int count;
  final Color line;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final n = count.clamp(1, 6);
    const gap = 14.0;
    final w = (size.width - gap * (n + 1)) / n;
    final h = size.height - 36;
    final p = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final net = Paint()
      ..color = ink
      ..strokeWidth = 2;
    for (var i = 0; i < n; i++) {
      final r = Rect.fromLTWH(gap + i * (w + gap), 18, w, h);
      canvas.drawRect(r, p);
      final mid = r.center.dy;
      canvas.drawLine(Offset(r.left, mid), Offset(r.right, mid), net);
      final kitchen = h * 0.16;
      canvas.drawLine(Offset(r.left, mid - kitchen), Offset(r.right, mid - kitchen), p);
      canvas.drawLine(Offset(r.left, mid + kitchen), Offset(r.right, mid + kitchen), p);
      canvas.drawLine(Offset(r.center.dx, r.top), Offset(r.center.dx, mid - kitchen), p);
      canvas.drawLine(Offset(r.center.dx, mid + kitchen), Offset(r.center.dx, r.bottom), p);
    }
  }

  @override
  bool shouldRepaint(_CourtsPlan old) => old.count != count || old.line != line;
}

/// Steps 2–4 of booking: date, time, court. Then Continue.
class SlotSheet extends ConsumerStatefulWidget {
  const SlotSheet({super.key, required this.venue, this.initialDate, this.initialHour});

  final Venue venue;
  final DateTime? initialDate;
  final int? initialHour;

  @override
  ConsumerState<SlotSheet> createState() => _SlotSheetState();
}

class _SlotSheetState extends ConsumerState<SlotSheet> {
  late DateTime _date = () {
    final d = widget.initialDate ?? DateTime.now();
    return DateTime(d.year, d.month, d.day);
  }();
  late int? _hour = widget.initialHour;
  int? _court;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final v = widget.venue;
    final slots = ref.watch(slotsProvider((v.id, _date)));
    final today = DateTime.now();
    final days = [for (var i = 0; i < 7; i++) DateTime(today.year, today.month, today.day + i)];
    final slot = slots.value?.where((s) => s.start.hour == _hour).firstOrNull;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('BOOK A COURT', style: SxType.title(c.ink, size: 28)),
            Text(v.name, style: SxType.caption(c.inkMuted)),
            const SizedBox(height: Sx.s24),
            const SxSection('Date'),
            DateStrip(
              days: days,
              selected: _date,
              onSelect: (d) => setState(() {
                _date = d;
                _hour = null;
                _court = null;
              }),
            ),
            const SizedBox(height: Sx.s24),
            const SxSection('Time'),
            switch (slots) {
              AsyncData(:final value) when value.every((s) => !s.available) => Text(
                  'Fully booked on this day. Try the next one.',
                  style: SxType.body(c.inkMuted, size: 14),
                ),
              AsyncData(:final value) => Wrap(
                  spacing: Sx.s8,
                  runSpacing: Sx.s8,
                  children: [
                    for (final s in value)
                      _Choice(
                        label: timeShort(s.start),
                        sublabel: s.available ? formatInr(s.price) : 'Full',
                        selected: s.start.hour == _hour,
                        enabled: s.available,
                        semantics: '${timeShort(s.start)}, ${s.available ? '${s.freeCourts.length} courts free' : 'full'}',
                        onTap: () => setState(() {
                          _hour = s.start.hour;
                          _court = s.freeCourts.length == 1 ? s.freeCourts.first : null;
                        }),
                      ),
                  ],
                ),
              _ => const Skeleton(height: 100),
            },
            if (slot != null) ...[
              const SizedBox(height: Sx.s24),
              const SxSection('Court'),
              Wrap(
                spacing: Sx.s8,
                runSpacing: Sx.s8,
                children: [
                  for (var n = 1; n <= v.courts; n++)
                    _Choice(
                      label: 'Court $n',
                      selected: _court == n,
                      enabled: slot.freeCourts.contains(n),
                      semantics: 'Court $n, ${slot.freeCourts.contains(n) ? 'free' : 'booked'}',
                      onTap: () => setState(() => _court = n),
                    ),
                ],
              ),
            ],
            const SizedBox(height: Sx.s32),
            SxButton(
              key: const Key('continueBooking'),
              label: _court == null || slot == null ? 'Pick a time and court' : 'Continue · ${formatInr(slot.price + bookingFee)}',
              onPressed: _court == null || slot == null
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      GoRouter.of(context).push('/player/venue/${v.id}/confirm?date=${isoDay(_date)}&hour=$_hour&court=$_court');
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.semantics,
    this.sublabel,
  });

  final String label;
  final String? sublabel;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final fg = selected ? c.canvas : (enabled ? c.ink : c.inkFaint);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: semantics,
      excludeSemantics: true,
      child: Tappable(
        onTap: enabled ? onTap : null,
        radius: Sx.radiusSm,
        child: AnimatedContainer(
          duration: Sx.fast,
          width: 84,
          padding: const EdgeInsets.symmetric(vertical: Sx.s8),
          decoration: BoxDecoration(
            color: selected ? c.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(Sx.radiusSm),
            border: Border.all(color: selected ? c.ink : c.line),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: SxType.number(16, fg).copyWith(decoration: enabled ? null : TextDecoration.lineThrough),
              ),
              if (sublabel != null) ...[
                const SizedBox(height: 2),
                Text(sublabel!, style: SxType.caption(selected ? c.canvas.withValues(alpha: 0.7) : c.inkMuted, size: 11)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Step 5: confirm and pay, then the booking code.
class ConfirmBookingPage extends ConsumerStatefulWidget {
  const ConfirmBookingPage({super.key, required this.venueId, required this.start, required this.court});

  factory ConfirmBookingPage.fromQuery(String venueId, Map<String, String> q) {
    final d = DateTime.tryParse(q['date'] ?? '') ?? DateTime.now();
    final hour = int.tryParse(q['hour'] ?? '') ?? 18;
    return ConfirmBookingPage(
      venueId: venueId,
      start: DateTime(d.year, d.month, d.day, hour),
      court: int.tryParse(q['court'] ?? '') ?? 1,
    );
  }

  final String venueId;
  final DateTime start;
  final int court;

  @override
  ConsumerState<ConfirmBookingPage> createState() => _ConfirmBookingPageState();
}

class _ConfirmBookingPageState extends ConsumerState<ConfirmBookingPage> {
  bool _busy = false;
  String? _error;
  Booking? _booked;

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final b = await ref.read(courtRepositoryProvider).book(widget.venueId, widget.start, widget.court);
      ref.invalidate(myBookingsProvider);
      ref.invalidate(venueSearchProvider);
      ref.invalidate(slotsProvider);
      if (mounted) setState(() => _booked = b);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final venue = ref.watch(venueProvider(widget.venueId)).value;
    final price = venue?.priceAt(widget.start.hour) ?? 0;
    final booked = _booked;

    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              if (booked == null) SxBackBar(title: 'Book a court', onBack: () => context.pop()),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s24),
                  children: [
                    if (booked != null) ...[
                      const SizedBox(height: Sx.s48),
                      const StateMark(SxState.registered, word: 'CONFIRMED', size: 14),
                      const SizedBox(height: Sx.s16),
                      Text('COURT\nBOOKED', style: SxType.hero(64, c.ink)),
                      const SizedBox(height: Sx.s24),
                      Text('SHOW THIS AT THE DESK', style: SxType.label(c.inkMuted)),
                      const SizedBox(height: Sx.s8),
                      Text(booked.code, key: const Key('bookingCode'), style: SxType.number(40, c.ink, weight: FontWeight.w800)),
                      const SizedBox(height: Sx.s24),
                    ] else
                      Text('CONFIRM', style: SxType.title(c.ink, size: 32)),
                    const SizedBox(height: Sx.s16),
                    SxRows(
                      children: [
                        SxRow(label: 'Venue', value: venue?.name ?? ''),
                        SxRow(label: 'Date', value: dayDate(widget.start)),
                        SxRow(label: 'Time', value: '${timeShort(widget.start)} – ${timeShort(widget.start.add(const Duration(hours: 1)))}'),
                        SxRow(label: 'Court', value: 'Court ${widget.court}'),
                        SxRow(label: 'Court fee', value: formatInr(price)),
                        SxRow(label: 'Booking fee', value: formatInr(bookingFee)),
                      ],
                    ),
                    Divider(height: 1, color: c.line),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Sx.s16),
                      child: Row(
                        children: [
                          Expanded(child: Text(booked == null ? 'Total' : 'Paid', style: SxType.heading(c.ink))),
                          Text(formatInr(price + bookingFee), style: SxType.heading(c.ink, size: 20)),
                        ],
                      ),
                    ),
                    if (booked == null)
                      Text('Free cancellation up to 6 hours before.', style: SxType.caption(c.inkMuted)),
                    if (_error != null) ...[
                      const SizedBox(height: Sx.s16),
                      Text(_error!, style: SxType.body(c.live, size: 14)),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s16),
                child: booked == null
                    ? SxButton(
                        key: const Key('confirmAndPay'),
                        label: 'Confirm & pay ${formatInr(price + bookingFee)}',
                        busy: _busy,
                        onPressed: venue == null ? null : _confirm,
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: SxButton.secondary(
                              key: const Key('toMyBookings'),
                              label: 'My bookings',
                              onPressed: () => context.go('/player/bookings'),
                            ),
                          ),
                          const SizedBox(width: Sx.s12),
                          Expanded(child: SxButton(label: 'Done', onPressed: () => context.go('/player/home'))),
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

class MyBookingsPage extends ConsumerWidget {
  const MyBookingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final bookings = ref.watch(myBookingsProvider);
    final now = DateTime.now();
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(onBack: () => context.canPop() ? context.pop() : context.go('/player/profile')),
              const SxTitleBar(title: 'My bookings'),
              Expanded(
                child: switch (bookings) {
                  AsyncData(:final value) when value.isEmpty => ListView(
                      padding: const EdgeInsets.symmetric(horizontal: Sx.gutter),
                      children: [
                        EmptyBlock(
                          icon: Icons.calendar_month_outlined,
                          title: 'No bookings yet',
                          message: 'Book a court and it will show up here with its desk code.',
                          action: SxButton(label: 'Book a court', expand: false, onPressed: () => context.go('/player/explore?view=courts')),
                        ),
                      ],
                    ),
                  AsyncData(:final value) => ListView(
                      padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48),
                      children: [
                        for (final (i, b) in value.indexed) ...[
                          if (i > 0) Divider(height: 1, color: c.line),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: Sx.s16),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 56,
                                  child: Column(
                                    children: [
                                      Text('${b.start.day}', style: SxType.hero(32, b.start.isBefore(now) ? c.inkMuted : c.ink)),
                                      Text(monthsShort[b.start.month - 1].toUpperCase(), style: SxType.label(c.inkMuted, size: 11)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: Sx.s12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(b.venue.name, style: SxType.heading(c.ink, size: 16)),
                                      Text('Court ${b.court} · ${timeShort(b.start)} · ${b.code}', style: SxType.caption(c.inkMuted)),
                                    ],
                                  ),
                                ),
                                StateMark(
                                  b.status == BookingStatus.cancelled
                                      ? SxState.cancelled
                                      : b.start.isBefore(now)
                                          ? SxState.completed
                                          : SxState.upcoming,
                                  word: b.start.isBefore(now) ? 'PLAYED' : 'BOOKED',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  AsyncError() => ErrorBlock(message: 'Did not load.', onRetry: () => ref.invalidate(myBookingsProvider)),
                  _ => const Padding(padding: EdgeInsets.all(Sx.gutter), child: SkeletonList()),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
