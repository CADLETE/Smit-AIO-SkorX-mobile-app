import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/redirect.dart';
import '../../../design/design.dart';
import '../../../shared/widgets.dart';
import '../../explore/explore_page.dart';
import 'onboarding_kit.dart';

/// "Explore SkorX" before signing in: the same tournaments and courts a
/// player browses, with sign-in one tap away. Opening anything that needs
/// an account (a tournament, a booking) goes to sign-in.
class GuestExplorePage extends StatelessWidget {
  const GuestExplorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.sx;
    return Scaffold(
      backgroundColor: c.canvas,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Sx.s8, Sx.s8, Sx.gutter, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => context.go(Routes.welcome),
                    icon: Icon(Icons.arrow_back_rounded, color: c.ink),
                  ),
                  const SkorxLogo(height: 34),
                  const SizedBox(width: Sx.s8),
                  Text('GUEST', style: SxType.label(c.inkMuted)),
                  const Spacer(),
                  TextButton(
                    key: const Key('guestSignIn'),
                    onPressed: () => context.go(Routes.login),
                    child: Text('Sign in', style: TextStyle(color: c.ink, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(context: context, removeTop: true, child: const ExploreBrowser()),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Sx.gutter, Sx.s12, Sx.gutter, Sx.s12),
              child: OnboardButton(
                key: const Key('guestGetStarted'),
                label: 'Create your player profile',
                onPressed: () => context.go(Routes.login),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
