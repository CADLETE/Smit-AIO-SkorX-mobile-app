import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/sample_persona.dart';
import '../../design/design.dart';
import '../../shared/format.dart';
import '../auth/auth_controller.dart';
import '../auth/data/auth_repository.dart';
import '../community/ui/community_rows.dart';
import '../matches/data/match_repository.dart';
import '../onboarding/app_tour.dart';
import '../onboarding/onboarding_controller.dart';
import '../player/data/player_repository.dart';
import '../player/player_pages.dart';
import '../settings/app_settings.dart';
import '../subscription/data/plans.dart';
import '../subscription/subscription_controller.dart';
import '../subscription/ui/plan_card.dart';
import '../subscription/ui/pro_widgets.dart';
import '../settings/match_defaults_sheet.dart';
import '../workspace/mode_switch.dart';

/// Who am I, and how do I control my account? Performance lives in My
/// Paddle; the ID card links there.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    return PlayerTabList(
      header: SxTitleBar(
        title: 'Account',
        actions: [
          SxIconAction(
            key: const Key('openSettings'),
            icon: Icons.settings_outlined,
            label: 'Settings',
            onTap: () => context.push('/player/settings'),
          ),
        ],
      ),
      children: [
        const _IdCard(),
        const Padding(padding: EdgeInsets.only(top: Sx.s12), child: ModeSwitch()),
        const SizedBox(height: Sx.section),
        const YourPlanCard(),
        const SizedBox(height: Sx.section),
        const CommunityRows(),
        const SizedBox(height: Sx.section),
        SxRows(
          title: 'Account',
          children: [
            SxRow(icon: Icons.edit_outlined, label: 'Edit profile', onTap: () => context.push('/player/edit-profile')),
            SxRow(
              key: const Key('subscriptionRow'),
              icon: Icons.bolt_rounded,
              label: 'Subscription',
              value: ref.watch(isProProvider) ? 'Pro' : 'Free',
              onTap: () => context.push('/player/subscription'),
            ),
            SxRow(
              key: const Key('billingRow'),
              icon: Icons.receipt_long_outlined,
              label: 'Billing & payments',
              onTap: () => context.push('/player/billing'),
            ),
            SxRow(icon: Icons.calendar_month_outlined, label: 'My bookings', onTap: () => context.push('/player/bookings')),
            SxRow(icon: Icons.emoji_events_outlined, label: 'My tournaments', onTap: () => context.push('/player/tournaments/mine')),
            SxRow(icon: Icons.notifications_none_rounded, label: 'Notifications', onTap: () => context.push('/player/notifications')),
            SxRow(icon: Icons.settings_outlined, label: 'Settings', subtitle: 'Theme, privacy, security', onTap: () => context.push('/player/settings')),
            SxRow(icon: Icons.help_outline_rounded, label: 'Help', onTap: () => _help(context)),
          ],
        ),
        const SizedBox(height: Sx.s24),
        SxRows(
          children: [
            SxRow(
              key: const Key('signOut'),
              icon: Icons.logout_rounded,
              label: 'Sign out',
              danger: true,
              onTap: () => _signOut(context, ref),
            ),
          ],
        ),
      ],
    );
  }

  static Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('Your matches and rating stay on your SkorX account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true) await ref.read(authControllerProvider.notifier).signOut();
  }
}

void _help(BuildContext context) => showSxSheet<void>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
        child: SxRows(
          title: 'Help',
          children: [
            SxRow(icon: FontAwesomeIcons.whatsapp.data, label: 'WhatsApp support', value: '+91 79 4000 0000'),
            const SxRow(icon: Icons.mail_outline_rounded, label: 'Email', value: 'help@skorx.app'),
            SxRow(icon: Icons.bug_report_outlined, label: 'Report a problem', onTap: () => Navigator.pop(ctx)),
          ],
        ),
      ),
    );

/// The player's sports identity card: inverted in both themes so it reads
/// as a card you would carry.
class _IdCard extends ConsumerWidget {
  const _IdCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final user = ref.watch(currentUserProvider)!;
    final o = ref.watch(playerOverviewProvider).value;
    final format = ref.watch(playerRecordProvider).value?.preferredFormat ?? PlayCategory.doubles;
    final city = o?.rankings.where((r) => r.scope == RankScope.city && r.category == format).firstOrNull;
    final hand = ref.watch(appSettingsProvider.select((s) => s.hand));
    final pro = ref.watch(isProProvider);
    // A city rank is a Local Ranking: Pro only.
    final rankShown = ref.watch(canAccessProvider(ProFeature.localRanking));
    const fg = Colors.white;
    final muted = Colors.white.withValues(alpha: 0.72);
    return Semantics(
      button: true,
      label: '${user.name}, SkorX Rating ${o?.rating == null ? 'none yet' : ratingText(o!.rating!)}${user.xCode == null ? '' : ', X code ${user.xCode}'}. Open My Paddle',
      excludeSemantics: true,
      child: Tappable(
        key: const Key('idCard'),
        onTap: () => context.go('/player/paddle'),
        radius: Sx.radiusLg,
        child: SxHeroCard(
          padding: const EdgeInsets.all(Sx.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('SKORX PLAYER', style: SxType.label(muted, size: 12))),
                ],
              ),
              const SizedBox(height: Sx.s20),
              Row(
                children: [
                  PlayerDp(name: user.name, size: 64, edge: c.voltFill),
                  const SizedBox(width: Sx.s16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.name.toUpperCase(), maxLines: 2, style: SxType.title(fg, size: 26)),
                        // Pro sits with the name, clear of the card's ball in the corner.
                        if (pro) const Padding(padding: EdgeInsets.only(top: 4, bottom: 2), child: ProBadge(key: Key('idCardPro'), size: 11)),
                        const SizedBox(height: 2),
                        Text(
                          [o?.arc?.band.label ?? 'New player', if (hand != null) '$hand-handed', if (user.phone != null) formatPhone(user.phone!)].join(' · '),
                          style: SxType.caption(muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Sx.s20),
              SizedBox(height: 8, child: NetLine(color: Colors.white.withValues(alpha: 0.3), markColor: c.voltFill)),
              const SizedBox(height: Sx.s16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: _cardStat(o?.rating == null ? '—' : ratingText(o!.rating!), 'SkorX Rating', fg, muted)),
                  const SizedBox(width: Sx.s8),
                  Expanded(
                    child: rankShown
                        ? _cardStat(city == null ? '—' : '#${city.rank}', city == null ? 'City rank' : '${city.place} rank', fg, muted)
                        : _lockedStat('City rank', fg, muted),
                  ),
                  if (user.xCode != null) ...[
                    const SizedBox(width: Sx.s8),
                    _XCodeBox(code: user.xCode!),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _lockedStat(String l, Color fg, Color muted) => Column(
        key: const Key('idCardRankLocked'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 29,
            child: Row(children: [
              Icon(Icons.lock_outline_rounded, color: muted, size: 18),
              const SizedBox(width: 6),
              const ProBadge(size: 10),
            ]),
          ),
          const SizedBox(height: 2),
          Text(l.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.label(muted, size: 10.5)),
        ],
      );

  static Widget _cardStat(String v, String l, Color fg, Color muted) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(child: Text(v, style: SxType.number(24, fg, weight: FontWeight.w800))),
          const SizedBox(height: 2),
          Text(l.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: SxType.label(muted, size: 10.5)),
        ],
      );
}

/// The player's X code, highlighted on the ID card: the code they read out
/// to be found or added to a match.
class _XCodeBox extends StatelessWidget {
  const _XCodeBox({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Container(
      key: const Key('xCodeBox'),
      padding: const EdgeInsets.symmetric(horizontal: Sx.s16, vertical: Sx.s8),
      decoration: BoxDecoration(color: c.voltFill, borderRadius: BorderRadius.circular(Sx.s8)),
      child: Text.rich(
        TextSpan(
          children: [
            // The "X·" in deep olive, so the code itself stands apart.
            TextSpan(text: 'X·', style: SxType.number(22, const Color(0xFF4A6B00), weight: FontWeight.w900)),
            TextSpan(text: code),
          ],
        ),
        style: SxType.number(22, c.onVolt, weight: FontWeight.w800),
      ),
    );
  }
}

/// Settings, in the order people look for things.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final s = ref.watch(appSettingsProvider);
    final ctl = ref.read(appSettingsProvider.notifier);
    final user = ref.watch(currentUserProvider);

    Future<void> pickVisibility(String title, Visibility3 current, void Function(Visibility3) set) async {
      final v = await showSxSheet<Visibility3>(
        context,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
          child: SxRows(
            title: title,
            children: [
              for (final v in Visibility3.values)
                SxRow(
                  label: v.label,
                  trailing: v == current ? Icon(Icons.check_rounded, color: ctx.sx.ink) : null,
                  onTap: () => Navigator.pop(ctx, v),
                ),
            ],
          ),
        ),
      );
      if (v != null) set(v);
    }

    Widget toggle(String key, String label) => SxRow(
          label: label,
          trailing: Switch(value: s.notify[key] ?? false, onChanged: (on) => ctl.setNotify(key, on)),
        );

    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(onBack: () => context.canPop() ? context.pop() : context.go('/player/profile')),
              const SxTitleBar(title: 'Settings'),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s48),
                  children: [
                    SxRows(title: 'Account', children: [
                      SxRow(label: 'Edit profile', onTap: () => context.push('/player/edit-profile')),
                      SxRow(label: 'Phone', value: user?.phone == null ? '—' : formatPhone(user!.phone!)),
                      SxRow(label: 'Email', value: user?.email ?? 'Not added'),
                    ]),
                    const SizedBox(height: Sx.section),
                    SxRows(title: 'Scoring', children: [
                      SxRow(
                        key: const Key('matchDefaults'),
                        icon: Icons.tune_rounded,
                        label: 'Default match settings',
                        subtitle: describeMatchDefaults(s),
                        onTap: () => showSxSheet<void>(context, builder: (_) => const MatchDefaultsSheet()),
                      ),
                    ]),
                    const SizedBox(height: Sx.section),
                    const SxSection('App'),
                    Text('Theme', style: SxType.heading(c.ink, size: 16).copyWith(fontWeight: FontWeight.w500)),
                    const SizedBox(height: Sx.s12),
                    _ThemePicker(
                      mode: s.themeMode,
                      onChanged: (m) => ctl.update((s) => s.copyWith(themeMode: m)),
                    ),
                    const SizedBox(height: Sx.s8),
                    SxRows(children: [
                      SxRow(label: 'Language', value: s.language),
                      SxRow(label: 'Home city', value: s.homeCity ?? 'Not set', onTap: () => context.push('/player/edit-profile')),
                    ]),
                    const SizedBox(height: Sx.section),
                    SxRows(title: 'Notifications', children: [
                      toggle('matchReminders', 'Match starting'),
                      toggle('results', 'Results and rating changes'),
                      toggle('tournamentUpdates', 'Tournament updates'),
                      toggle('bookings', 'Court bookings'),
                      toggle('achievements', 'Achievements'),
                      toggle('announcements', 'Organiser announcements'),
                    ]),
                    const SizedBox(height: Sx.section),
                    SxRows(title: 'Privacy', children: [
                      SxRow(
                        label: 'Profile visibility',
                        value: s.profileVisibility.label,
                        onTap: () => pickVisibility('Profile visibility', s.profileVisibility,
                            (v) => ctl.update((s) => s.copyWith(profileVisibility: v))),
                      ),
                      SxRow(
                        label: 'Match visibility',
                        value: s.matchVisibility.label,
                        onTap: () => pickVisibility('Match visibility', s.matchVisibility,
                            (v) => ctl.update((s) => s.copyWith(matchVisibility: v))),
                      ),
                      SxRow(
                        label: 'Show me in rankings',
                        trailing: Switch(
                          value: s.rankingVisible,
                          onChanged: (on) => ctl.update((s) => s.copyWith(rankingVisible: on)),
                        ),
                      ),
                    ]),
                    const SizedBox(height: Sx.section),
                    const SxRows(title: 'Security', children: [
                      SxRow(label: 'Sign-in', value: 'WhatsApp code'),
                      SxRow(label: 'Devices', value: 'This phone'),
                    ]),
                    const SizedBox(height: Sx.section),
                    SxRows(title: 'Support', children: [
                      SxRow(
                        key: const Key('replayTour'),
                        label: 'Take the app tour',
                        subtitle: 'A one-minute walk through SkorX',
                        onTap: () {
                          ref.read(appTourProvider.notifier).start();
                          context.go('/player/home');
                        },
                      ),
                      SxRow(label: 'Help', onTap: () => _help(context)),
                      SxRow(label: 'Contact us', value: 'help@skorx.app'),
                      SxRow(label: 'Report a problem', onTap: () => _help(context)),
                    ]),
                    const SizedBox(height: Sx.section),
                    const SxRows(title: 'About', children: [
                      SxRow(label: 'Terms of service'),
                      SxRow(label: 'Privacy policy'),
                      SxRow(label: 'About SkorX', value: 'Version 1.0.0'),
                    ]),
                    if (kDebugMode) ...[
                      const SizedBox(height: Sx.section),
                      const _DeveloperSection(),
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

class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    const options = [
      (ThemeMode.system, 'System', Icons.brightness_auto_outlined),
      (ThemeMode.light, 'Light', Icons.light_mode_outlined),
      (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
    ];
    return Row(
      children: [
        for (final (m, label, icon) in options)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: m == ThemeMode.dark ? 0 : Sx.s8),
              child: Semantics(
                button: true,
                selected: m == mode,
                label: label,
                excludeSemantics: true,
                child: Tappable(
                  key: Key('theme-$label'),
                  onTap: () => onChanged(m),
                  child: AnimatedContainer(
                    duration: Sx.fast,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: m == mode ? c.brand : c.card,
                      borderRadius: BorderRadius.circular(Sx.radius),
                      border: Border.all(color: m == mode ? Colors.transparent : c.cardEdge),
                      boxShadow: m == mode ? c.glowOf(c.voltFill, strength: 0.6) : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, color: m == mode ? c.onVolt : c.ink, size: 22),
                        const SizedBox(height: 6),
                        Text(label, style: SxType.label(m == mode ? c.onVolt : c.ink, size: 13)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Debug builds only: switch the sample player to check first-run states.
class _DeveloperSection extends ConsumerWidget {
  const _DeveloperSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final persona = ref.watch(samplePersonaProvider);
    return SxRows(
      title: 'Developer · sample player',
      children: [
        for (final p in SamplePersona.values)
          SxRow(
            key: Key('persona-${p.name}'),
            label: p.label,
            subtitle: p.description,
            trailing: p == persona ? Icon(Icons.check_rounded, color: c.ink) : null,
            onTap: () => ref.read(samplePersonaProvider.notifier).set(p),
          ),
        SxRow(
          key: const Key('replayFirstLaunch'),
          label: 'Replay first launch',
          subtitle: 'Signs out and shows the introduction. Your own number signs back in as you; any other number is a new player.',
          onTap: () async {
            await ref.read(onboardingControllerProvider.notifier).reset();
            await ref.read(authControllerProvider.notifier).signOut();
          },
        ),
      ],
    );
  }
}

/// The player's picture, big, with a camera badge: tap to change it.
class _PhotoEditor extends ConsumerWidget {
  const _PhotoEditor({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.sx;
    final hasPhoto = ref.watch(appSettingsProvider.select((s) => s.photoPath != null));
    return Center(
      child: Semantics(
        button: true,
        label: hasPhoto ? 'Change profile photo' : 'Add profile photo',
        excludeSemantics: true,
        child: Tappable(
          key: const Key('changePhoto'),
          onTap: onTap,
          radius: 60,
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: c.brand,
                      boxShadow: c.glowOf(c.voltFill, strength: 0.7),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: c.canvas),
                      child: const PlayerDp(name: 'You', size: 108),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 4,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: c.cool,
                        border: Border.all(color: c.canvas, width: 3),
                      ),
                      child: const Icon(Icons.photo_camera_rounded, size: 17, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Sx.s12),
              Text(
                hasPhoto ? 'Change photo' : 'Add a photo',
                style: SxType.caption(c.isDark ? c.cyan : c.blue, size: 13.5).copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Player details go to the server (`PATCH /me/profile`); hand and playing
/// style stay on the phone until the API has fields for them.
class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  late final _name = TextEditingController(text: ref.read(currentUserProvider)?.name ?? '');
  late final _city = TextEditingController(text: ref.read(appSettingsProvider).homeCity ?? '');
  String? _gender;
  DateTime? _dateOfBirth;
  late String? _hand = ref.read(appSettingsProvider).hand;
  late String? _style = ref.read(appSettingsProvider).playStyle;
  bool _busy = false;
  String? _error;

  static const _genders = {'male': 'Male', 'female': 'Female', 'other': 'Other'};
  static const _styles = ['All-court', 'Dinker', 'Banger', 'Net rusher'];

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().length >= 2;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 4),
      helpText: 'Date of birth',
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  /// Camera, gallery or remove. The photo is saved straight away: it lives
  /// on this phone until the API takes uploads, so there is nothing to wait
  /// for.
  Future<void> _changePhoto() async {
    final hasPhoto = ref.read(appSettingsProvider).photoPath != null;
    final choice = await showSxSheet<String>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(Sx.gutter, 0, Sx.gutter, Sx.s24),
        child: SxRows(
          title: 'Profile photo',
          children: [
            SxRow(
              key: const Key('photoCamera'),
              icon: Icons.photo_camera_outlined,
              label: 'Take a photo',
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            SxRow(
              key: const Key('photoGallery'),
              icon: Icons.photo_library_outlined,
              label: 'Choose from gallery',
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (hasPhoto)
              SxRow(
                key: const Key('photoRemove'),
                icon: Icons.delete_outline_rounded,
                label: 'Remove photo',
                danger: true,
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final settings = ref.read(appSettingsProvider.notifier);
    final previous = ref.read(appSettingsProvider).photoPath;
    if (choice == 'remove') {
      settings.update((s) => s.copyWith(clearPhoto: true));
      if (previous != null) File(previous).delete().ignore();
      return;
    }
    final source = choice == 'camera' ? ImageSource.camera : ImageSource.gallery;
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
      settings.update((s) => s.copyWith(photoPath: saved.path));
      if (previous != null) File(previous).delete().ignore();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile photo updated')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(source == ImageSource.camera ? "Couldn't open the camera." : "Couldn't open your photos."),
        ),
      );
    }
  }

  Future<void> _save() async {
    if (_busy || !_valid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final city = _city.text.trim();
    try {
      await ref.read(authControllerProvider.notifier).completeProfile(
            ProfileUpdate(name: _name.text.trim(), city: city.isEmpty ? null : city, gender: _gender, dateOfBirth: _dateOfBirth),
          );
      ref.read(appSettingsProvider.notifier).update(
            (s) => s.copyWith(hand: _hand, playStyle: _style, homeCity: city.isEmpty ? null : city),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved')));
      context.canPop() ? context.pop() : context.go('/player/profile');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    Widget choices(List<(String, String)> options, String? value, ValueChanged<String> set) => Wrap(
          spacing: Sx.s8,
          runSpacing: Sx.s8,
          children: [for (final (v, l) in options) SxChip(label: l, selected: v == value, onTap: () => set(v))],
        );
    return Scaffold(
      body: SafeArea(
        child: SxWidth(
          child: Column(
            children: [
              SxBackBar(onBack: () => context.canPop() ? context.pop() : context.go('/player/profile')),
              const SxTitleBar(title: 'Edit profile'),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s24),
                  children: [
                    _PhotoEditor(onTap: _changePhoto),
                    const SizedBox(height: Sx.s24),
                    const SxSection('Name'),
                    TextField(
                      key: const Key('editName'),
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: Sx.s24),
                    const SxSection('Home city'),
                    TextField(controller: _city, textCapitalization: TextCapitalization.words),
                    const SizedBox(height: Sx.s24),
                    const SxSection('Gender'),
                    choices([for (final e in _genders.entries) (e.key, e.value)], _gender, (v) => setState(() => _gender = v)),
                    const SizedBox(height: Sx.s24),
                    const SxSection('Date of birth'),
                    SxRow(
                      icon: Icons.cake_outlined,
                      label: _dateOfBirth == null ? 'Add date of birth' : longDate(_dateOfBirth!),
                      onTap: _pickDate,
                    ),
                    const SizedBox(height: Sx.s24),
                    const SxSection('Playing hand'),
                    choices(const [('Right', 'Right'), ('Left', 'Left')], _hand, (v) => setState(() => _hand = v)),
                    const SizedBox(height: Sx.s24),
                    const SxSection('Playing style'),
                    choices([for (final s in _styles) (s, s)], _style, (v) => setState(() => _style = v)),
                    if (_error != null) ...[
                      const SizedBox(height: Sx.s16),
                      Text(_error!, style: SxType.body(c.live, size: 14)),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s8, Sx.gutter, Sx.s16),
                child: SxButton(key: const Key('saveProfileEdit'), label: 'Save', busy: _busy, onPressed: _valid ? _save : null),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
