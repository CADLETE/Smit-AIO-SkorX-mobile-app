import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/theme/typography.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/format.dart';
import '../../../shared/ui/components.dart';
import '../../../sports/core/match_rules.dart';
import '../../player/data/player_repository.dart' show PlayCategory;
import '../../tournaments/data/tournaments.dart' show skillLevels;
import '../data/organizer_repository.dart';
import '../data/tms_models.dart';
import 'org_widgets.dart';

/// A category while it is being set up.
class _CategoryDraft {
  _CategoryDraft(this.name, this.format, {this.level = 'Open'});

  String name;
  PlayCategory format;
  String level;
  DrawFormat drawFormat = DrawFormat.knockout;
  int fee = 500;
  int capacity = 16;
  int pointsToWin = 11;
  int bestOf = 1;

  OrgCategory build(int i) => OrgCategory(
        id: 'draft-$i',
        name: name,
        format: format,
        level: level,
        drawFormat: drawFormat,
        fee: fee,
        capacity: capacity,
        rules: MatchRules(pointsToWin: pointsToWin, winByTwo: true, bestOf: bestOf, scoring: ScoringSystem.sideOut),
      );
}

const _presets = [
  ("Men's Doubles", PlayCategory.doubles),
  ("Women's Doubles", PlayCategory.doubles),
  ('Mixed Doubles', PlayCategory.mixed),
  ("Men's Singles", PlayCategory.singles),
  ("Women's Singles", PlayCategory.singles),
  ('Open Doubles', PlayCategory.doubles),
];

/// Five short steps with sensible defaults, so a first tournament takes
/// minutes: basics, categories, format, registration and fees, review.
class CreateTournamentPage extends ConsumerStatefulWidget {
  const CreateTournamentPage({super.key, required this.orgId});

  final String orgId;

  @override
  ConsumerState<CreateTournamentPage> createState() => _CreateTournamentPageState();
}

class _CreateTournamentPageState extends ConsumerState<CreateTournamentPage> {
  static const _titles = ['Basics', 'Categories', 'Format', 'Registration', 'Review'];

  var _step = 0;
  var _saving = false;
  String? _error;

  final _name = TextEditingController();
  final _description = TextEditingController();
  final _venue = TextEditingController(text: 'Smash Arena');
  final _city = TextEditingController(text: 'Ahmedabad');
  var _indoor = true;
  late DateTime _day;
  var _startTime = const TimeOfDay(hour: 8, minute: 0);
  var _endTime = const TimeOfDay(hour: 20, minute: 0);
  var _days = 1;
  late DateTime _regOpens;
  late DateTime _regCloses;
  var _courts = 6;
  var _waitlist = true;
  var _earlyBird = 0;
  final List<_CategoryDraft> _categories = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _day = DateTime(now.year, now.month, now.day + 21);
    _regOpens = now;
    _regCloses = DateTime(_day.year, _day.month, _day.day - 2, 23, 59);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _venue.dispose();
    _city.dispose();
    super.dispose();
  }

  DateTime get _start => DateTime(_day.year, _day.month, _day.day, _startTime.hour, _startTime.minute);
  DateTime get _end => DateTime(_day.year, _day.month, _day.day + _days - 1, _endTime.hour, _endTime.minute);

  TournamentDraft get _draft => TournamentDraft(
        name: _name.text,
        description: _description.text,
        venue: _venue.text,
        city: _city.text,
        indoor: _indoor,
        start: _start,
        end: _end,
        registrationOpens: _regOpens,
        registrationCloses: _regCloses,
        categories: [for (final (i, c) in _categories.indexed) c.build(i)],
        courts: _courts,
        waitlist: _waitlist,
        earlyBirdDiscount: _earlyBird,
      );

  /// What stops the current step, in words, or null.
  String? get _stepProblem => switch (_step) {
        0 => _name.text.trim().length < 3
            ? 'Give the tournament a name.'
            : _venue.text.trim().isEmpty
                ? 'Add the venue.'
                : null,
        1 => _categories.isEmpty ? 'Add at least one category.' : null,
        3 => _regCloses.isAfter(_start) ? 'Registration must close before the first match.' : null,
        _ => null,
      };

  void _next() {
    final problem = _stepProblem;
    setState(() => _error = problem);
    if (problem != null) return;
    FocusScope.of(context).unfocus();
    setState(() => _step++);
  }

  Future<void> _save({required bool publish}) async {
    final problem = _draft.problem;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (publish) {
      final ok = await confirmAction(
        context,
        title: 'Publish tournament?',
        message: 'Players will see ${_name.text.trim()} in the SkorX app and can register straight away.',
        confirm: 'Publish',
      );
      if (!ok) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final t = await ref.read(organizerRepositoryProvider).createTournament(widget.orgId, _draft, publish: publish);
      if (!mounted) return;
      showSkxToast(context, publish ? 'Published. Registration is open.' : 'Saved as a draft.');
      context.pushReplacement('/org/${widget.orgId}/t/${t.id}');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong while saving. Nothing was lost; try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    if (!orgPermissions(ref, widget.orgId).editTournaments) {
      return DetailScaffold(
        title: 'New tournament',
        fallback: '/org/${widget.orgId}/tournaments',
        body: const NoAccess(what: 'create tournaments'),
      );
    }
    final last = _step == _titles.length - 1;
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step--);
      },
      child: DetailScaffold(
        title: 'New tournament',
        fallback: '/org/${widget.orgId}/tournaments',
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(SkorxSpace.lg, 0, SkorxSpace.lg, SkorxSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < _titles.length; i++) ...[
                        Expanded(
                          child: Container(
                            height: 5,
                            decoration: BoxDecoration(
                              color: i <= _step ? colors.lime : colors.surfaceInteractive,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        if (i < _titles.length - 1) const SizedBox(width: 4),
                      ],
                    ],
                  ),
                  const SizedBox(height: SkorxSpace.sm),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'STEP ${_step + 1} OF ${_titles.length} · ${_titles[_step].toUpperCase()}',
                      style: SkorxType.label(color: colors.textMuted, size: 12),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                key: ValueKey(_step),
                padding: const EdgeInsets.fromLTRB(SkorxSpace.lg, 0, SkorxSpace.lg, SkorxSpace.xxl),
                children: switch (_step) {
                  0 => _basics(),
                  1 => _categoriesStep(),
                  2 => _formatStep(),
                  3 => _registrationStep(),
                  _ => _review(),
                },
              ),
            ),
          ],
        ),
        bottom: BottomCtaBar(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: SkorxSpace.md),
                  child: Semantics(
                    liveRegion: true,
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: colors.live, size: 18),
                        const SizedBox(width: SkorxSpace.sm),
                        Expanded(child: Text(_error!, style: TextStyle(color: colors.live, fontWeight: FontWeight.w600))),
                      ],
                    ),
                  ),
                ),
              Row(
                children: [
                  if (_step > 0) ...[
                    SkxButton.secondary(label: 'Back', expand: false, onPressed: () => setState(() => _step--)),
                    const SizedBox(width: SkorxSpace.md),
                  ],
                  Expanded(
                    child: last
                        ? SkxButton(
                            key: const Key('publishTournament'),
                            label: 'Publish',
                            busy: _saving,
                            onPressed: () => _save(publish: true),
                          )
                        : SkxButton(key: const Key('wizardNext'), label: 'Continue', onPressed: _next),
                  ),
                ],
              ),
              if (last)
                SkxButton.ghost(
                  key: const Key('saveDraft'),
                  label: 'Save as draft',
                  onPressed: _saving ? null : () => _save(publish: false),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- steps

  Widget _label(String text) {
    final colors = context.skorx.colors;
    return Padding(
      padding: const EdgeInsets.only(top: SkorxSpace.lg, bottom: SkorxSpace.sm),
      child: Text(text.toUpperCase(), style: SkorxType.label(color: colors.textMuted, size: 12)),
    );
  }

  Widget _field(TextEditingController c, String hint, {Key? key, int lines = 1, TextInputType? type}) => TextField(
        key: key,
        controller: c,
        maxLines: lines,
        keyboardType: type,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) => setState(() => _error = null),
        decoration: InputDecoration(hintText: hint),
      );

  Widget _pickerTile(IconData icon, String label, String value, VoidCallback onTap, {Key? key}) => SkxCard(
        key: key,
        onTap: onTap,
        padding: const EdgeInsets.all(SkorxSpace.md),
        child: InfoTile(icon: icon, label: label, value: value),
      );

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    setState(() {
      _day = picked;
      if (_regCloses.isAfter(_start)) _regCloses = DateTime(picked.year, picked.month, picked.day - 1, 23, 59);
    });
  }

  Future<void> _pickTime(bool start) async {
    final picked = await showTimePicker(context: context, initialTime: start ? _startTime : _endTime);
    if (picked != null) setState(() => start ? _startTime = picked : _endTime = picked);
  }

  List<Widget> _basics() => [
        _label('Tournament name'),
        _field(_name, 'e.g. SkorX Summer Open 2026', key: const Key('tournamentName')),
        _label('Description'),
        _field(_description, 'What players should know (optional)', lines: 3),
        _label('Venue'),
        _field(_venue, 'Venue name', key: const Key('venueField')),
        const SizedBox(height: SkorxSpace.sm),
        _field(_city, 'City'),
        const SizedBox(height: SkorxSpace.md),
        SkxSegmented<bool>(
          segments: const [(true, 'Indoor'), (false, 'Outdoor')],
          selected: _indoor,
          onChanged: (v) => setState(() => _indoor = v),
        ),
        _label('When'),
        _pickerTile(Icons.event_rounded, 'First day', dayDate(_day), _pickDay),
        const SizedBox(height: SkorxSpace.sm),
        Row(
          children: [
            Expanded(child: _pickerTile(Icons.schedule_rounded, 'Starts', _startTime.format(context), () => _pickTime(true))),
            const SizedBox(width: SkorxSpace.sm),
            Expanded(child: _pickerTile(Icons.flag_rounded, 'Ends', _endTime.format(context), () => _pickTime(false))),
          ],
        ),
        const SizedBox(height: SkorxSpace.sm),
        _Stepper(label: 'Days', value: _days, min: 1, max: 7, onChanged: (v) => setState(() => _days = v)),
      ];

  List<Widget> _categoriesStep() {
    final colors = context.skorx.colors;
    return [
      Text('Tap to add. Set levels and fees on the next steps.', style: TextStyle(color: colors.textMuted)),
      const SizedBox(height: SkorxSpace.md),
      Wrap(
        spacing: SkorxSpace.sm,
        runSpacing: SkorxSpace.xs,
        children: [
          for (final (name, format) in _presets)
            SkxChip(
              key: Key('preset-$name'),
              label: name,
              icon: _categories.any((c) => c.name == name) ? Icons.check_rounded : Icons.add_rounded,
              selected: _categories.any((c) => c.name == name),
              onTap: () => setState(() {
                _error = null;
                final existing = _categories.where((c) => c.name == name).toList();
                if (existing.isEmpty) {
                  _categories.add(_CategoryDraft(name, format, level: 'Intermediate'));
                } else {
                  _categories.removeWhere((c) => c.name == name);
                }
              }),
            ),
          SkxChip(label: 'Custom', icon: Icons.edit_rounded, selected: false, onTap: _addCustom),
        ],
      ),
      const SizedBox(height: SkorxSpace.lg),
      for (final c in _categories) ...[
        SkxCard(
          padding: const EdgeInsets.all(SkorxSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                  IconButton(
                    tooltip: 'Remove ${c.name}',
                    icon: Icon(Icons.close_rounded, color: colors.textMuted),
                    onPressed: () => setState(() => _categories.remove(c)),
                  ),
                ],
              ),
              Wrap(
                spacing: SkorxSpace.sm,
                children: [
                  for (final level in skillLevels)
                    SkxChip(label: level, selected: c.level == level, onTap: () => setState(() => c.level = level)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: SkorxSpace.sm),
      ],
    ];
  }

  Future<void> _addCustom() async {
    final name = TextEditingController();
    var format = PlayCategory.doubles;
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            SkorxSpace.xl,
            0,
            SkorxSpace.xl,
            SkorxSpace.xl + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('CUSTOM CATEGORY', style: SkorxType.headline(24, color: context.skorx.colors.text)),
              const SizedBox(height: SkorxSpace.lg),
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'e.g. Veterans 50+ Doubles'),
              ),
              const SizedBox(height: SkorxSpace.md),
              SkxSegmented<PlayCategory>(
                segments: [for (final f in PlayCategory.values) (f, f.label)],
                selected: format,
                onChanged: (v) => setSheet(() => format = v),
              ),
              const SizedBox(height: SkorxSpace.lg),
              SkxButton(label: 'Add category', onPressed: () => Navigator.pop(context, name.text.trim().isNotEmpty)),
            ],
          ),
        ),
      ),
    );
    if (added == true) setState(() => _categories.add(_CategoryDraft(name.text.trim(), format)));
    name.dispose();
  }

  List<Widget> _formatStep() {
    final colors = context.skorx.colors;
    return [
      Text('How each category is played. You can use a different format per category.',
          style: TextStyle(color: colors.textMuted)),
      for (final c in _categories) ...[
        _label(c.name),
        SkxCard(
          padding: const EdgeInsets.all(SkorxSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkxSegmented<DrawFormat>(
                segments: [for (final f in DrawFormat.values) (f, f.label)],
                selected: c.drawFormat,
                onChanged: (v) => setState(() => c.drawFormat = v),
              ),
              const SizedBox(height: SkorxSpace.md),
              Row(
                children: [
                  Expanded(
                    child: SkxSegmented<int>(
                      segments: const [(11, 'To 11'), (15, 'To 15'), (21, 'To 21')],
                      selected: c.pointsToWin,
                      onChanged: (v) => setState(() => c.pointsToWin = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SkorxSpace.sm),
              SkxSegmented<int>(
                segments: const [(1, '1 game'), (3, 'Best of 3'), (5, 'Best of 5')],
                selected: c.bestOf,
                onChanged: (v) => setState(() => c.bestOf = v),
              ),
              const SizedBox(height: SkorxSpace.sm),
              Text('Side-out scoring, win by 2.', style: TextStyle(color: colors.textMuted, fontSize: 12.5)),
            ],
          ),
        ),
      ],
    ];
  }

  Future<void> _pickRegDate(bool opens) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: opens ? _regOpens : _regCloses,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: _day,
    );
    if (picked == null) return;
    setState(() {
      _error = null;
      if (opens) {
        _regOpens = picked;
      } else {
        _regCloses = DateTime(picked.year, picked.month, picked.day, 23, 59);
      }
    });
  }

  List<Widget> _registrationStep() => [
        _label('Registration window'),
        Row(
          children: [
            Expanded(child: _pickerTile(Icons.lock_open_rounded, 'Opens', dayDate(_regOpens), () => _pickRegDate(true))),
            const SizedBox(width: SkorxSpace.sm),
            Expanded(child: _pickerTile(Icons.lock_clock_rounded, 'Closes', dayDate(_regCloses), () => _pickRegDate(false))),
          ],
        ),
        const SizedBox(height: SkorxSpace.sm),
        SkxCard(
          padding: const EdgeInsets.symmetric(horizontal: SkorxSpace.md),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Waitlist when full', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Late entries queue and move up if someone drops out.'),
            value: _waitlist,
            onChanged: (v) => setState(() => _waitlist = v),
          ),
        ),
        const SizedBox(height: SkorxSpace.sm),
        _Stepper(label: 'Courts', value: _courts, min: 1, max: 24, onChanged: (v) => setState(() => _courts = v)),
        _label('Entries and fees, per category'),
        for (final c in _categories) ...[
          SkxCard(
            padding: const EdgeInsets.all(SkorxSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${c.name} · ${c.level}', style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: SkorxSpace.sm),
                _Stepper(
                  label: c.format == PlayCategory.singles ? 'Players' : 'Teams',
                  value: c.capacity,
                  min: 2,
                  max: 128,
                  step: c.capacity >= 16 ? 8 : 2,
                  onChanged: (v) => setState(() => c.capacity = v),
                ),
                const SizedBox(height: SkorxSpace.sm),
                _MoneyField(
                  label: c.format == PlayCategory.singles ? 'Fee per player' : 'Fee per team',
                  value: c.fee,
                  onChanged: (v) => c.fee = v,
                ),
              ],
            ),
          ),
          const SizedBox(height: SkorxSpace.sm),
        ],
        _label('Early bird'),
        _MoneyField(label: 'Discount for the first week (₹)', value: _earlyBird, onChanged: (v) => _earlyBird = v),
        const SizedBox(height: SkorxSpace.sm),
        Text(
          'Players pay by UPI or card through Razorpay when they register. GST is added at checkout; refunds follow your refund policy in Settings.',
          style: TextStyle(color: context.skorx.colors.textMuted, fontSize: 12.5, height: 1.4),
        ),
      ];

  List<Widget> _review() {
    final colors = context.skorx.colors;
    final d = _draft;
    return [
      SkxCard(
        padding: const EdgeInsets.all(SkorxSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(d.name.trim().toUpperCase(), style: SkorxType.headline(28, color: colors.text)),
            const SizedBox(height: SkorxSpace.lg),
            InfoTile(icon: Icons.event_rounded, label: 'When', value: '${dateRange(d.start, d.end)} · ${time12(d.start)}'),
            const SizedBox(height: SkorxSpace.md),
            InfoTile(
              icon: Icons.place_rounded,
              label: 'Where',
              value: '${d.venue}, ${d.city} · ${d.indoor ? 'Indoor' : 'Outdoor'} · ${d.courts} courts',
            ),
            const SizedBox(height: SkorxSpace.md),
            InfoTile(
              icon: Icons.how_to_reg_rounded,
              label: 'Registration',
              value: '${dayDate(d.registrationOpens)} to ${dayDate(d.registrationCloses)}',
            ),
          ],
        ),
      ),
      _label('${d.categories.length} categories'),
      for (final c in d.categories) ...[
        SkxCard(
          padding: const EdgeInsets.all(SkorxSpace.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('${c.drawFormat.label} · ${c.rules.describe()} · ${c.capacity} entries',
                        style: TextStyle(color: colors.textMuted, fontSize: 12.5)),
                  ],
                ),
              ),
              Text(formatInr(c.fee), style: SkorxType.score(18, color: colors.text)),
            ],
          ),
        ),
        const SizedBox(height: SkorxSpace.sm),
      ],
    ];
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.label, required this.value, required this.min, required this.max, required this.onChanged, this.step = 1});

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.skorx.colors;
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
        IconButton.filledTonal(
          tooltip: 'Fewer $label',
          onPressed: value <= min ? null : () => onChanged((value - step).clamp(min, max)),
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 52,
          child: Text('$value', textAlign: TextAlign.center, style: SkorxType.score(24, color: colors.text)),
        ),
        IconButton.filledTonal(
          tooltip: 'More $label',
          onPressed: value >= max ? null : () => onChanged((value + step).clamp(min, max)),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

class _MoneyField extends StatefulWidget {
  const _MoneyField({required this.label, required this.value, required this.onChanged});

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_MoneyField> createState() => _MoneyFieldState();
}

class _MoneyFieldState extends State<_MoneyField> {
  late final _c = TextEditingController(text: '${widget.value}');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        onChanged: (v) => widget.onChanged(int.tryParse(v) ?? 0),
        decoration: InputDecoration(labelText: widget.label, prefixText: '₹ '),
      );
}
