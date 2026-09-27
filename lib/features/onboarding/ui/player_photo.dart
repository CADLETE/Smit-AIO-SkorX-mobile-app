import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/theme/typography.dart';
import 'onboarding_kit.dart';

/// The player's photo in a volt ring, or their initials until there is one.
class PlayerPhoto extends StatelessWidget {
  const PlayerPhoto({super.key, required this.name, this.photoPath, this.size = 96});

  final String name;
  final String? photoPath;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    final path = photoPath;
    final initials = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.035),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: path != null ? palette.ball : palette.glassBorder, width: size * 0.02),
        boxShadow: path != null && palette.isDark ? [BoxShadow(color: palette.ball.withValues(alpha: 0.25), blurRadius: 30)] : null,
      ),
      child: ClipOval(
        child: path != null
            ? Image.file(
                File(path),
                fit: BoxFit.cover,
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
                errorBuilder: (_, _, _) => PhotoInitials(initials, size),
              )
            : PhotoInitials(initials, size),
      ),
    );
  }
}

class PhotoInitials extends StatelessWidget {
  const PhotoInitials(this.text, this.size, {super.key});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    return Container(
      color: palette.isDark ? const Color(0xFF131A24) : const Color(0xFFE8EEF6),
      alignment: Alignment.center,
      child: text.isEmpty
          ? Icon(Icons.person_rounded, size: size * 0.45, color: palette.inkFaint)
          : Text(text, style: SkorxType.score(size * 0.36, color: palette.ink)),
    );
  }
}

