import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/redirect.dart';
import '../../../app/theme/typography.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/widgets.dart';
import '../../onboarding/ui/onboarding_kit.dart';
import '../auth_controller.dart';
import '../auth_errors.dart';

/// Sign-in with a WhatsApp number. The same screen serves new and returning
/// players: the server tells them apart after the code is verified.
///
/// Other ways to sign in (Google, Apple, email) slot in under the WhatsApp
/// form; everything after sign-in only looks at the signed-in user, never at
/// how they signed in.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _mobile = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _mobile.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _digits => _mobile.text.replaceAll(RegExp(r'\D'), '');

  Future<void> _continue() async {
    // Ignore a second tap while the first request is in flight.
    if (_busy) return;
    if (!isValidIndianMobile(_digits)) {
      setState(() => _error = SignInProblem.invalidNumber.message);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sent = await ref.read(authControllerProvider.notifier).sendOtp(_digits);
      if (!mounted) return;
      context.push(Routes.verifyFor(_digits, resendAfter: sent.resendAfter));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = SignInProblem.from(e).$2);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    final ready = _digits.length == 10;
    final statement = OnboardType.statement(context, palette.ink);
    // Keyboard up: the compact layout, so everything fits above it.
    final compact = MediaQuery.viewInsetsOf(context).bottom > 80;

    return OnboardScaffold(
      courtTop: 0.7,
      leading: context.canPop()
          ? OnboardIconButton(icon: Icons.arrow_back_rounded, label: 'Back', onPressed: () => context.pop())
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // With the keyboard up the screen keeps its shape instead of
          // scrolling the logo away: the logo and headline shrink in place
          // and the supporting lines step aside.
          Reveal(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: compact ? 0 : 1),
              duration: _morph,
              curve: Curves.easeOutCubic,
              builder: (context, t, child) => Padding(
                padding: EdgeInsets.only(top: 4 + 4 * t, bottom: 28 + 8 * t),
                child: SizedBox(
                  // Scaled rather than resized, so the image is not decoded
                  // again on every frame.
                  height: 36 + 24 * t,
                  child: FittedBox(fit: BoxFit.contain, alignment: Alignment.centerLeft, child: child),
                ),
              ),
              child: const SkorxLogo(height: 60, glow: true),
            ),
          ),
          _Collapsible(
            visible: !compact,
            child: Reveal(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text('SIGN IN OR SIGN UP', style: OnboardType.eyebrow(palette.accent)),
              ),
            ),
          ),
          Reveal(
            delay: const Duration(milliseconds: 80),
            child: Semantics(
              header: true,
              label: 'Continue with WhatsApp',
              excludeSemantics: true,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: compact ? 30 : statement.fontSize!),
                duration: _morph,
                curve: Curves.easeOutCubic,
                builder: (context, size, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CONTINUE', style: statement.copyWith(fontSize: size)),
                    Text('WITH WHATSAPP', style: statement.copyWith(fontSize: size, color: palette.accentText)),
                  ],
                ),
              ),
            ),
          ),
          _Collapsible(
            visible: !compact,
            child: Reveal(
              delay: const Duration(milliseconds: 160),
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  "We'll send a verification code to your WhatsApp number.",
                  style: OnboardType.body(palette.inkMuted),
                ),
              ),
            ),
          ),
          AnimatedContainer(duration: _morph, curve: Curves.easeOutCubic, height: compact ? 18 : 28),
          Reveal(
            delay: const Duration(milliseconds: 240),
            child: _PhoneField(
              controller: _mobile,
              focusNode: _focus,
              enabled: !_busy,
              hasError: _error != null,
              onChanged: () => setState(() => _error = null),
              onSubmitted: _continue,
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _error == null
                ? const SizedBox(width: double.infinity)
                : Padding(padding: const EdgeInsets.only(top: 12), child: OnboardError(message: _error!)),
          ),
        ],
      ),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OnboardButton(
            key: const Key('signInPrimary'),
            label: 'Continue',
            icon: Icons.arrow_forward_rounded,
            busy: _busy,
            onPressed: ready ? _continue : null,
          ),
          _Collapsible(
            visible: !compact,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                'By continuing you agree to the SkorX Terms of Service and Privacy Policy. Your number is only used to sign you in.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, height: 1.4, color: palette.inkMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _morph = Duration(milliseconds: 260);

/// Folds [child] away (height and opacity together) when not [visible].
class _Collapsible extends StatelessWidget {
  const _Collapsible({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSize(
        duration: _morph,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topLeft,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: visible ? 1 : 0,
          child: visible ? child : const SizedBox(width: double.infinity),
        ),
      );
}

/// "+91 | 95865 45430" in one glass field, with a WhatsApp mark.
class _PhoneField extends StatelessWidget {
  const _PhoneField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.hasError,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool hasError;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final border = hasError ? palette.error : (focusNode.hasFocus ? palette.accent : palette.glassBorder);
        // The whole field, "+91" included, opens the keyboard.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? focusNode.requestFocus : null,
          child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 64,
          decoration: BoxDecoration(
            color: palette.isDark ? const Color(0x14FFFFFF) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border, width: focusNode.hasFocus || hasError ? 1.6 : 1),
          ),
          child: Row(
            children: [
              const SizedBox(width: 18),
              FaIcon(FontAwesomeIcons.whatsapp, size: 22, color: palette.isDark ? const Color(0xFF25D366) : const Color(0xFF128C7E)),
              const SizedBox(width: 10),
              Text('+91', style: SkorxType.score(22, color: palette.ink)),
              Container(
                width: 1,
                height: 28,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: palette.glassBorder,
              ),
              Expanded(
                child: TextField(
                  key: const Key('mobileField'),
                  controller: controller,
                  focusNode: focusNode,
                  enabled: enabled,
                  // No autofocus: the keyboard opens only when the player taps
                  // the field (this screen can sit under the launch animation).
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                  cursorColor: palette.accent,
                  style: SkorxType.score(24, color: palette.ink).copyWith(letterSpacing: 1.5),
                  decoration: InputDecoration(
                    hintText: 'WhatsApp number',
                    hintStyle: TextStyle(fontSize: 17, color: palette.inkFaint, letterSpacing: 0),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (_) => onChanged(),
                  onSubmitted: (_) => onSubmitted(),
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
        );
      },
    );
  }
}
