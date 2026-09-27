import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/theme/typography.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/app_permissions.dart';
import '../../onboarding/onboarding_controller.dart';
import '../../onboarding/ui/onboarding_kit.dart';
import '../../onboarding/ui/player_photo.dart';
import '../../settings/app_settings.dart';
import '../auth_controller.dart';
import '../auth_errors.dart';
import '../data/auth_repository.dart';

/// A new player builds their SkorX identity, one question per screen:
/// name, photo, level, playing hand, how they play, and where. Only the name is required
/// to go on; everything is saved as they go, so leaving and coming back
/// resumes on the same question.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  static const steps = 6;

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

/// The six questions, then the permissions that make SkorX work nearby.
enum _Step { name, photo, level, hand, game, city, permissions }

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _city = TextEditingController();
  final _lastFocus = FocusNode();

  ProfileDraft _draft = const ProfileDraft();
  bool _loaded = false;
  bool _forward = true;
  bool _busy = false;
  String? _error;

  String? get _userId => ref.read(currentUserProvider)?.id;
  _Step get _step => _Step.values[_draft.step.clamp(0, _Step.values.length - 1)];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = _userId;
    final saved = id == null ? null : await ref.read(profileDraftStoreProvider).read(id);
    if (!mounted) return;
    final draft = saved ?? const ProfileDraft();
    _first.text = draft.firstName;
    _last.text = draft.lastName;
    _city.text = draft.city ?? '';
    setState(() {
      _draft = draft;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _city.dispose();
    _lastFocus.dispose();
    super.dispose();
  }

  void _update(ProfileDraft Function(ProfileDraft) change) {
    setState(() {
      _draft = change(_draft);
      _error = null;
    });
    final id = _userId;
    if (id != null) ref.read(profileDraftStoreProvider).write(id, _draft);
  }

  void _goTo(int step) {
    FocusScope.of(context).unfocus();
    _forward = step > _draft.step;
    final typedCity = _city.text.trim();
    _update(
      (d) => d.copyWith(
        step: step,
        firstName: _first.text,
        lastName: _last.text,
        city: typedCity.isEmpty ? null : () => typedCity,
      ),
    );
  }

  bool get _canContinue => switch (_step) {
        // Both names: they are how a player appears in draws and rankings.
        _Step.name => _first.text.trim().isNotEmpty && _last.text.trim().isNotEmpty,
        _Step.photo => true,
        _Step.level => _draft.level != null,
        _Step.hand => _draft.hand != null,
        _Step.game => _draft.formats.isNotEmpty,
        _Step.city => _city.text.trim().isNotEmpty,
        _Step.permissions => true,
      };

  Future<void> _next() async {
    if (!_canContinue || _busy) return;
    if (_step == _Step.permissions) return _allowAndFinish();
    _goTo(_draft.step + 1);
  }

  void _back() {
    if (_draft.step > 0) _goTo(_draft.step - 1);
  }

  Future<void> _finish() async {
    final city = _city.text.trim().isEmpty ? null : _city.text.trim();
    final draft = _draft.copyWith(firstName: _first.text, lastName: _last.text, city: () => city);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Kept on this phone first: the welcome card reads them the moment
      // the server accepts the profile and the router moves on.
      ref.read(appSettingsProvider.notifier).update(
            (s) => s.copyWith(
              homeCity: city,
              level: draft.level,
              hand: draft.hand,
              formats: draft.formats.toList()..sort(),
              photoPath: draft.photoPath,
            ),
          );
      final id = _userId;
      await ref.read(authControllerProvider.notifier).completeProfile(ProfileUpdate(name: draft.fullName, city: city));
      if (id != null) await ref.read(profileDraftStoreProvider).clear(id);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = SignInProblem.from(e).$2);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 900,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.front,
      );
      if (picked == null) return;
      // The picker's file lives in a cache the system may clear.
      final dir = await getApplicationDocumentsDirectory();
      final saved = await File(picked.path).copy('${dir.path}/player_photo_${DateTime.now().millisecondsSinceEpoch}.jpg');
      final previous = _draft.photoPath;
      _update((d) => d.copyWith(photoPath: () => saved.path));
      if (previous != null) File(previous).delete().ignore();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            source == ImageSource.camera
                ? "Couldn't open the camera. You can add a photo later from your profile."
                : "Couldn't open your photos. You can add a photo later from your profile.",
          ),
        ),
      );
    }
  }

  /// Asks for whatever has not been answered yet, one system prompt at a
  /// time, then saves the profile whatever the answers: SkorX works without
  /// them, just less well.
  Future<void> _allowAndFinish() async {
    final permissions = ref.read(appPermissionsProvider);
    for (final p in AppPermission.values) {
      if (_answers[p] == PermissionAnswer.notAsked) {
        final answer = await permissions.request(p);
        if (!mounted) return;
        setState(() => _answers[p] = answer);
      }
    }
    await _finish();
  }

  final Map<AppPermission, PermissionAnswer> _answers = {
    for (final p in AppPermission.values) p: PermissionAnswer.notAsked,
  };

  Future<void> _useAnotherNumber() => ref.read(authControllerProvider.notifier).signOut();

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    final index = _draft.step;
    final last = _step == _Step.permissions;
    final allAnswered = _answers.values.every((a) => a != PermissionAnswer.notAsked);

    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: OnboardScaffold(
        courtTop: 0.78,
        backdropStrength: 0.7,
        ball: false,
        leading: index == 0
            ? OnboardIconButton(
                key: const Key('setupClose'),
                icon: Icons.close_rounded,
                label: 'Use another number',
                onPressed: _busy ? null : _useAnotherNumber,
              )
            : OnboardIconButton(icon: Icons.arrow_back_rounded, label: 'Back', onPressed: _busy ? null : _back),
        top: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(end: (index + 1).clamp(1, ProfileSetupScreen.steps) / ProfileSetupScreen.steps),
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOutCubic,
              builder: (_, value, _) {
                final exact = value * ProfileSetupScreen.steps;
                return SegmentedProgress(
                  count: ProfileSetupScreen.steps,
                  index: (exact - 0.001).floor().clamp(0, ProfileSetupScreen.steps - 1),
                  progress: exact - (exact - 0.001).floor(),
                  label: last ? 'Almost there' : 'Step ${index + 1} of ${ProfileSetupScreen.steps}',
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              last ? 'ALMOST THERE' : 'STEP ${index + 1} OF ${ProfileSetupScreen.steps}',
              style: OnboardType.eyebrow(palette.inkMuted),
            ),
          ],
        ),
        body: !_loaded
            ? const SizedBox(height: 200)
            : AnimatedSwitcher(
                duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 360),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topLeft,
                  children: [...previous, ?current],
                ),
                transitionBuilder: (child, animation) {
                  final incoming = child.key == ValueKey(_step);
                  final dx = (incoming == _forward) ? 0.12 : -0.12;
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(key: ValueKey(_step), child: _buildStep(context)),
              ),
        bottom: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              OnboardError(message: _error!, action: 'Retry', onAction: _finish),
              const SizedBox(height: 12),
            ],
            OnboardButton(
              key: const Key('setupNext'),
              label: last ? (allAnswered ? 'Finish' : 'Allow & finish') : 'Continue',
              icon: last ? Icons.check_rounded : Icons.arrow_forward_rounded,
              busy: _busy,
              onPressed: _canContinue ? _next : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context) => switch (_step) {
        _Step.name => _Question(
            title: 'WHAT SHOULD WE CALL YOU?',
            subtitle: 'This is how you appear in scores, draws and rankings.',
            child: Column(
              children: [
                _BigField(
                  key: const Key('firstNameField'),
                  controller: _first,
                  label: 'First name',
                  autofillHints: const [AutofillHints.givenName],
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _lastFocus.requestFocus(),
                ),
                const SizedBox(height: 14),
                _BigField(
                  key: const Key('lastNameField'),
                  controller: _last,
                  focusNode: _lastFocus,
                  label: 'Last name',
                  autofillHints: const [AutofillHints.familyName],
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _next(),
                ),
              ],
            ),
          ),
        _Step.photo => _Question(
            title: 'ADD YOUR PLAYER PHOTO',
            subtitle: 'Optional. It helps partners and opponents recognise you at the court.',
            child: _PhotoStep(
              name: ProfileDraft(firstName: _first.text, lastName: _last.text).fullName,
              photoPath: _draft.photoPath,
              onCamera: () => _pickPhoto(ImageSource.camera),
              onGallery: () => _pickPhoto(ImageSource.gallery),
            ),
          ),
        _Step.level => _Question(
            title: "WHAT'S YOUR LEVEL?",
            subtitle: 'Pick what sounds most like you. Your rating builds from real matches.',
            child: Column(
              children: [
                for (final level in PlayerLevel.values) ...[
                  _ChoiceCard(
                    key: Key('level-${level.name}'),
                    title: level.label.toUpperCase(),
                    subtitle: level.description,
                    leading: _LevelBars(filled: level.index + 1),
                    selected: _draft.level == level.name,
                    onTap: () => _update((d) => d.copyWith(level: level.name)),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        _Step.hand => _Question(
            title: 'WHICH HAND DO YOU PLAY WITH?',
            subtitle: 'Partners and opponents plan around it, and it helps us pair you in doubles.',
            child: Column(
              children: [
                for (final (value, label, subtitle) in const [
                  ('Right', 'RIGHT-HANDED', 'Paddle in my right hand'),
                  ('Left', 'LEFT-HANDED', 'Paddle in my left hand'),
                ]) ...[
                  _ChoiceCard(
                    key: Key('hand-${value.toLowerCase()}'),
                    title: label,
                    subtitle: subtitle,
                    leading: _Hand(left: value == 'Left'),
                    selected: _draft.hand == value,
                    onTap: () => _update((d) => d.copyWith(hand: value)),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        _Step.game => _Question(
            title: 'TELL US ABOUT YOUR GAME',
            subtitle: 'How do you like to play? Pick all that apply.',
            child: _GameStep(
              formats: _draft.formats,
              onChanged: (formats) => _update((d) => d.copyWith(formats: formats)),
            ),
          ),
        _Step.city => _Question(
            title: 'WHERE DO YOU PLAY?',
            subtitle: "We'll show courts, tournaments, players and rankings near you.",
            child: _CityStep(
              controller: _city,
              selected: _draft.city,
              onSelected: (city) {
                _city.text = city ?? '';
                FocusScope.of(context).unfocus();
                _update((d) => d.copyWith(city: () => city));
              },
              onTyped: () => setState(() {}),
            ),
          ),
        _Step.permissions => _Question(
            title: 'STAY IN THE GAME',
            subtitle: 'Two quick permissions so SkorX works best for you. You can change them any time in Settings.',
            child: _PermissionsStep(
              answers: _answers,
              onAnswer: (p, answer) => setState(() => _answers[p] = answer),
            ),
          ),
      };
}

/// One question: a big statement, one line of why, then the answer.
class _Question extends StatelessWidget {
  const _Question({required this.title, required this.subtitle, required this.child});

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(title, style: OnboardType.statement(context, palette.ink, max: 46))),
        const SizedBox(height: 12),
        Text(subtitle, style: OnboardType.body(palette.inkMuted)),
        const SizedBox(height: 28),
        child,
      ],
    );
  }
}

class _BigField extends StatelessWidget {
  const _BigField({
    super.key,
    required this.controller,
    required this.label,
    this.focusNode,
    this.autofillHints,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
  });

  final TextEditingController controller;
  final String label;
  final FocusNode? focusNode;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final IconData? prefixIcon;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: color, width: width));
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      textCapitalization: TextCapitalization.words,
      cursorColor: palette.accent,
      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: palette.ink),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: palette.inkMuted, fontSize: 16),
        floatingLabelStyle: TextStyle(color: palette.accent, fontWeight: FontWeight.w600),
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, color: palette.inkMuted),
        filled: true,
        fillColor: palette.isDark ? const Color(0x14FFFFFF) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        enabledBorder: border(palette.glassBorder),
        focusedBorder: border(palette.accent, 1.6),
        border: border(palette.glassBorder),
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

// ─── Photo ───────────────────────────────────────────────────────────────

class _PhotoStep extends StatelessWidget {
  const _PhotoStep({required this.name, required this.photoPath, required this.onCamera, required this.onGallery});

  final String name;
  final String? photoPath;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    return Column(
      children: [
        Center(child: PlayerPhoto(name: name, photoPath: photoPath, size: 168)),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: _SourceButton(key: const Key('photoCamera'), icon: Icons.photo_camera_outlined, label: 'Camera', onTap: onCamera),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SourceButton(
                key: const Key('photoGallery'),
                icon: Icons.photo_library_outlined,
                label: photoPath == null ? 'Gallery' : 'Change',
                onTap: onGallery,
              ),
            ),
          ],
        ),
        if (photoPath != null) ...[
          const SizedBox(height: 16),
          Text('Looking good.', style: TextStyle(color: palette.accentText, fontWeight: FontWeight.w600)),
        ],
      ],
    );
  }
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    return Material(
      color: palette.isDark ? const Color(0x14FFFFFF) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: palette.glassBorder)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: palette.ink, size: 22),
              const SizedBox(width: 10),
              Text(label, style: TextStyle(color: palette.ink, fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Choices ─────────────────────────────────────────────────────────────

/// A big selectable card: lifts, tints and ticks when chosen.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget leading;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    final base = palette.isDark ? const Color(0x0FFFFFFF) : Colors.white;
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedScale(
          scale: selected && !reduceMotion(context) ? 1.015 : 1,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: selected ? Color.alphaBlend(palette.accent.withValues(alpha: palette.isDark ? 0.16 : 0.08), base) : base,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: selected ? palette.accent : palette.glassBorder, width: selected ? 1.8 : 1),
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: SkorxType.label(color: palette.ink, size: 20).copyWith(letterSpacing: 1.4)),
                      const SizedBox(height: 3),
                      Text(subtitle, style: TextStyle(color: palette.inkMuted, fontSize: 14, height: 1.3)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                  child: selected
                      ? Container(
                          key: const ValueKey('on'),
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(color: palette.accent, shape: BoxShape.circle),
                          child: const Icon(Icons.check_rounded, size: 17, color: Colors.white),
                        )
                      : Container(
                          key: const ValueKey('off'),
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: palette.inkFaint, width: 1.5)),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One to four rising bars, like signal strength.
class _LevelBars extends StatelessWidget {
  const _LevelBars({required this.filled});

  final int filled;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    return SizedBox(
      width: 30,
      height: 26,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < 4; i++)
            Container(
              width: 5,
              height: 8 + i * 6,
              decoration: BoxDecoration(
                color: i < filled ? (palette.isDark ? palette.ball : palette.ink) : palette.inkFaint.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

/// "L" or "R" in a ring, the way hands are marked on scoresheets.
class _Hand extends StatelessWidget {
  const _Hand({required this.left});

  final bool left;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    final color = palette.isDark ? palette.ball : palette.ink;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 2)),
      child: Text(left ? 'L' : 'R', style: SkorxType.label(color: color, size: 15)),
    );
  }
}

class _GameStep extends StatelessWidget {
  const _GameStep({required this.formats, required this.onChanged});

  final Set<String> formats;
  final ValueChanged<Set<String>> onChanged;

  void _toggle(String format) {
    final next = {...formats};
    if (!next.remove(format)) next.add(format);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final both = formats.containsAll(const {'singles', 'doubles'});
    return Column(
      children: [
        _ChoiceCard(
          key: const Key('format-singles'),
          title: 'SINGLES',
          subtitle: 'One on one',
          leading: const _Players(count: 1),
          selected: formats.contains('singles'),
          onTap: () => _toggle('singles'),
        ),
        const SizedBox(height: 10),
        _ChoiceCard(
          key: const Key('format-doubles'),
          title: 'DOUBLES',
          subtitle: 'Two a side, including mixed',
          leading: const _Players(count: 2),
          selected: formats.contains('doubles'),
          onTap: () => _toggle('doubles'),
        ),
        const SizedBox(height: 10),
        _ChoiceCard(
          key: const Key('format-both'),
          title: 'BOTH',
          subtitle: 'Whatever the court needs',
          leading: const _Players(count: 3),
          selected: both,
          onTap: () => onChanged(both ? {} : {'singles', 'doubles'}),
        ),
      ],
    );
  }
}

class _Players extends StatelessWidget {
  const _Players({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    final icon = switch (count) {
      1 => Icons.person_rounded,
      2 => Icons.people_alt_rounded,
      _ => Icons.groups_rounded,
    };
    return SizedBox(width: 30, child: Icon(icon, size: 28, color: palette.isDark ? palette.ball : palette.ink));
  }
}

// ─── City ────────────────────────────────────────────────────────────────

class _CityStep extends StatelessWidget {
  const _CityStep({required this.controller, required this.selected, required this.onSelected, required this.onTyped});

  final TextEditingController controller;
  final String? selected;
  final ValueChanged<String?> onSelected;
  final VoidCallback onTyped;

  /// Where most SkorX players and tournaments are today.
  static const popular = [
    'Ahmedabad',
    'Mumbai',
    'Delhi',
    'Bengaluru',
    'Pune',
    'Hyderabad',
    'Chennai',
    'Kolkata',
    'Surat',
    'Jaipur',
    'Vadodara',
    'Gurugram',
    'Noida',
    'Chandigarh',
    'Goa',
    'Indore',
  ];

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    final query = controller.text.trim();
    final matches = [
      for (final city in popular)
        if (query.isEmpty || city.toLowerCase().contains(query.toLowerCase())) city,
    ];
    final custom = query.isNotEmpty && !popular.any((c) => c.toLowerCase() == query.toLowerCase());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BigField(
          key: const Key('cityField'),
          controller: controller,
          label: 'Search your city',
          prefixIcon: Icons.search_rounded,
          autofillHints: const [AutofillHints.addressCity],
          textInputAction: TextInputAction.done,
          onChanged: (_) => onTyped(),
          onSubmitted: (value) => onSelected(value.trim().isEmpty ? null : value.trim()),
        ),
        const SizedBox(height: 20),
        Text(query.isEmpty ? 'POPULAR' : 'MATCHES', style: OnboardType.eyebrow(palette.inkMuted)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (custom) _CityChip(label: 'Use “$query”', selected: selected == query, onTap: () => onSelected(query)),
            for (final city in matches) _CityChip(label: city, selected: selected == city, onTap: () => onSelected(city)),
          ],
        ),
      ],
    );
  }
}

class _CityChip extends StatelessWidget {
  const _CityChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? palette.primaryFill : (palette.isDark ? const Color(0x0FFFFFFF) : Colors.white),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: selected ? palette.primaryFill : palette.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[Icon(Icons.place_rounded, size: 16, color: palette.onPrimary), const SizedBox(width: 6)],
              Text(
                label,
                style: TextStyle(
                  color: selected ? palette.onPrimary : palette.ink,
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Permissions ─────────────────────────────────────────────────────────

/// Location and notifications, each with why SkorX wants it. A card asks on
/// its own when tapped; "Allow & finish" asks for whatever is left.
class _PermissionsStep extends ConsumerStatefulWidget {
  const _PermissionsStep({required this.answers, required this.onAnswer});

  final Map<AppPermission, PermissionAnswer> answers;
  final void Function(AppPermission, PermissionAnswer) onAnswer;

  @override
  ConsumerState<_PermissionsStep> createState() => _PermissionsStepState();
}

class _PermissionsStepState extends ConsumerState<_PermissionsStep> {
  @override
  void initState() {
    super.initState();
    // Already answered on this phone (a reinstall, or set in Settings).
    for (final p in AppPermission.values) {
      ref.read(appPermissionsProvider).status(p).then((answer) {
        if (mounted && answer != PermissionAnswer.notAsked) widget.onAnswer(p, answer);
      });
    }
  }

  Future<void> _ask(AppPermission p) async {
    final permissions = ref.read(appPermissionsProvider);
    if (widget.answers[p] == PermissionAnswer.blocked) return permissions.openSettings();
    final answer = await permissions.request(p);
    if (mounted) widget.onAnswer(p, answer);
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _PermissionCard(
            key: const Key('permission-location'),
            icon: Icons.near_me_rounded,
            title: 'LOCATION',
            reason: 'Find courts, tournaments and players near you.',
            answer: widget.answers[AppPermission.location]!,
            onTap: () => _ask(AppPermission.location),
          ),
          const SizedBox(height: 12),
          _PermissionCard(
            key: const Key('permission-notifications'),
            icon: Icons.notifications_active_rounded,
            title: 'NOTIFICATIONS',
            reason: 'Match reminders, live scores and results as they happen.',
            answer: widget.answers[AppPermission.notifications]!,
            onTap: () => _ask(AppPermission.notifications),
          ),
        ],
      );
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.reason,
    required this.answer,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String reason;
  final PermissionAnswer answer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    final granted = answer == PermissionAnswer.granted;
    final base = palette.isDark ? const Color(0x0FFFFFFF) : Colors.white;
    return Semantics(
      button: !granted,
      label: '$title. $reason. ${switch (answer) {
        PermissionAnswer.granted => 'Allowed',
        PermissionAnswer.blocked => 'Turned off. Opens Settings',
        PermissionAnswer.notAsked => 'Allow',
      }}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: granted
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: granted ? Color.alphaBlend(palette.accent.withValues(alpha: palette.isDark ? 0.14 : 0.07), base) : base,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: granted ? palette.accent : palette.glassBorder, width: granted ? 1.6 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.accent.withValues(alpha: palette.isDark ? 0.18 : 0.1),
                ),
                child: Icon(icon, color: palette.accent, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 1,
                        style: SkorxType.label(color: palette.ink, size: 18).copyWith(letterSpacing: 1.4),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(reason, style: TextStyle(color: palette.inkMuted, fontSize: 14, height: 1.3)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: switch (answer) {
                  PermissionAnswer.granted => Container(
                      key: const ValueKey('on'),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(color: palette.accent, shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
                    ),
                  PermissionAnswer.blocked => Text(
                      'Settings',
                      key: const ValueKey('blocked'),
                      style: TextStyle(color: palette.ink, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
                    ),
                  PermissionAnswer.notAsked => Container(
                      key: const ValueKey('ask'),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: palette.primaryFill, borderRadius: BorderRadius.circular(20)),
                      child: Text('Allow', style: TextStyle(color: palette.onPrimary, fontWeight: FontWeight.w700)),
                    ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
