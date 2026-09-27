import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/casual_match/handover/handover_prompt.dart';
import '../features/settings/app_settings.dart';
import '../features/workspace/workspace_controller.dart';
import 'intro/skorx_intro.dart';
import 'routing/router.dart';
import 'theme/app_theme.dart';

class SkorxApp extends ConsumerWidget {
  const SkorxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // The accent follows the open workspace: cyan for Player, lime for
    // Organizer.
    final accent = ref.watch(workspaceControllerProvider.select((s) => s.current.accent));

    return MaterialApp.router(
      title: 'SkorX',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      // The opening animation plays over the first route while the session
      // restores underneath.
      // A scoring request from another phone can arrive on any screen.
      builder: (context, child) =>
          SkorxIntroGate(child: IncomingHandoverLayer(child: child ?? const SizedBox.shrink())),
      theme: buildSkorxTheme(brightness: Brightness.light, accent: accent),
      darkTheme: buildSkorxTheme(brightness: Brightness.dark, accent: accent),
      // Dark is the SkorX hero look; light reads better on sunny outdoor
      // courts. Chosen in Settings › Appearance.
      themeMode: ref.watch(appSettingsProvider.select((s) => s.themeMode)),
    );
  }
}
