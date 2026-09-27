import '../../core/api/api_exception.dart';

/// What went wrong during sign-in, in words a player understands, and what
/// they can do next.
enum SignInProblem {
  invalidNumber('Please enter a valid WhatsApp number.'),
  wrongCode("That code doesn't look right. Try again."),
  expiredCode('Your code has expired. Request a new one.'),
  tooManyAttempts('Too many tries. Request a new code.'),
  network('Something went wrong. Check your connection and try again.'),
  whatsApp("We couldn't send the code on WhatsApp. Try again in a moment.");

  const SignInProblem(this.message);

  final String message;

  /// The code can no longer be used, so the fix is a new one.
  bool get needsNewCode => this == expiredCode || this == tooManyAttempts;

  /// Sorts an API failure. [message] of anything unrecognised is the
  /// server's own, which is written for players.
  static (SignInProblem?, String) from(ApiException e) {
    final problem = switch (e.code) {
      ApiException.network => network,
      'OTP_INVALID' || 'OTP_MISMATCH' || 'INVALID_OTP' => wrongCode,
      'OTP_EXPIRED' || 'OTP_NOT_FOUND' => expiredCode,
      'OTP_TOO_MANY_ATTEMPTS' || 'OTP_LOCKED' || 'TOO_MANY_REQUESTS' => tooManyAttempts,
      'OTP_SEND_FAILED' || 'WHATSAPP_FAILED' || 'WHATSAPP_UNAVAILABLE' => whatsApp,
      'INVALID_MOBILE' || 'VALIDATION_ERROR' => invalidNumber,
      _ => null,
    };
    return (problem, problem?.message ?? e.message);
  }
}

/// Indian mobile numbers, as the server accepts them: 10 digits from 6–9.
bool isValidIndianMobile(String digits) => RegExp(r'^[6-9]\d{9}$').hasMatch(digits);

/// "95865 45430".
String formatIndianMobile(String digits) =>
    digits.length == 10 ? '${digits.substring(0, 5)} ${digits.substring(5)}' : digits;
