import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/typography.dart';
import '../../../core/api/api_exception.dart';
import '../../onboarding/ui/onboarding_kit.dart';
import '../auth_controller.dart';
import '../auth_errors.dart';

/// The 6-digit code sent on WhatsApp. A complete code verifies itself; the
/// router then opens profile setup for a new number or welcomes back an
/// existing player.
class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({super.key, required this.mobile, this.resendAfter = const Duration(seconds: 30)});

  final String mobile;
  final Duration resendAfter;

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> with SingleTickerProviderStateMixin {
  static const _length = 6;
  final _code = TextEditingController();
  final _focus = FocusNode();
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  bool _busy = false;
  SignInProblem? _problem;
  String? _error;

  /// "New code sent", shown where errors go until the player types.
  bool _resent = false;
  int _resendIn = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startResendTimer(widget.resendAfter.inSeconds);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shake.dispose();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy || _code.text.length != _length) return;
    setState(() {
      _busy = true;
      _error = null;
      _problem = null;
    });
    try {
      // On success the router moves on; nothing else to do here.
      await ref.read(authControllerProvider.notifier).verifyOtp(widget.mobile, _code.text);
      TextInput.finishAutofillContext();
    } on ApiException catch (e) {
      if (!mounted) return;
      final (problem, message) = SignInProblem.from(e);
      setState(() {
        _problem = problem;
        _error = message;
      });
      // A network failure keeps the code so Retry can send it again.
      if (problem != SignInProblem.network) {
        _code.clear();
        if (!reduceMotion(context)) _shake.forward(from: 0);
        HapticFeedback.heavyImpact();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _problem = null;
    });
    try {
      final sent = await ref.read(authControllerProvider.notifier).sendOtp(widget.mobile);
      if (!mounted) return;
      _code.clear();
      _startResendTimer(sent.resendAfter.inSeconds);
      _focus.requestFocus();
      setState(() => _resent = true);
    } on ApiException catch (e) {
      if (mounted) {
        final (problem, message) = SignInProblem.from(e);
        setState(() {
          _problem = problem;
          _error = message;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startResendTimer(int seconds) {
    _timer?.cancel();
    setState(() => _resendIn = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendIn <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendIn = 0);
        return;
      }
      setState(() => _resendIn--);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    // An expired code can be replaced at once, whatever the timer says.
    final canResend = !_busy && (_resendIn == 0 || (_problem?.needsNewCode ?? false));

    return OnboardScaffold(
      courtTop: 0.72,
      ball: false,
      leading: OnboardIconButton(
        icon: Icons.arrow_back_rounded,
        label: 'Change number',
        onPressed: _busy ? null : () => context.pop(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Reveal(child: Text('STEP 2 OF 2', style: OnboardType.eyebrow(palette.accent))),
          const SizedBox(height: 14),
          Reveal(
            delay: const Duration(milliseconds: 80),
            child: Semantics(
              header: true,
              child: Text('VERIFY YOUR NUMBER', style: OnboardType.statement(context, palette.ink, max: 46)),
            ),
          ),
          const SizedBox(height: 14),
          Reveal(
            delay: const Duration(milliseconds: 160),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Enter the 6-digit code sent to your WhatsApp '),
                  TextSpan(
                    // Non-breaking space keeps "+91" and the number together.
                    text: '+91 ${formatIndianMobile(widget.mobile).replaceAll(' ', ' ')}',
                    style: TextStyle(color: palette.ink, fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
              style: OnboardType.body(palette.inkMuted),
            ),
          ),
          const SizedBox(height: 28),
          Reveal(
            delay: const Duration(milliseconds: 240),
            child: AnimatedBuilder(
              animation: _shake,
              builder: (context, child) => Transform.translate(
                offset: Offset(math.sin(_shake.value * math.pi * 6) * 10 * (1 - _shake.value), 0),
                child: child,
              ),
              child: _CodeBoxes(
                controller: _code,
                focusNode: _focus,
                length: _length,
                readOnly: _busy,
                error: _error != null && _problem != SignInProblem.network,
                onChanged: (value) {
                  setState(() {
                    _error = null;
                    _resent = false;
                  });
                  if (value.length == _length) _verify();
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 28,
            child: _busy
                ? Row(
                    children: [
                      BallLoader(color: palette.accent, width: 36, label: 'Verifying'),
                      const SizedBox(width: 12),
                      Text('Verifying…', style: TextStyle(color: palette.inkMuted, fontSize: 14)),
                    ],
                  )
                : null,
          ),
          if (_resent && _error == null)
            Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 18, color: palette.accent),
                  const SizedBox(width: 8),
                  Text('New code sent on WhatsApp.', style: TextStyle(color: palette.ink, fontSize: 14)),
                ],
              ),
            ),
          if (_error != null)
            OnboardError(
              message: _error!,
              action: switch (_problem) {
                SignInProblem.network => 'Retry',
                SignInProblem.expiredCode || SignInProblem.tooManyAttempts || SignInProblem.whatsApp => 'Send new code',
                _ => null,
              },
              onAction: switch (_problem) {
                SignInProblem.network => _code.text.length == _length ? _verify : _resend,
                _ => _resend,
              },
            ),
        ],
      ),
      bottom: Row(
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: TextButton(
                key: const Key('changeNumber'),
                onPressed: _busy ? null : () => context.pop(),
                style: TextButton.styleFrom(foregroundColor: palette.inkMuted, minimumSize: const Size(48, 48)),
                child: const Text('Change number'),
              ),
            ),
          ),
          const Spacer(),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: TextButton(
                key: const Key('resendCode'),
                onPressed: canResend ? _resend : null,
                style: TextButton.styleFrom(foregroundColor: palette.ink, minimumSize: const Size(48, 48)),
                child: Text(
                  canResend || _busy ? 'Resend code' : 'Resend in ${_resendIn}s',
                  style: TextStyle(
                    color: canResend ? palette.ink : palette.inkMuted,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Six boxes over one invisible field, so the keyboard, paste and the
/// system's one-time-code autofill all work as for a normal text field.
class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({
    required this.controller,
    required this.focusNode,
    required this.length,
    required this.readOnly,
    required this.error,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final bool readOnly;
  final bool error;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = OnboardPalette.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([controller, focusNode]),
      builder: (context, _) {
        final text = controller.text;
        return SizedBox(
          height: 64,
          child: Stack(
            children: [
              Row(
                children: [
                  for (var i = 0; i < length; i++) ...[
                    if (i > 0) SizedBox(width: i == length / 2 ? 14 : 8),
                    Expanded(
                      child: _Box(
                        digit: i < text.length ? text[i] : null,
                        active: focusNode.hasFocus && !readOnly && i == math.min(text.length, length - 1),
                        error: error,
                        palette: palette,
                      ),
                    ),
                  ],
                ],
              ),
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    key: const Key('codeField'),
                    controller: controller,
                    focusNode: focusNode,
                    // Read-only rather than disabled while busy: a disabled
                    // field cannot hold focus, so the keyboard would close.
                    readOnly: readOnly,
                    autofocus: true,
                    showCursor: false,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(length)],
                    decoration: const InputDecoration(border: InputBorder.none, filled: false, counterText: ''),
                    onChanged: onChanged,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.digit, required this.active, required this.error, required this.palette});

  final String? digit;
  final bool active;
  final bool error;
  final OnboardPalette palette;

  @override
  Widget build(BuildContext context) {
    final border = error ? palette.error : (active ? palette.accent : (digit != null ? palette.inkFaint : palette.glassBorder));
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.isDark ? const Color(0x14FFFFFF) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: active || error ? 1.8 : 1),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 140),
        transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
        child: digit == null
            ? (active ? Container(key: const ValueKey('caret'), width: 2, height: 24, color: palette.accent) : const SizedBox())
            : Text(digit!, key: ValueKey(digit), style: SkorxType.score(30, color: palette.ink)),
      ),
    );
  }
}
