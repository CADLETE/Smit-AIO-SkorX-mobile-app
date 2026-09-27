import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/design.dart';
import '../../../shared/format.dart';
import '../data/looking_for.dart';
import '../looking_for_controller.dart';
import 'lf_widgets.dart';

/// Post a Looking For in seconds: what → how many, when, where → post.
/// Or type it as a sentence and review what SkorX understood.
class CreateLookingForPage extends ConsumerStatefulWidget {
  const CreateLookingForPage({super.key, this.initialCategory});

  final String? initialCategory;

  @override
  ConsumerState<CreateLookingForPage> createState() => _CreateLookingForPageState();
}

enum _Step { what, details, review, done }

class _CreateLookingForPageState extends ConsumerState<CreateLookingForPage> {
  _Step _step = _Step.what;
  LfDraft? _draft;
  bool _titleEdited = false;
  bool _more = false;
  bool _busy = false;
  (LfPost, LfMatching)? _result;
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _place = TextEditingController();
  final _city = TextEditingController();
  final _amount = TextEditingController();
  final _sentence = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final cats = await ref.read(lfCategoriesProvider.future);
        final cat = lfCategoryOf(cats, widget.initialCategory!);
        if (cat != null && mounted) _pick(cat);
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _place, _city, _amount, _sentence]) {
      c.dispose();
    }
    super.dispose();
  }

  LfCategory? get _category => lfCategoryOf(ref.read(lfCategoriesProvider).value, _draft?.categoryId ?? '');

  String _defaultCity() => ref.read(lfAlertsProvider).value?.city ?? 'Ahmedabad';

  void _pick(LfCategory cat, {LfParsed? parsed}) {
    final now = DateTime.now();
    final form = cat.form;
    final draft = LfDraft(
      categoryId: cat.id,
      subcategoryId: parsed?.subcategoryId ?? (cat.subcategories.isEmpty ? null : cat.subcategories.first.id),
      quantity: parsed?.quantity ?? (form.has('quantity') ? (cat.id == 'player' ? 2 : 1) : 1),
      paymentType: LfPaymentType.parse(parsed?.paymentType ?? form.payment),
      paymentAmount: parsed?.paymentAmount,
      paymentUnit: form.payment == 'paid' ? 'per_day' : 'per_person',
      skillLevels: {...?parsed?.skillLevels},
      gender: parsed?.gender ?? 'any',
    );
    if (form.has('when')) {
      draft.startsAt = parsed?.startsAt ??
          (parsed?.date != null ? DateTime(parsed!.date!.year, parsed.date!.month, parsed.date!.day, 18) : _nextSlot(now));
      draft.endsAt = parsed?.endsAt;
      if (draft.endsAt == null && (cat.id == 'player' || cat.id == 'match')) draft.durationMins = 90;
    }
    if (parsed?.matchType != null && form.details.any((d) => d.key == 'matchType')) draft.details['matchType'] = parsed!.matchType;
    _city.text = parsed?.city ?? _defaultCity();
    _place.text = parsed?.placeName ?? '';
    _description.text = parsed?.description ?? '';
    _amount.text = draft.paymentAmount?.toString() ?? '';
    _titleEdited = false;
    setState(() {
      _draft = draft;
      _step = _Step.details;
      _more = false;
    });
    _suggestTitle();
  }

  static DateTime _nextSlot(DateTime now) {
    final evening = DateTime(now.year, now.month, now.day, 19);
    if (evening.isAfter(now.add(const Duration(hours: 1)))) return evening;
    final t = now.add(const Duration(days: 1));
    return DateTime(t.year, t.month, t.day, 19);
  }

  /// "2 Players needed · Today 7 PM" until the person writes their own.
  void _suggestTitle() {
    final d = _draft;
    final cat = _category;
    if (d == null || cat == null || _titleEdited) return;
    final sub = cat.subcategories.where((s) => s.id == d.subcategoryId).firstOrNull?.label;
    final noun = sub == null || sub.startsWith('A ') ? cat.label : sub;
    final plural = d.quantity > 1 && cat.form.has('quantity');
    final what = switch (d.subcategoryId) {
      'team.join' => 'Looking for a team to join',
      'tournament.to_play' => 'Looking for a tournament to play',
      'club.join' => 'Looking for a club to join',
      'match.match' => 'Looking for a match',
      _ => plural ? '${d.quantity} ${noun.endsWith('s') ? noun : '${noun}s'} needed' : '${noun.endsWith('s') && !noun.endsWith('ss') ? noun.substring(0, noun.length - 1) : noun} needed',
    };
    final when = d.startsAt == null ? '' : ' · ${relativeDay(d.startsAt!, DateTime.now())}';
    _title.text = '$what$when';
  }

  Future<void> _parse() async {
    final text = _sentence.text.trim();
    if (text.length < 4) return;
    setState(() => _busy = true);
    try {
      final parsed = await ref.read(lfActionsProvider).parse(text);
      final cats = await ref.read(lfCategoriesProvider.future);
      final cat = lfCategoryOf(cats, parsed.categoryId ?? 'other') ?? cats.last;
      if (!mounted) return;
      _pick(cat, parsed: parsed);
      if (parsed.title != null) {
        _title.text = parsed.title!;
        _titleEdited = true;
      }
      setState(() => _step = _Step.review);
    } catch (e) {
      if (mounted) lfError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _problem() {
    final d = _draft!;
    final form = _category!.form;
    if (_title.text.trim().length < 3) return 'Give it a short title.';
    if (_city.text.trim().length < 2) return 'Add the city.';
    if (form.needs('when') && d.startsAt == null) return 'Pick a date and time.';
    if (d.startsAt != null && d.startsAt!.isBefore(DateTime.now().subtract(const Duration(minutes: 30)))) {
      return 'That time has already passed.';
    }
    if (d.endsAt != null && d.startsAt != null && !d.endsAt!.isAfter(d.startsAt!)) return 'The end time must be after the start.';
    return null;
  }

  void _toReview() {
    _sync();
    final problem = _problem();
    if (problem != null) return lfNote(context, problem);
    setState(() => _step = _Step.review);
  }

  void _sync() {
    final d = _draft!;
    d
      ..title = _title.text
      ..description = _description.text
      ..placeName = _place.text
      ..city = _city.text
      ..paymentAmount = int.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9]'), ''));
  }

  Future<void> _post() async {
    _sync();
    final problem = _problem();
    if (problem != null) return lfNote(context, problem);
    setState(() => _busy = true);
    try {
      final result = await ref.read(lfActionsProvider).create(_draft!.toJson(_category!.form));
      if (!mounted) return;
      setState(() {
        _result = result;
        _step = _Step.done;
      });
    } catch (e) {
      if (mounted) lfError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() {
    switch (_step) {
      case _Step.details:
        setState(() => _step = _Step.what);
      case _Step.review:
        setState(() => _step = _Step.details);
      case _Step.what:
      case _Step.done:
        context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == _Step.what || _step == _Step.done,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: SxWidth(
            child: Column(
              children: [
                SxBackBar(
                  title: switch (_step) {
                    _Step.what => 'Post Looking For',
                    _Step.details => _category?.label ?? 'Details',
                    _Step.review => 'Review',
                    _Step.done => 'Posted',
                  },
                  onBack: _back,
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: Sx.medium,
                    child: switch (_step) {
                      _Step.what => _whatStep(),
                      _Step.details => _detailsStep(),
                      _Step.review => _reviewStep(),
                      _Step.done => _doneStep(),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------

  Widget _whatStep() {
    final c = context.sx;
    final cats = ref.watch(lfCategoriesProvider);
    return ListView(
      key: const ValueKey('what'),
      padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s32),
      children: [
        Text('What are you looking for?', style: SxType.title(c.ink, size: 28)),
        const SizedBox(height: Sx.s16),
        TextField(
          key: const Key('lfSentence'),
          controller: _sentence,
          minLines: 1,
          maxLines: 3,
          maxLength: 300,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _parse(),
          decoration: InputDecoration(
            hintText: 'Or type it: "Need 2 intermediate players at XYZ Club tonight at 8 PM"',
            suffixIcon: _busy
                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : IconButton(key: const Key('lfParse'), tooltip: 'Read it', icon: const Icon(Icons.auto_awesome_rounded), onPressed: _parse),
          ),
        ),
        const SizedBox(height: Sx.s8),
        cats.when(
          loading: () => const SkeletonList(rows: 3, rowHeight: 96),
          error: (e, _) => ErrorBlock(message: 'Could not load categories.', onRetry: () => ref.invalidate(lfCategoriesProvider)),
          data: (list) => GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width > 520 ? 3 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: Sx.s12,
            crossAxisSpacing: Sx.s12,
            childAspectRatio: 1.45,
            children: [
              for (final cat in list)
                Semantics(
                  button: true,
                  label: '${cat.label}: ${cat.tagline}',
                  excludeSemantics: true,
                  child: Tappable(
                    key: Key('lfPick-${cat.id}'),
                    haptic: true,
                    onTap: () => _pick(cat),
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          SxIconTile(icon: lfIcon(cat.icon), size: 34, colors: lfColors(c, cat.id)),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(cat.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.heading(c.ink, size: 15)),
                              Text(cat.tagline, maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.caption(c.inkMuted, size: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------

  Widget _label(String text) {
    final c = context.sx;
    return Padding(
      padding: const EdgeInsets.only(top: Sx.s20, bottom: Sx.s8),
      child: Text(text.toUpperCase(), style: SxType.label(c.inkMuted)),
    );
  }

  Widget _detailsStep() {
    final c = context.sx;
    final d = _draft!;
    final cat = _category!;
    final form = cat.form;
    final cities = ref.watch(lfAlertsProvider).value?.knownCities ?? const <String>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = d.startsAt == null ? null : DateTime(d.startsAt!.year, d.startsAt!.month, d.startsAt!.day);

    void setDay(DateTime day) => setState(() {
          final t = d.startsAt ?? _nextSlot(now);
          d.startsAt = DateTime(day.year, day.month, day.day, t.hour, t.minute);
          if (d.endsAt != null) d.endsAt = DateTime(day.year, day.month, day.day, d.endsAt!.hour, d.endsAt!.minute);
          _suggestTitle();
        });

    return ListView(
      key: const ValueKey('details'),
      padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s32),
      children: [
        if (cat.subcategories.length > 1) ...[
          _label('Looking for'),
          LfChoiceRow<String>(
            keyPrefix: 'lfSub',
            options: [for (final s in cat.subcategories) (s.id, s.label)],
            isSelected: (v) => d.subcategoryId == v,
            onTap: (v) => setState(() {
              d.subcategoryId = v;
              _suggestTitle();
            }),
          ),
        ],
        if (form.has('quantity')) ...[
          _label(form.quantityLabel ?? 'How many'),
          Row(
            children: [
              for (final n in [1, 2, 3, 4])
                Padding(
                  padding: const EdgeInsets.only(right: Sx.s8),
                  child: SxChip(
                    key: Key('lfQty-$n'),
                    label: '$n',
                    selected: d.quantity == n,
                    onTap: () => setState(() {
                      d.quantity = n;
                      _suggestTitle();
                    }),
                  ),
                ),
              SxChip(
                key: const Key('lfQty-more'),
                label: d.quantity > 4 ? '${d.quantity}' : 'More',
                selected: d.quantity > 4,
                onTap: () => setState(() {
                  d.quantity = d.quantity < 5 ? 5 : (d.quantity >= 50 ? 5 : d.quantity + 1);
                  _suggestTitle();
                }),
              ),
            ],
          ),
        ],
        if (form.has('when')) ...[
          _label(form.needs('when') ? 'When' : 'When (optional)'),
          Wrap(
            spacing: Sx.s8,
            runSpacing: Sx.s8,
            children: [
              SxChip(key: const Key('lfDay-today'), label: 'Today', selected: day == today, onTap: () => setDay(today)),
              SxChip(
                key: const Key('lfDay-tomorrow'),
                label: 'Tomorrow',
                selected: day == today.add(const Duration(days: 1)),
                onTap: () => setDay(today.add(const Duration(days: 1))),
              ),
              SxChip(
                key: const Key('lfDay-pick'),
                icon: Icons.calendar_today_rounded,
                label: day != null && day.isAfter(today.add(const Duration(days: 1))) ? dayDate(day) : 'Pick a date',
                selected: day != null && day.isAfter(today.add(const Duration(days: 1))),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: today,
                    lastDate: today.add(const Duration(days: 60)),
                    initialDate: day ?? today,
                  );
                  if (picked != null) setDay(picked);
                },
              ),
            ],
          ),
          if (d.startsAt != null) ...[
            const SizedBox(height: Sx.s8),
            Row(
              children: [
                Expanded(
                  child: _TimeButton(
                    key: const Key('lfStart'),
                    label: 'Starts',
                    value: timeShort(d.startsAt!),
                    onTap: () async {
                      final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(d.startsAt!));
                      if (t != null) setState(() => d.startsAt = DateTime(d.startsAt!.year, d.startsAt!.month, d.startsAt!.day, t.hour, t.minute));
                    },
                  ),
                ),
                if (form.has('endTime') || form.has('duration') || cat.id == 'player' || cat.id == 'match') ...[
                  const SizedBox(width: Sx.s12),
                  Expanded(
                    child: _TimeButton(
                      key: const Key('lfEnd'),
                      label: 'Ends',
                      value: d.endsAt != null
                          ? timeShort(d.endsAt!)
                          : d.durationMins != null
                              ? timeShort(d.startsAt!.add(Duration(minutes: d.durationMins!)))
                              : 'Optional',
                      onTap: () async {
                        final base = d.endsAt ?? d.startsAt!.add(Duration(minutes: d.durationMins ?? 120));
                        final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
                        if (t == null) return;
                        var end = DateTime(d.startsAt!.year, d.startsAt!.month, d.startsAt!.day, t.hour, t.minute);
                        if (!end.isAfter(d.startsAt!)) end = end.add(const Duration(days: 1));
                        setState(() {
                          d.endsAt = end;
                          d.durationMins = null;
                        });
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
        _label('Where'),
        if (form.has('place'))
          TextField(
            key: const Key('lfPlace'),
            controller: _place,
            maxLength: 80,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Club, venue or area', counterText: ''),
          ),
        const SizedBox(height: Sx.s8),
        TextField(
          key: const Key('lfCity'),
          controller: _city,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'City', counterText: ''),
          onChanged: (_) => setState(() {}),
        ),
        if (cities.isNotEmpty) ...[
          const SizedBox(height: Sx.s8),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final city in cities.take(12))
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
        const SizedBox(height: Sx.s16),
        if (!_more)
          SxButton.quiet(
            key: const Key('lfMore'),
            icon: Icons.tune_rounded,
            label: 'More details (level, payment, notes)',
            onPressed: () => setState(() => _more = true),
          )
        else
          ..._moreFields(d, form),
        const SizedBox(height: Sx.s24),
        SxButton(key: const Key('lfReview'), label: 'Review', onPressed: _toReview),
        const SizedBox(height: Sx.s8),
        Text('You can post straight from the review. Nothing is shared until you post.', style: SxType.caption(c.inkMuted, size: 12.5)),
      ],
    );
  }

  List<Widget> _moreFields(LfDraft d, LfForm form) {
    final c = context.sx;
    return [
      if (form.has('skill')) ...[
        _label('Level'),
        LfChoiceRow<String>(
          keyPrefix: 'lfLevel',
          options: [for (final s in lfSkillBands) (s, lfSkillLabels[s]!)],
          isSelected: d.skillLevels.contains,
          onTap: (s) => setState(() => d.skillLevels.contains(s) ? d.skillLevels.remove(s) : d.skillLevels.add(s)),
        ),
        const SizedBox(height: Sx.s4),
        Text(d.skillLevels.isEmpty ? 'Any level' : 'Only these levels', style: SxType.caption(c.inkMuted, size: 12)),
      ],
      if (form.has('gender')) ...[
        _label('Open to'),
        LfChoiceRow<String>(
          keyPrefix: 'lfG',
          options: const [('any', 'Everyone'), ('male', 'Men'), ('female', 'Women')],
          isSelected: (v) => d.gender == v,
          onTap: (v) => setState(() => d.gender = v),
        ),
      ],
      if (form.has('age')) ...[
        _label('Age group'),
        LfChoiceRow<String>(
          keyPrefix: 'lfAge',
          options: [for (final a in lfAgeGroups) (a, a == 'any' ? 'Any' : a == 'junior' ? 'Juniors' : a == 'open' ? 'Open' : a)],
          isSelected: (v) => d.ageGroup == v,
          onTap: (v) => setState(() => d.ageGroup = v),
        ),
      ],
      for (final f in form.details) ...[
        _label(f.label),
        if (f.type == 'choice')
          LfChoiceRow<String>(
            keyPrefix: 'lfD-${f.key}',
            options: [for (final o in f.options) (o, o)],
            isSelected: (v) => d.details[f.key] == v,
            onTap: (v) => setState(() => d.details[f.key] = d.details[f.key] == v ? null : v),
          )
        else
          TextFormField(
            key: Key('lfD-${f.key}'),
            initialValue: d.details[f.key]?.toString() ?? '',
            keyboardType: f.type == 'number' ? TextInputType.number : TextInputType.text,
            maxLength: f.type == 'number' ? 3 : 120,
            decoration: InputDecoration(
              hintText: f.type == 'number' ? '${f.min ?? 1}–${f.max ?? 99}' : null,
              counterText: '',
            ),
            onChanged: (v) => d.details[f.key] = f.type == 'number' ? int.tryParse(v) : v,
          ),
      ],
      if (form.has('payment')) ...[
        _label('Payment'),
        LfChoiceRow<LfPaymentType>(
          keyPrefix: 'lfPay',
          options: const [(LfPaymentType.none, 'None'), (LfPaymentType.paid, 'I pay them'), (LfPaymentType.fee, 'They share the cost')],
          isSelected: (v) => d.paymentType == v,
          onTap: (v) => setState(() {
            d.paymentType = v;
            d.paymentUnit = v == LfPaymentType.paid ? 'per_day' : 'per_person';
          }),
        ),
        if (d.paymentType != LfPaymentType.none) ...[
          const SizedBox(height: Sx.s8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('lfAmount'),
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
                ),
              ),
              const SizedBox(width: Sx.s12),
              DropdownButton<String>(
                value: d.paymentUnit,
                onChanged: (v) => setState(() => d.paymentUnit = v ?? d.paymentUnit),
                items: [for (final e in lfPaymentUnits.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              ),
            ],
          ),
        ],
      ],
      _label('Title'),
      TextField(
        key: const Key('lfTitle'),
        controller: _title,
        maxLength: 80,
        onChanged: (_) => _titleEdited = true,
        textCapitalization: TextCapitalization.sentences,
      ),
      _label('Notes'),
      TextField(
        key: const Key('lfDescription'),
        controller: _description,
        maxLength: 1000,
        minLines: 2,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Anything people should know'),
      ),
      _label('Take it down'),
      LfChoiceRow<String?>(
        keyPrefix: 'lfExpiry',
        options: [
          (null, d.startsAt != null ? 'When it starts' : 'In a week'),
          ('1h', 'In 1 hour'),
          ('today', 'End of today'),
          ('tomorrow', 'End of tomorrow'),
          ('week', 'In a week'),
        ],
        isSelected: (v) => d.expiryPreset == v,
        onTap: (v) => setState(() => d.expiryPreset = v),
      ),
    ];
  }

  // ---------------------------------------------------------------------------

  Widget _reviewStep() {
    final c = context.sx;
    _sync();
    final d = _draft!;
    final cat = _category!;
    final sub = cat.subcategories.where((s) => s.id == d.subcategoryId).firstOrNull?.label;
    final rows = <(String, String)>[
      ('Looking for', [cat.label, ?sub].join(' · ')),
      if (cat.form.has('quantity')) (cat.form.quantityLabel ?? 'How many', '${d.quantity}'),
      if (d.startsAt != null)
        (
          'When',
          '${relativeDay(d.startsAt!, DateTime.now())} · ${timeShort(d.startsAt!)}${d.endsAt != null ? '–${timeShort(d.endsAt!)}' : d.durationMins != null ? '–${timeShort(d.startsAt!.add(Duration(minutes: d.durationMins!)))}' : ''}',
        ),
      ('Where', [if (d.placeName.trim().isNotEmpty) d.placeName.trim(), d.city.trim()].join(' · ')),
      if (d.skillLevels.isNotEmpty) ('Level', d.skillLevels.map((s) => lfSkillLabels[s]).join(' / ')),
      if (d.gender != 'any') ('Open to', d.gender == 'male' ? 'Men' : 'Women'),
      if (d.paymentType != LfPaymentType.none)
        (
          'Payment',
          '${d.paymentType == LfPaymentType.paid ? 'Paid' : 'Shared cost'}${d.paymentAmount != null ? ' · ${formatInr(d.paymentAmount!, freeWhenZero: false)} ${lfPaymentUnits[d.paymentUnit]}' : ''}',
        ),
      for (final f in cat.form.details)
        if (d.details[f.key] != null && '${d.details[f.key]}'.isNotEmpty) (f.label, '${d.details[f.key]}'),
    ];
    return ListView(
      key: const ValueKey('review'),
      padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s32),
      children: [
        Text('Review requirement', style: SxType.label(c.inkMuted)),
        const SizedBox(height: Sx.s8),
        TextField(
          key: const Key('lfReviewTitle'),
          controller: _title,
          maxLength: 80,
          style: SxType.heading(c.ink, size: 22),
          onChanged: (_) => _titleEdited = true,
          decoration: const InputDecoration(border: InputBorder.none, counterText: ''),
        ),
        if (d.description.trim().isNotEmpty) Text(d.description.trim(), style: SxType.body(c.inkMuted)),
        const SizedBox(height: Sx.s16),
        SxRows(children: [for (final (label, value) in rows) SxRow(label: label, value: value)]),
        const SizedBox(height: Sx.s12),
        SxButton.quiet(label: 'Change details', icon: Icons.edit_outlined, onPressed: () => setState(() => _step = _Step.details)),
        const SizedBox(height: Sx.s16),
        Text(
          'Posting shows this on Looking For and alerts people nearby whose settings and profile fit. They answer here; your phone number stays private.',
          style: SxType.caption(c.inkMuted, size: 12.5),
        ),
        const SizedBox(height: Sx.s16),
        SxButton(key: const Key('lfSubmit'), label: 'Post', icon: Icons.campaign_rounded, busy: _busy, onPressed: _post),
      ],
    );
  }

  Widget _doneStep() {
    final c = context.sx;
    final (post, matching) = _result!;
    return ListView(
      key: const ValueKey('done'),
      padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s32, Sx.gutter, Sx.s32),
      children: [
        Center(child: SxIconTile(icon: Icons.campaign_rounded, size: 64, solid: true, colors: [c.voltFill, c.olive])),
        const SizedBox(height: Sx.s24),
        Text("It's live", textAlign: TextAlign.center, style: SxType.title(c.ink, size: 30)),
        const SizedBox(height: Sx.s8),
        Text(post.title, textAlign: TextAlign.center, style: SxType.heading(c.inkMuted, size: 16)),
        const SizedBox(height: Sx.s24),
        SxBlock(
          child: Column(
            children: [
              Text(
                matching.count == 0 ? 'No one matches yet' : '${matching.count} ${matching.count == 1 ? 'person' : 'people'} may match your requirement',
                textAlign: TextAlign.center,
                style: SxType.heading(c.ink, size: 16),
              ),
              const SizedBox(height: Sx.s4),
              Text(
                matching.count == 0
                    ? "SkorX will tell people as they set alerts that fit. Share it to reach more now."
                    : 'SkorX alerted the closest fits, without spamming anyone. You will hear as soon as someone responds.',
                textAlign: TextAlign.center,
                style: SxType.caption(c.inkMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: Sx.s24),
        SxButton(
          key: const Key('lfViewPosted'),
          label: 'View request',
          onPressed: () => context.pushReplacement('/player/looking-for/${post.id}'),
        ),
        const SizedBox(height: Sx.s12),
        SxButton.secondary(label: 'Share', icon: Icons.ios_share_rounded, onPressed: () => shareLfPost(context, ref, post)),
      ],
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({super.key, required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Tappable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Sx.s16, vertical: Sx.s12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Sx.radiusSm),
          border: Border.all(color: c.cardEdge),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: SxType.label(c.inkMuted, size: 11)),
            const SizedBox(height: 2),
            Text(value, style: SxType.number(20, c.ink)),
          ],
        ),
      ),
    );
  }
}
