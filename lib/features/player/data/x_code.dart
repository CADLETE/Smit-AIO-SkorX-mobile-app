import 'dart:math';

/// A player's X code: four letters and digits, unique to one player, e.g.
/// "7K2Q". It is what players read out to each other to be found, searched
/// or added to a match, so it is short and hard to misread:
///
/// - no 0/O, 1/I/L, which look alike on a screen and sound alike;
/// - always at least one letter and one digit, so a code never spells a
///   word and a four-letter name search ("ANAN") is never taken for a code.
///
/// That leaves 639,584 codes. The server assigns them and keeps them
/// unique; [generate] is for sample data and tests.
abstract final class XCode {
  static const length = 4;
  static const letters = 'ABCDEFGHJKMNPQRSTUVWXYZ';
  static const digits = '23456789';
  static const alphabet = '$digits$letters';

  static final _shape = RegExp('^[$alphabet]{$length}\$');

  /// Whether [code] is a well-formed X code, already normalised.
  static bool isValid(String code) =>
      _shape.hasMatch(code) && code.split('').any(digits.contains) && code.split('').any(letters.contains);

  /// The code a person typed, however they typed it ("7k2q", "X-7K2Q",
  /// "#7K2Q", "x 7k2q"), or null when it is not one.
  static String? parse(String input) {
    var s = input.toUpperCase().replaceAll(RegExp(r'[\s\-#·]'), '');
    if (s.length == length + 1 && s.startsWith('X')) s = s.substring(1);
    return isValid(s) ? s : null;
  }

  /// How a code is shown next to a name: "X·7K2Q".
  static String display(String code) => 'X·$code';

  /// A random code not in [taken].
  static String generate({Random? random, Set<String> taken = const {}}) {
    final r = random ?? Random.secure();
    while (true) {
      final code = List.generate(length, (_) => alphabet[r.nextInt(alphabet.length)]).join();
      if (isValid(code) && !taken.contains(code)) return code;
    }
  }
}
