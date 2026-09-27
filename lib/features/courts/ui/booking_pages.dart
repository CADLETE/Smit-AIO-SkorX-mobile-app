import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../../explore/explore_page.dart' show DateStrip;
import '../data/courts.dart';
import 'venue_art.dart';

/// A venue, built to book fast: the day, a time, and a court already picked
/// on the court map, then one button. Everything else about the venue sits
/// below the booking, for whoever wants it.
class VenuePage extends ConsumerStatefulWidget {
  const VenuePage({super.key, required this.venueId, this.initialDate, this.initialHour});

  final String venueId;
  final DateTime? initialDate;
  final int? initialHour;

  @override
  ConsumerState<VenuePage> createState() => _VenuePageState();
}

class _VenuePageState extends ConsumerState<VenuePage> {
  late DateTime _date = () {
    final d = widget.initialDate ?? DateTime.now();
    return DateTime(d.year, d.month, d.day);
  }();
  late int? _hour = widget.initialHour;

  /// The court the player tapped. Until then the first free court is used,
  /// so a time is all it takes.
  int? _court;

  void _back() => context.canPop() ? context.pop() : context.go('/player/explore/courts');

  @override
  Widget build(BuildContext context) {
    final venue = ref.watch(venueProvider(widget.venueId));
    return Scaffold(
      body: switch (venue) {
        AsyncData(:final value) => _body(value),
        AsyncError(:final error) => SafeArea(
            child: Column(
              children: [
                SxBackBar(title: 'Venue', onBack: _back),
                Expanded(
                  child: EmptyBlock(
                    icon: Icons.stadium_outlined,
                    title: 'Not available',
                    message: error is ApiException ? error.message : 'This venue did not load.',
                  ),
                ),
              ],
            ),
          ),
        _ => SafeArea(
            child: Column(
              children: [
                SxBackBar(title: 'Venue', onBack: _back),
                const Padding(padding: EdgeInsets.all(Sx.gutter), child: SkeletonList(rows: 4, rowHeight: 90)),
              ],
            ),
          ),
      },
    );
  }

  Widget _body(Venue v) {
    final c = context.sx;
    final slots = ref.watch(slotsProvider((v.id, _date)));
    final today = DateTime.now();
    final days = [for (var i = 0; i < 7; i++) DateTime(today.year, today.month, today.day + i)];
    final slot = slots.value?.where((s) => s.start.hour == _hour && s.available).firstOrNull;
    final court = slot == null ? null : (_court != null && slot.freeCourts.contains(_court) ? _court : slot.freeCourts.first);
    final top = MediaQuery.paddingOf(context).top;

    return Column(
      children: [
        Expanded(
          child: SxWidth(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _Hero(venue: v, top: top, onBack: _back)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s20, Sx.gutter, Sx.s32),
                  sliver: SliverList.list(
                    children: [
                      _Facts(venue: v),
                      const SizedBox(height: Sx.s24),
                      _StepTitle(n: 1, title: 'Pick a day', done: true),
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
                      _StepTitle(n: 2, title: 'Pick a time', done: slot != null),
                      switch (slots) {
                        AsyncData(:final value) when value.every((s) => !s.available) => _Note(
                            icon: Icons.event_busy_outlined,
                            text: daysBetween(today, _date) == 0 ? 'No more slots today. Try tomorrow.' : 'Fully booked on this day. Try the next one.',
                          ),
                        AsyncData(:final value) => _SlotGrid(
                            slots: value,
                            selectedHour: slot == null ? null : _hour,
                            onSelect: (s) {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _hour = s.start.hour;
                                _court = null;
                              });
                            },
                          ),
                        AsyncError() => ErrorBlock(
                            message: 'Times did not load.',
                            onRetry: () => ref.invalidate(slotsProvider((v.id, _date))),
                          ),
                        _ => const Skeleton(height: 120),
                      },
                      const SizedBox(height: Sx.s24),
                      _StepTitle(n: 3, title: 'Pick a court', done: court != null),
                      if (slot == null)
                        const _Note(icon: Icons.touch_app_outlined, text: 'Pick a time to see which courts are free.')
                      else ...[
                        CourtMap(
                          venue: v,
                          free: slot.freeCourts,
                          selected: court,
                          onSelect: (n) {
                            HapticFeedback.selectionClick();
                            setState(() => _court = n);
                          },
                        ),
                        const SizedBox(height: Sx.s8),
                        Text(
                          '${slot.freeCourts.length} of ${v.courts} courts free at ${timeShort(slot.start)}. We picked Court $court; tap another to switch.',
                          style: SxType.caption(c.inkMuted, size: 12.5),
                        ),
                      ],
                      const SizedBox(height: Sx.section),
                      _About(venue: v),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _BookBar(
          venue: v,
          date: _date,
          slot: slot,
          court: court,
          onBook: slot == null || court == null
              ? null
              : () => context.push('/player/venue/${v.id}/confirm?date=${isoDay(_date)}&hour=${slot.start.hour}&court=$court'),
        ),
      ],
    );
  }
}

/// The banner, with the back button and the venue's name over it.
class _Hero extends StatelessWidget {
  const _Hero({required this.venue, required this.top, required this.onBack});

  final Venue venue;
  final double top;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final v = venue;
    return VenueBanner(
      venue: v,
      height: 250 + top,
      radius: 0,
      child: Stack(
        children: [
          Positioned(
            top: top + Sx.s8,
            left: Sx.s12,
            child: _GlassButton(icon: Icons.arrow_back_rounded, label: 'Back', onTap: onBack),
          ),
          Positioned(
            left: Sx.gutter,
            right: Sx.gutter,
            bottom: Sx.s16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _BannerChip(icon: Icons.star_rounded, label: '${v.rating.toStringAsFixed(1)} · ${v.reviews}', accent: true),
                    const SizedBox(width: 6),
                    _BannerChip(icon: v.indoor ? Icons.roofing_rounded : Icons.wb_sunny_outlined, label: v.indoor ? 'Indoor' : 'Outdoor'),
                  ],
                ),
                const SizedBox(height: Sx.s8),
                Text(v.name.toUpperCase(), style: SxType.title(Colors.white, size: 34)),
                const SizedBox(height: 2),
                Text(
                  '${v.area}, ${v.city} · ${v.distanceKm.toStringAsFixed(1)} km away',
                  style: SxType.body(Colors.white.withValues(alpha: 0.85), size: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Tappable(
          key: const Key('back'),
          onTap: onTap,
          radius: 22,
          child: ClipOval(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                width: 44,
                height: 44,
                color: Colors.black.withValues(alpha: 0.35),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
            ),
          ),
        ),
      );
}

class _BannerChip extends StatelessWidget {
  const _BannerChip({required this.icon, required this.label, this.accent = false});

  final IconData icon;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent ? c.voltFill : Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: accent ? null : Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent ? c.onVolt : Colors.white),
          const SizedBox(width: 4),
          Text(label, style: SxType.caption(accent ? c.onVolt : Colors.white, size: 12).copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Courts, hours and price at a glance.
class _Facts extends StatelessWidget {
  const _Facts({required this.venue});

  final Venue venue;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final v = venue;
    Widget fact(IconData icon, String value, String label) => Expanded(
          child: Column(
            children: [
              Icon(icon, size: 20, color: c.isDark ? c.cyan : c.blue),
              const SizedBox(height: 6),
              FittedBox(child: Text(value, style: SxType.number(20, c.ink, weight: FontWeight.w800))),
              const SizedBox(height: 2),
              Text(label.toUpperCase(), style: SxType.label(c.inkMuted, size: 9.5)),
            ],
          ),
        );
    return SxBlock(
      padding: const EdgeInsets.symmetric(vertical: Sx.s16, horizontal: Sx.s8),
      child: Row(
        children: [
          fact(Icons.grid_view_rounded, '${v.courts}', 'Courts'),
          fact(Icons.schedule_rounded, '${_hour(v.openHour)}–${_hour(v.closeHour)}', 'Open'),
          fact(Icons.currency_rupee_rounded, formatInr(v.pricePerHour).replaceAll('₹', ''), 'From / hour'),
        ],
      ),
    );
  }

  static String _hour(int h) => h == 0 || h == 24 ? '12a' : h < 12 ? '${h}a' : h == 12 ? '12p' : '${h - 12}p';
}

class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.n, required this.title, required this.done});

  final int n;
  final String title;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sx.s12),
      child: Row(
        children: [
          AnimatedContainer(
            duration: Sx.medium,
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: done ? c.brand : null,
              border: done ? null : Border.all(color: c.line, width: 1.5),
            ),
            child: done
                ? Icon(Icons.check_rounded, size: 15, color: c.onVolt)
                : Text('$n', style: SxType.label(c.inkMuted, size: 12, weight: FontWeight.w800)),
          ),
          const SizedBox(width: Sx.s8),
          Semantics(header: true, child: Text(title, style: SxType.heading(c.ink, size: 17).copyWith(fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      padding: const EdgeInsets.all(Sx.s16),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(Sx.radius),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: c.inkMuted),
          const SizedBox(width: Sx.s12),
          Expanded(child: Text(text, style: SxType.body(c.inkMuted, size: 14))),
        ],
      ),
    );
  }
}

/// Times grouped into morning, afternoon and evening, each with its price
/// and how many courts are left.
class _SlotGrid extends StatelessWidget {
  const _SlotGrid({required this.slots, required this.selectedHour, required this.onSelect});

  final List<Slot> slots;
  final int? selectedHour;
  final ValueChanged<Slot> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final parts = [PartOfDay.morning, PartOfDay.afternoon, PartOfDay.evening];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in parts)
          if (slots.any((s) => p.contains(s.start))) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: Sx.s8, top: 2),
              child: Row(
                children: [
                  Icon(
                    switch (p) {
                      PartOfDay.morning => Icons.wb_twilight_rounded,
                      PartOfDay.afternoon => Icons.wb_sunny_outlined,
                      _ => Icons.nights_stay_outlined,
                    },
                    size: 15,
                    color: c.inkMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(p.label.toUpperCase(), style: SxType.label(c.inkMuted, size: 11)),
                ],
              ),
            ),
            Wrap(
              spacing: Sx.s8,
              runSpacing: Sx.s8,
              children: [
                for (final s in slots.where((s) => p.contains(s.start)))
                  _SlotChip(slot: s, selected: s.start.hour == selectedHour, onTap: () => onSelect(s)),
              ],
            ),
            const SizedBox(height: Sx.s12),
          ],
      ],
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({required this.slot, required this.selected, required this.onTap});

  final Slot slot;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final s = slot;
    final enabled = s.available;
    final left = s.freeCourts.length;
    final fg = selected ? c.onVolt : (enabled ? c.ink : c.inkFaint);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: '${timeShort(s.start)}, ${enabled ? '$left courts free' : 'full'}',
      excludeSemantics: true,
      child: Tappable(
        onTap: enabled ? onTap : null,
        radius: Sx.radiusSm,
        child: AnimatedContainer(
          duration: Sx.fast,
          width: 80,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: selected ? c.brand : null,
            color: selected ? null : (enabled ? c.surface : c.surfaceAlt.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(Sx.radiusSm),
            border: Border.all(color: selected ? Colors.transparent : (enabled ? c.cardEdge : c.line.withValues(alpha: 0.5))),
            boxShadow: selected ? c.glowOf(c.voltFill, strength: 0.6) : null,
          ),
          child: Column(
            children: [
              Text(
                timeShort(s.start),
                style: SxType.number(17, fg, weight: FontWeight.w800).copyWith(decoration: enabled ? null : TextDecoration.lineThrough),
              ),
              const SizedBox(height: 3),
              Text(
                enabled ? formatInr(s.price) : 'Full',
                style: SxType.caption(selected ? c.onVolt.withValues(alpha: 0.8) : c.inkMuted, size: 11),
              ),
              if (enabled && left <= 2) ...[
                const SizedBox(height: 2),
                Text(
                  '$left left',
                  style: SxType.label(selected ? c.onVolt : c.caution, size: 9.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Facilities, prices, location and rules, below the booking.
class _About extends StatelessWidget {
  const _About({required this.venue});

  final Venue venue;

  static IconData _facilityIcon(String f) => switch (f.toLowerCase()) {
        'parking' => Icons.local_parking_rounded,
        'changing rooms' => Icons.checkroom_rounded,
        'showers' => Icons.shower_rounded,
        'paddle rental' => Icons.sports_tennis_rounded,
        'café' || 'cafe' => Icons.local_cafe_rounded,
        'floodlights' => Icons.light_mode_rounded,
        'ac' => Icons.ac_unit_rounded,
        'pro shop' => Icons.storefront_rounded,
        'coaching' => Icons.school_rounded,
        'drinking water' => Icons.water_drop_rounded,
        _ => Icons.check_circle_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final v = venue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (v.facilities.isNotEmpty) ...[
          const SxSection('Facilities'),
          Wrap(
            spacing: Sx.s8,
            runSpacing: Sx.s8,
            children: [
              for (final f in v.facilities)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Sx.s12, vertical: 8),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c.cardEdge),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_facilityIcon(f), size: 15, color: c.isDark ? c.cyan : c.blue),
                      const SizedBox(width: 6),
                      Text(f, style: SxType.caption(c.ink, size: 13).copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: Sx.section),
        ],
        SxRows(
          title: 'Pricing',
          children: [
            SxRow(icon: Icons.wb_sunny_outlined, label: 'Off-peak', value: '${formatInr(v.pricePerHour)} / hour'),
            SxRow(icon: Icons.local_fire_department_outlined, label: 'Peak · 6–10 PM', value: '${formatInr(v.peakPricePerHour)} / hour'),
            SxRow(icon: Icons.layers_outlined, label: 'Surface', value: v.surface),
          ],
        ),
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
          const SxSection('Good to know'),
          for (final r in v.rules)
            Padding(
              padding: const EdgeInsets.only(bottom: Sx.s8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Icon(Icons.info_outline_rounded, size: 15, color: c.inkMuted),
                  ),
                  const SizedBox(width: Sx.s8),
                  Expanded(child: Text(r, style: SxType.body(c.ink, size: 14))),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// Always on screen: what is picked and the one button to book it.
class _BookBar extends StatelessWidget {
  const _BookBar({required this.venue, required this.date, required this.slot, required this.court, required this.onBook});

  final Venue venue;
  final DateTime date;
  final Slot? slot;
  final int? court;
  final VoidCallback? onBook;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final s = slot;
    final ready = s != null && court != null;
    return Container(
      padding: EdgeInsets.fromLTRB(Sx.gutter, Sx.s12, Sx.gutter, Sx.s12 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.cardEdge)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: c.isDark ? 0.4 : 0.08), blurRadius: 20, offset: const Offset(0, -6))],
      ),
      child: SxWidth(
        child: Row(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: Sx.medium,
                child: ready
                    ? Column(
                        key: ValueKey('${s.start}-$court'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Court $court · ${timeShort(s.start)}', style: SxType.heading(c.ink, size: 16).copyWith(fontWeight: FontWeight.w800)),
                          Text('${relativeDay(date, DateTime.now())} · 1 hour', style: SxType.caption(c.inkMuted, size: 12.5)),
                        ],
                      )
                    : Text(
                        key: const ValueKey('none'),
                        'From ${formatInr(venue.pricePerHour)} / hour',
                        style: SxType.heading(c.ink, size: 16),
                      ),
              ),
            ),
            const SizedBox(width: Sx.s12),
            SxButton(
              key: const Key('continueBooking'),
              label: ready ? 'Book · ${formatInr(s.price + bookingFee)}' : 'Pick a time',
              icon: ready ? Icons.bolt_rounded : null,
              expand: false,
              onPressed: onBook,
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirm and pay, then the booking code.
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
      HapticFeedback.heavyImpact();
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
    final end = widget.start.add(const Duration(hours: 1));

    final ticket = Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Sx.radiusLg),
        border: Border.all(color: booked != null ? c.voltFill.withValues(alpha: 0.6) : c.cardEdge),
        boxShadow: booked != null ? c.glowOf(c.voltFill, strength: 0.6) : c.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (venue != null)
            VenueBanner(
              venue: venue,
              height: 120,
              radius: 0,
              child: Positioned(
                left: Sx.s16,
                bottom: Sx.s12,
                right: Sx.s16,
                child: Text(venue.name.toUpperCase(), style: SxType.title(Colors.white, size: 24)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(Sx.s16),
            child: Row(
              children: [
                Expanded(child: _TicketField(label: 'Date', value: dayDate(widget.start))),
                Expanded(child: _TicketField(label: 'Time', value: '${timeShort(widget.start)}–${timeShort(end)}')),
                _TicketField(label: 'Court', value: '${widget.court}', big: true),
              ],
            ),
          ),
          // The tear line.
          Row(
            children: [
              _Notch(color: c.canvas, left: true),
              Expanded(
                child: LayoutBuilder(
                  builder: (_, box) => Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var i = 0; i < (box.maxWidth / 10).floor(); i++)
                        Container(width: 5, height: 1.5, color: c.line),
                    ],
                  ),
                ),
              ),
              _Notch(color: c.canvas, left: false),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(Sx.s16),
            child: booked != null
                ? Column(
                    children: [
                      Text('SHOW THIS AT THE DESK', style: SxType.label(c.inkMuted)),
                      const SizedBox(height: Sx.s8),
                      SxPop(
                        child: Text(booked.code,
                            key: const Key('bookingCode'), style: SxType.number(40, c.ink, weight: FontWeight.w800)),
                      ),
                      const SizedBox(height: Sx.s8),
                      Text('Paid ${formatInr(price + bookingFee)}', style: SxType.caption(c.inkMuted)),
                    ],
                  )
                : Column(
                    children: [
                      _PriceRow(label: 'Court fee', value: formatInr(price)),
                      _PriceRow(label: 'Booking fee', value: formatInr(bookingFee)),
                      const SizedBox(height: 6),
                      _PriceRow(label: 'Total', value: formatInr(price + bookingFee), strong: true),
                    ],
                  ),
          ),
        ],
      ),
    );

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
                      const SizedBox(height: Sx.s24),
                      Center(
                        child: SxPop(
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(shape: BoxShape.circle, gradient: c.brand, boxShadow: c.glowOf(c.voltFill)),
                            child: Icon(Icons.check_rounded, size: 40, color: c.onVolt),
                          ),
                        ),
                      ),
                      const SizedBox(height: Sx.s16),
                      Center(child: Text('COURT BOOKED', style: SxType.title(c.ink, size: 34))),
                      const SizedBox(height: 4),
                      Center(
                        child: Text('See you on court ${widget.court}. It is in My bookings too.',
                            textAlign: TextAlign.center, style: SxType.body(c.inkMuted, size: 14)),
                      ),
                      const SizedBox(height: Sx.s24),
                    ] else ...[
                      Text('CONFIRM', style: SxType.title(c.ink, size: 32)),
                      const SizedBox(height: Sx.s16),
                    ],
                    ticket,
                    if (booked == null) ...[
                      const SizedBox(height: Sx.s16),
                      Row(
                        children: [
                          Icon(Icons.verified_user_outlined, size: 16, color: c.inkMuted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text('Free cancellation up to 6 hours before.', style: SxType.caption(c.inkMuted)),
                          ),
                        ],
                      ),
                    ],
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

class _TicketField extends StatelessWidget {
  const _TicketField({required this.label, required this.value, this.big = false});

  final String label;
  final String value;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Column(
      crossAxisAlignment: big ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: SxType.label(c.inkMuted, size: 10)),
        const SizedBox(height: 4),
        Text(value, style: big ? SxType.number(30, c.ink, weight: FontWeight.w800) : SxType.heading(c.ink, size: 15)),
      ],
    );
  }
}

class _Notch extends StatelessWidget {
  const _Notch({required this.color, required this.left});

  final Color color;
  final bool left;

  @override
  Widget build(BuildContext context) => Transform.translate(
        offset: Offset(left ? -10 : 10, 0),
        child: Container(width: 20, height: 20, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      );
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.label, required this.value, this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: strong ? SxType.heading(c.ink) : SxType.body(c.inkMuted, size: 14))),
          Text(value, style: strong ? SxType.heading(c.ink, size: 20) : SxType.body(c.ink, size: 14)),
        ],
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
                          action: SxButton(label: 'Book a court', expand: false, onPressed: () => context.go('/player/explore/courts')),
                        ),
                      ],
                    ),
                  AsyncData(:final value) => ListView(
                      padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48),
                      children: [
                        for (final b in value)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Sx.s12),
                            child: SxBlock(
                              padding: EdgeInsets.zero,
                              onTap: () => context.push('/player/venue/${b.venue.id}'),
                              semanticLabel: '${b.venue.name}, court ${b.court}, ${dayDate(b.start)} ${timeShort(b.start)}, ${b.code}',
                              child: Row(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(Sx.s8),
                                    child: SizedBox(
                                      width: 76,
                                      height: 76,
                                      child: VenueBanner(venue: b.venue, height: 76, radius: Sx.radiusSm),
                                    ),
                                  ),
                                  const SizedBox(width: Sx.s12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(b.venue.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 16)),
                                        const SizedBox(height: 2),
                                        Text('${dayDate(b.start)} · ${timeShort(b.start)}', style: SxType.caption(c.inkMuted)),
                                        Text('Court ${b.court} · ${b.code}', style: SxType.caption(c.inkMuted)),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(right: Sx.s12),
                                    child: StateMark(
                                      b.status == BookingStatus.cancelled
                                          ? SxState.cancelled
                                          : b.start.isBefore(now)
                                              ? SxState.completed
                                              : SxState.upcoming,
                                      word: b.start.isBefore(now) ? 'PLAYED' : 'BOOKED',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
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
