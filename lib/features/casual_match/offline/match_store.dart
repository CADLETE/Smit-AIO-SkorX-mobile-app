import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/auth_controller.dart';
import '../local_match.dart';

/// Where matches scored on this phone live (docs/OFFLINE-SCORING.md §2.1):
/// one document per match, written atomically, so a crash, a flat battery
/// or one damaged file never costs more than that one write, and never
/// another match.
final matchStoreProvider = Provider<MatchStore>((ref) {
  final prefs = ref.watch(preferencesProvider);
  // Widget tests run in fake time, where real file I/O never completes.
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return MatchStore(prefs, directory: () async => throw UnsupportedError('No files under flutter test.'));
  }
  return MatchStore(prefs);
});

class MatchStore {
  MatchStore(this._prefs, {Future<Directory> Function()? directory}) : _directory = directory ?? _defaultDirectory;

  final SharedPreferencesAsync _prefs;
  final Future<Directory> Function() _directory;

  static Future<Directory> _defaultDirectory() async => Directory('${(await getApplicationSupportDirectory()).path}/skorx_matches');

  /// Where the store kept matches before it existed.
  static const legacyActiveKey = 'skorx.activeMatch';
  static const legacyPlayedKey = 'skorx.playedMatches';

  static const _active = 'active';
  static const _played = 'played';

  late final Future<_Backend> _backend = _open();

  /// Documents that could not be read and were set aside, this session.
  int quarantined = 0;

  Future<_Backend> _open() async {
    _Backend backend;
    try {
      final dir = await _directory();
      await Directory('${dir.path}/$_played').create(recursive: true);
      backend = _FileBackend(dir);
    } catch (_) {
      // No file system to use (tests, some desktop builds): one preference per match.
      backend = _PrefsBackend(_prefs);
    }
    await _migrate(backend);
    return backend;
  }

  /// Moves matches saved by earlier versions into the store. The old keys
  /// are removed only once every match is written.
  Future<void> _migrate(_Backend backend) async {
    try {
      final active = await _prefs.getString(legacyActiveKey);
      if (active != null) {
        if (await backend.read(_active) == null) await backend.write(_active, active);
        await _prefs.remove(legacyActiveKey);
      }
      final played = await _prefs.getString(legacyPlayedKey);
      if (played != null) {
        List<dynamic> list;
        try {
          list = jsonDecode(played) as List<dynamic>;
        } catch (_) {
          // Keep the unreadable blob aside instead of losing it.
          await backend.write('legacy-played.corrupt', played);
          list = const [];
        }
        for (final item in list) {
          final id = item is Map<String, dynamic> ? item['id'] : null;
          if (id is String) await backend.write('$_played/$id', jsonEncode(item));
        }
        await _prefs.remove(legacyPlayedKey);
      }
    } catch (e) {
      debugPrint('Match store migration: $e');
    }
  }

  LocalMatch? _parse(String? raw) {
    if (raw == null) return null;
    return LocalMatch.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<LocalMatch?> readActive() async {
    final backend = await _backend;
    try {
      return _parse(await backend.read(_active));
    } catch (_) {
      await backend.quarantine(_active);
      quarantined++;
      return null;
    }
  }

  Future<void> writeActive(LocalMatch match) async => (await _backend).write(_active, jsonEncode(match.toJson()));

  Future<void> clearActive() async => (await _backend).delete(_active);

  /// Every finished match on this phone, in no particular order. One that
  /// cannot be read is set aside (`.corrupt`) and the rest still load.
  Future<List<LocalMatch>> readPlayed() async {
    final backend = await _backend;
    final out = <LocalMatch>[];
    for (final name in await backend.list(_played)) {
      try {
        final m = _parse(await backend.read(name));
        if (m != null) out.add(m);
      } catch (_) {
        await backend.quarantine(name);
        quarantined++;
      }
    }
    return out;
  }

  Future<void> writePlayed(LocalMatch match) async => (await _backend).write('$_played/${match.id}', jsonEncode(match.toJson()));

  Future<void> removePlayed(String id) async => (await _backend).delete('$_played/$id');

  /// Keeps [match] as it was before a sync conflict replaced it.
  Future<void> archive(LocalMatch match, String reason) async =>
      (await _backend).write('superseded-${match.id}-${DateTime.now().millisecondsSinceEpoch}.$reason', jsonEncode(match.toJson()));
}

abstract class _Backend {
  Future<String?> read(String name);
  Future<void> write(String name, String content);
  Future<void> delete(String name);

  /// Names under [folder], e.g. `played/<id>`.
  Future<List<String>> list(String folder);

  /// Sets an unreadable document aside where support can still find it.
  Future<void> quarantine(String name);
}

/// A file per document. Every write goes to `<name>.json.tmp`, is flushed to
/// disk, then renamed over `<name>.json`: rename is atomic, so the file is
/// always the old version or the new one, never half of each.
class _FileBackend implements _Backend {
  _FileBackend(this._dir);

  final Directory _dir;

  /// Writes to the same document go one after another.
  final _queues = <String, Future<void>>{};

  File _file(String name) => File('${_dir.path}/$name.json');
  File _tmp(String name) => File('${_dir.path}/$name.json.tmp');

  @override
  Future<String?> read(String name) async {
    final file = _file(name);
    if (await file.exists()) return file.readAsString();
    // Died between writing and renaming: the temporary copy is complete only
    // if it parses, which the caller checks.
    final tmp = _tmp(name);
    return await tmp.exists() ? tmp.readAsString() : null;
  }

  @override
  Future<void> write(String name, String content) => _serial(name, () async {
        final tmp = _tmp(name);
        await tmp.writeAsString(content, flush: true);
        try {
          await tmp.rename(_file(name).path);
        } on FileSystemException {
          // Windows cannot rename over an existing file.
          final target = _file(name);
          if (await target.exists()) await target.delete();
          await tmp.rename(target.path);
        }
      });

  @override
  Future<void> delete(String name) => _serial(name, () async {
        for (final f in [_file(name), _tmp(name)]) {
          if (await f.exists()) await f.delete();
        }
      });

  @override
  Future<List<String>> list(String folder) async {
    final dir = Directory('${_dir.path}/$folder');
    if (!await dir.exists()) return const [];
    final names = <String>{};
    await for (final f in dir.list()) {
      final base = f.uri.pathSegments.last;
      if (base.endsWith('.json')) names.add('$folder/${base.substring(0, base.length - 5)}');
      if (base.endsWith('.json.tmp')) names.add('$folder/${base.substring(0, base.length - 9)}');
    }
    return names.toList();
  }

  @override
  Future<void> quarantine(String name) => _serial(name, () async {
        final stamp = DateTime.now().millisecondsSinceEpoch;
        for (final f in [_file(name), _tmp(name)]) {
          if (await f.exists()) await f.rename('${f.path}.$stamp.corrupt');
        }
      });

  Future<void> _serial(String name, Future<void> Function() body) {
    final next = (_queues[name] ?? Future<void>.value()).then((_) => body());
    _queues[name] = next.catchError((_) {});
    return next;
  }
}

/// One preference per document, for platforms without files.
class _PrefsBackend implements _Backend {
  _PrefsBackend(this._prefs);

  final SharedPreferencesAsync _prefs;
  static const _prefix = 'skorx.store.';

  @override
  Future<String?> read(String name) => _prefs.getString('$_prefix$name');

  @override
  Future<void> write(String name, String content) => _prefs.setString('$_prefix$name', content);

  @override
  Future<void> delete(String name) => _prefs.remove('$_prefix$name');

  @override
  Future<List<String>> list(String folder) async => [
        for (final k in await _prefs.getKeys())
          if (k.startsWith('$_prefix$folder/') && !k.endsWith('.corrupt')) k.substring(_prefix.length),
      ];

  @override
  Future<void> quarantine(String name) async {
    final raw = await read(name);
    if (raw != null) await _prefs.setString('$_prefix$name.${DateTime.now().millisecondsSinceEpoch}.corrupt', raw);
    await delete(name);
  }
}
