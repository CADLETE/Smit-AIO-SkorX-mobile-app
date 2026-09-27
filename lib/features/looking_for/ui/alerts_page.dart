import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/design.dart';
import '../data/looking_for.dart';
import '../looking_for_controller.dart';
import 'lf_widgets.dart';

/// My Looking For alerts: how, what and how far. SkorX only alerts when a
/// request fits, and never more than a few times a day (docs/LOOKING-FOR.md §8).
class LookingForAlertsPage extends ConsumerWidget {
  const LookingForAlertsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(lfAlertsProvider);
    final categories = ref.watch(lfCategoriesProvider);
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              const SxBackBar(title: 'Looking For alerts'),
              Expanded(
                child: switch ((alerts, categories)) {
                  (AsyncData(value: final a), AsyncData(value: final cats)) => _Form(initial: a, categories: cats),
                  (AsyncError(), _) || (_, AsyncError()) => ErrorBlock(
                      message: 'Could not load your alert settings.',
                      onRetry: () => ref
                        ..invalidate(lfAlertsProvider)
                        ..invalidate(lfCategoriesProvider),
                    ),
                  _ => const Center(child: BallLoader()),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.initial, required this.categories});

  final LfAlerts initial;
  final List<LfCategory> categories;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late LfAlerts _a = widget.initial;
  late final _city = TextEditingController(text: widget.initial.city ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _city.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final city = _city.text.trim();
      await ref.read(lfActionsProvider).saveAlerts(_a.copyWith(city: city.isEmpty ? null : city));
      if (mounted) {
        lfNote(context, 'Alerts saved');
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) lfError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _label(String t, [String? hint]) {
    final c = context.sx;
    return Padding(
      padding: const EdgeInsets.only(top: Sx.s24, bottom: Sx.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.toUpperCase(), style: SxType.label(c.inkMuted)),
          if (hint != null) ...[const SizedBox(height: 2), Text(hint, style: SxType.caption(c.inkMuted, size: 12.5))],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    final off = _a.mode == LfAlertMode.off;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s32),
      children: [
        Text(
          _a.isDefault
              ? 'These are the settings SkorX uses for you until you change them.'
              : 'SkorX alerts you only when a request fits your settings and profile.',
          style: SxType.body(c.inkMuted),
        ),
        _label('How'),
        SxRows(children: [
          for (final m in LfAlertMode.values)
            SxRow(
              key: Key('lfMode-${m.api}'),
              label: m.label,
              subtitle: m.detail,
              trailing: Icon(
                _a.mode == m ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: _a.mode == m ? c.volt : c.inkFaint,
              ),
              onTap: () => setState(() => _a = _a.copyWith(mode: m)),
            ),
        ]),
        AnimatedOpacity(
          duration: Sx.fast,
          opacity: off ? 0.4 : 1,
          child: IgnorePointer(
            ignoring: off,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('What', 'Requests you want to hear about'),
                LfChoiceRow<String>(
                  keyPrefix: 'lfAlertCat',
                  options: [for (final cat in widget.categories) (cat.id, cat.label)],
                  isSelected: _a.categories.contains,
                  onTap: (id) => setState(() {
                    final next = {..._a.categories};
                    next.contains(id) ? next.remove(id) : next.add(id);
                    _a = _a.copyWith(categories: next);
                  }),
                ),
                _label('Where'),
                TextField(
                  key: const Key('lfAlertCity'),
                  controller: _city,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Your city'),
                ),
                if (_a.knownCities.isNotEmpty) ...[
                  const SizedBox(height: Sx.s8),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final city in _a.knownCities.take(12))
                          Padding(
                            padding: const EdgeInsets.only(right: Sx.s8),
                            child: SxChip(
                              label: city,
                              selected: _city.text.trim().toLowerCase() == city.toLowerCase(),
                              onTap: () => setState(() => _city.text = city),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                _label('Location radius'),
                LfChoiceRow<int?>(
                  keyPrefix: 'lfAlertRadius',
                  options: const [(5, '5 km'), (10, '10 km'), (25, '25 km'), (50, '50 km'), (null, 'Anywhere')],
                  isSelected: (v) => _a.radiusKm == v,
                  onTap: (v) => setState(() => _a = v == null ? _a.copyWith(anywhere: true) : _a.copyWith(radiusKm: v)),
                ),
                _label('I can be found as', 'Referee, scorer and media requests go to people who hold the role.'),
                LfChoiceRow<String>(
                  keyPrefix: 'lfRole',
                  options: [for (final e in lfRoles.entries) (e.key, e.value)],
                  isSelected: _a.roles.contains,
                  onTap: (r) => setState(() {
                    final next = {..._a.roles};
                    next.contains(r) ? next.remove(r) : next.add(r);
                    _a = _a.copyWith(roles: next);
                  }),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Sx.s32),
        SxButton(key: const Key('lfSaveAlerts'), label: 'Save', busy: _busy, onPressed: _save),
      ],
    );
  }
}
