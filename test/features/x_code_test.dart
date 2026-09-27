import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:skorx/features/casual_match/data/match_setup.dart';
import 'package:skorx/features/player/data/player_repository.dart';
import 'package:skorx/features/player/data/x_code.dart';

void main() {
  group('XCode', () {
    test('is four letters and digits, always both', () {
      expect(XCode.isValid('7K2Q'), isTrue);
      expect(XCode.isValid('ABCD'), isFalse, reason: 'no digit');
      expect(XCode.isValid('2345'), isFalse, reason: 'no letter');
      expect(XCode.isValid('7K2'), isFalse);
      expect(XCode.isValid('7K2QA'), isFalse);
    });

    test('leaves out characters that look alike', () {
      for (final c in ['0', 'O', '1', 'I', 'L']) {
        expect(XCode.isValid('7K2$c'), isFalse, reason: c);
      }
    });

    test('reads a code however it is typed', () {
      for (final typed in ['7K2Q', '7k2q', 'X7K2Q', 'x-7k2q', '#7K2Q', ' 7K 2Q ', 'X·7K2Q']) {
        expect(XCode.parse(typed), '7K2Q', reason: typed);
      }
      expect(XCode.parse('Anand'), isNull);
      expect(XCode.parse('ANAN'), isNull, reason: 'a name is never a code');
    });

    test('generates valid codes and skips taken ones', () {
      final r = Random(1);
      final taken = <String>{};
      for (var i = 0; i < 2000; i++) {
        final code = XCode.generate(random: r, taken: taken);
        expect(XCode.isValid(code), isTrue, reason: code);
        expect(taken.add(code), isTrue, reason: 'duplicate $code');
      }
    });
  });

  test('sample players each have their own X code', () {
    final codes = [for (final p in SampleMatchPlayerDirectory.players) p.xCode!];
    expect(codes.every(XCode.isValid), isTrue);
    expect(codes.toSet().length, codes.length);
  });

  test('searching an X code finds only that player', () async {
    expect((await const SampleMatchPlayerDirectory().search('h9st')).map((p) => p.name), ['Hardik Suthar']);
    expect(await const SampleMatchPlayerDirectory().search('Z9ZZ'), isEmpty);
    final found = await SamplePlayerRepository('Smit', latency: Duration.zero).searchPlayers('X-T4MN');
    expect(found.map((p) => p.name), ['Tara Menon']);
  });
}
