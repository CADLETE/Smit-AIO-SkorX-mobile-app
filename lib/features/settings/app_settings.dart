import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';

enum Visibility3 {
  everyone('Everyone'),
  players('SkorX players'),
  onlyMe('Only me');

  const Visibility3(this.label);
  final String label;
}

/// Device-side preferences. They move to `PATCH /me/preferences` when the
/// API has it; until then they stay on this phone.
class AppSettings {
  const AppSettings({
    // Dark is the SkorX look; players can pick light or system in Settings.
    this.themeMode = ThemeMode.dark,
    this.notify = const {
      'matchReminders': true,
      'tournamentUpdates': true,
      'results': true,
      'bookings': true,
      'achievements': true,
      'announcements': false,
    },
    this.profileVisibility = Visibility3.everyone,
    this.matchVisibility = Visibility3.players,
    this.rankingVisible = true,
    this.language = 'English',
    this.hand,
    this.playStyle,
    this.homeCity,
    this.level,
    this.formats = const [],
    this.photoPath,
  });

  final ThemeMode themeMode;
  final Map<String, bool> notify;
  final Visibility3 profileVisibility;
  final Visibility3 matchVisibility;
  final bool rankingVisible;
  final String language;

  /// "Right" or "Left".
  final String? hand;

  /// "All-court", "Dinker", "Banger", "Net rusher".
  final String? playStyle;
  final String? homeCity;

  /// A PlayerLevel name, from sign-up.
  final String? level;

  /// "singles" and/or "doubles", from sign-up.
  final List<String> formats;

  /// The player photo, kept on this phone until the API takes uploads.
  final String? photoPath;

  AppSettings copyWith({
    ThemeMode? themeMode,
    Map<String, bool>? notify,
    Visibility3? profileVisibility,
    Visibility3? matchVisibility,
    bool? rankingVisible,
    String? language,
    String? hand,
    String? playStyle,
    String? homeCity,
    String? level,
    List<String>? formats,
    String? photoPath,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        notify: notify ?? this.notify,
        profileVisibility: profileVisibility ?? this.profileVisibility,
        matchVisibility: matchVisibility ?? this.matchVisibility,
        rankingVisible: rankingVisible ?? this.rankingVisible,
        language: language ?? this.language,
        hand: hand ?? this.hand,
        playStyle: playStyle ?? this.playStyle,
        homeCity: homeCity ?? this.homeCity,
        level: level ?? this.level,
        formats: formats ?? this.formats,
        photoPath: photoPath ?? this.photoPath,
      );

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'notify': notify,
        'profileVisibility': profileVisibility.name,
        'matchVisibility': matchVisibility.name,
        'rankingVisible': rankingVisible,
        'language': language,
        'hand': hand,
        'playStyle': playStyle,
        'homeCity': homeCity,
        'level': level,
        'formats': formats,
        'photoPath': photoPath,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    const defaults = AppSettings();
    return AppSettings(
      themeMode: ThemeMode.values.asNameMap()[json['themeMode']] ?? defaults.themeMode,
      notify: {...defaults.notify, ...((json['notify'] as Map<String, dynamic>?) ?? const {}).cast<String, bool>()},
      profileVisibility: Visibility3.values.asNameMap()[json['profileVisibility']] ?? defaults.profileVisibility,
      matchVisibility: Visibility3.values.asNameMap()[json['matchVisibility']] ?? defaults.matchVisibility,
      rankingVisible: json['rankingVisible'] as bool? ?? true,
      language: json['language'] as String? ?? 'English',
      hand: json['hand'] as String?,
      playStyle: json['playStyle'] as String?,
      homeCity: json['homeCity'] as String?,
      level: json['level'] as String?,
      formats: ((json['formats'] as List<dynamic>?) ?? const []).cast<String>(),
      photoPath: json['photoPath'] as String?,
    );
  }
}

final appSettingsProvider = NotifierProvider<AppSettingsController, AppSettings>(AppSettingsController.new);

class AppSettingsController extends Notifier<AppSettings> {
  static const _key = 'skorx.settings';

  @override
  AppSettings build() {
    Future.microtask(_load);
    return const AppSettings();
  }

  Future<void> _load() async {
    try {
      final raw = await ref.read(preferencesProvider).getString(_key);
      if (raw != null) state = AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Unreadable saved settings: keep the defaults.
    }
  }

  void update(AppSettings Function(AppSettings) change) {
    state = change(state);
    ref.read(preferencesProvider).setString(_key, jsonEncode(state.toJson()));
  }

  void setNotify(String key, bool on) => update((s) => s.copyWith(notify: {...s.notify, key: on}));
}
