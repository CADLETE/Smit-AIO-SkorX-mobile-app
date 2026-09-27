import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../tournaments/data/tournaments.dart' show PlaceFilter, PlaceOption;

/// An active filter, shown under the search box: tap × to drop it.
class RemovableChip extends StatelessWidget {
  const RemovableChip({super.key, required this.label, required this.onRemove, this.icon});

  final String label;
  final VoidCallback onRemove;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Semantics(
      button: true,
      label: 'Remove filter $label',
      excludeSemantics: true,
      child: Tappable(
        key: Key('remove-$label'),
        onTap: onRemove,
        radius: 18,
        child: Container(
          height: 32,
          padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
          decoration: BoxDecoration(
            color: c.voltFill.withValues(alpha: c.isDark ? 0.16 : 0.32),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.voltFill.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 14, color: c.ink), const SizedBox(width: 4)],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: SxType.sans, fontSize: 12.5, fontWeight: FontWeight.w700, color: c.ink)),
              ),
              const SizedBox(width: 2),
              Icon(Icons.close_rounded, size: 16, color: c.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A horizontal row of [RemovableChip]s, with "Clear all" at the end.
class ActiveFilters extends StatelessWidget {
  const ActiveFilters({super.key, required this.chips, required this.onClear});

  final List<Widget> chips;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();
    final c = context.sx;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Sx.gutter),
        children: [
          for (final chip in chips) Padding(padding: const EdgeInsets.only(right: Sx.s8, top: 4, bottom: 4), child: chip),
          if (chips.length > 1)
            Center(
              child: Tappable(
                key: const Key('clearFilters'),
                onTap: onClear,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sx.s8, vertical: Sx.s8),
                  child: Text('Clear all', style: SxType.caption(c.isDark ? c.cyan : c.blue).copyWith(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One group in a filter sheet: a title and its chips.
class FilterGroup extends StatelessWidget {
  const FilterGroup({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Sx.s24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [SxSection(title), Wrap(spacing: Sx.s8, runSpacing: Sx.s8, children: children)],
        ),
      );
}

/// Country, then state, then city (and optionally venue), each row appearing
/// once the one above is picked. The options come from the data, so a new
/// city appears as soon as something is played there.
class PlacePicker extends StatelessWidget {
  const PlacePicker({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.venues = const [],
    this.venue,
    this.onVenue,
  });

  final List<PlaceOption> options;
  final PlaceFilter value;
  final ValueChanged<PlaceFilter> onChanged;

  /// Venues in the picked city.
  final List<String> venues;
  final String? venue;
  final ValueChanged<String?>? onVenue;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final country = options.where((o) => o.country == value.country).firstOrNull;
    // A country without states (Singapore) lists its cities straight away.
    final regions = country?.regions.keys.toList() ?? const <String>[];
    final flat = regions.length == 1 && country!.regions[regions.first]!.length <= 1;
    final cities = value.region != null ? country?.regions[value.region] ?? const <String>[] : const <String>[];

    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: Sx.s12, bottom: Sx.s8),
          child: Text(text, style: SxType.label(c.inkMuted, size: 11.5)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Sx.s8,
          runSpacing: Sx.s8,
          children: [
            SxChip(key: const Key('place-anywhere'), label: 'Anywhere', selected: value.isAny, onTap: () => onChanged(const PlaceFilter())),
            for (final o in options)
              SxChip(
                key: Key('place-${o.country}'),
                label: o.country,
                selected: value.country == o.country,
                onTap: () => onChanged(PlaceFilter(country: o.country)),
              ),
          ],
        ),
        if (country != null && !flat) ...[
          label('STATE'),
          Wrap(
            spacing: Sx.s8,
            runSpacing: Sx.s8,
            children: [
              SxChip(
                label: 'All of ${country.country}',
                selected: value.region == null,
                onTap: () => onChanged(PlaceFilter(country: country.country)),
              ),
              for (final r in regions)
                SxChip(
                  key: Key('place-$r'),
                  label: r,
                  selected: value.region == r,
                  onTap: () => onChanged(PlaceFilter(country: country.country, region: r)),
                ),
            ],
          ),
        ],
        if (cities.length > 1 || (cities.length == 1 && cities.first != value.region)) ...[
          label('CITY'),
          Wrap(
            spacing: Sx.s8,
            runSpacing: Sx.s8,
            children: [
              SxChip(
                label: 'All of ${value.region}',
                selected: value.city == null,
                onTap: () => onChanged(PlaceFilter(country: value.country, region: value.region)),
              ),
              for (final city in cities)
                SxChip(
                  key: Key('place-$city'),
                  label: city,
                  selected: value.city == city,
                  onTap: () => onChanged(PlaceFilter(country: value.country, region: value.region, city: city)),
                ),
            ],
          ),
        ],
        if (onVenue != null && venues.isNotEmpty && (value.city != null || flat)) ...[
          label('VENUE'),
          Wrap(
            spacing: Sx.s8,
            runSpacing: Sx.s8,
            children: [
              SxChip(label: 'Any venue', selected: venue == null, onTap: () => onVenue!(null)),
              for (final v in venues) SxChip(key: Key('venue-$v'), label: v, selected: venue == v, onTap: () => onVenue!(v)),
            ],
          ),
        ],
      ],
    );
  }
}

Set<T> toggled<T>(Set<T> set, T value) => set.contains(value) ? ({...set}..remove(value)) : {...set, value};
