import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import '../features/matches/data/match.dart' show sideLabel;
import '../features/player/ui/player_quick_view.dart';
import '../features/settings/app_settings.dart';
import 'tokens.dart';
import 'widgets.dart';

/// A player's picture wherever a match shows their name. The signed-in
/// player ("You") gets their own photo; everyone else shows initials until
/// photos come from the API.
class PlayerDp extends ConsumerWidget {
  const PlayerDp({super.key, required this.name, this.size = 28, this.edge});

  final String name;
  final double size;

  /// A thin ring in this colour, so overlapping pictures stay apart.
  final Color? edge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isMe = name == 'You' || (user != null && name == user.name);
    final photo = isMe ? ref.watch(appSettingsProvider.select((s) => s.photoPath)) : null;
    final display = isMe && user != null && user.name.isNotEmpty ? user.name : name;
    final fallback = SxAvatar(name: display, size: size);
    final pic = photo == null
        ? fallback
        : ClipOval(
            child: Image.file(
              File(photo),
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
              errorBuilder: (_, _, _) => fallback,
            ),
          );
    if (edge == null) return pic;
    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(shape: BoxShape.circle, color: edge),
      child: pic,
    );
  }
}

/// One side's pictures, overlapped for doubles.
class SideDps extends StatelessWidget {
  const SideDps({super.key, required this.names, this.size = 28, this.edge});

  final List<String> names;
  final double size;
  final Color? edge;

  @override
  Widget build(BuildContext context) {
    final ring = edge ?? context.sx.canvas;
    if (names.isEmpty) {
      return Container(
        width: size + 3,
        height: size + 3,
        decoration: BoxDecoration(shape: BoxShape.circle, color: context.sx.surfaceAlt),
        child: Icon(Icons.person_outline_rounded, size: size * 0.55, color: context.sx.inkFaint),
      );
    }
    final shown = names.take(2).toList();
    final step = size * 0.62;
    return SizedBox(
      width: size + 3 + step * (shown.length - 1),
      height: size + 3,
      child: Stack(
        children: [
          for (var i = shown.length - 1; i >= 0; i--)
            Positioned(left: step * i, child: PlayerDp(name: shown[i], size: size, edge: ring)),
        ],
      ),
    );
  }
}

/// Picture then name, for a list of players stacked one under another.
/// Tapping it opens the player's Quick View.
class PlayerTag extends StatelessWidget {
  const PlayerTag({super.key, required this.name, required this.style, this.size = 24, this.edge});

  final String name;
  final TextStyle style;
  final double size;
  final Color? edge;

  @override
  Widget build(BuildContext context) => PlayerTap(
        name: name,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PlayerDp(name: name, size: size, edge: edge),
            const SizedBox(width: Sx.s8),
            Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
          ],
        ),
      );
}

/// Makes a player's picture or name open their Quick View, wherever it is
/// drawn. Inside a tappable row, the name wins over the row.
class PlayerTap extends StatelessWidget {
  const PlayerTap({super.key, required this.name, required this.child});

  /// The name as the match has it ("You" for the signed-in player).
  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (name.trim().isEmpty) return child;
    return Semantics(
      button: true,
      label: 'View ${name == 'You' ? 'your' : '$name\'s'} player card',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showPlayerQuickView(context, name),
        child: child,
      ),
    );
  }
}

/// One side's names as a match row writes them ("You & Kamal", "Rahul &
/// Jay", "Vivek Rana"), each name opening its own player card.
class SideNames extends StatelessWidget {
  const SideNames({super.key, required this.names, required this.style, this.placeholder});

  final List<String> names;
  final TextStyle style;

  /// Shown, in italics, while the side is not known yet.
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) {
      return Text(placeholder ?? 'TBD',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: style.copyWith(fontStyle: FontStyle.italic));
    }
    if (names.length == 1) {
      return PlayerTap(
        name: names.first,
        child: Text(sideLabel(names), maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
      );
    }
    String short(String n) => n == 'You' ? n : n.split(' ').first;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, n) in names.indexed) ...[
          if (i > 0) Text(' & ', style: style),
          Flexible(
            child: PlayerTap(name: n, child: Text(short(n), maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
          ),
        ],
      ],
    );
  }
}
