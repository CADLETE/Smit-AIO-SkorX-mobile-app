import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skorx/app/intro/skorx_intro.dart';
import 'package:skorx/features/onboarding/ui/onboarding_kit.dart';

import '../support/fakes.dart';

void main() {
  setUp(useInMemoryPreferences);

  Future<void> pumpGate(WidgetTester tester, ProviderContainer container) => tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SkorxIntroGate(child: Text('app'))),
        ),
      );

  Future<int> playOut(WidgetTester tester) async {
    var ms = 0;
    while (find.byType(SkorxIntro).evaluate().isNotEmpty && ms < 5000) {
      await tester.pump(const Duration(milliseconds: 50));
      ms += 50;
    }
    return ms;
  }

  testWidgets('the first launch plays the full reveal over the app, then removes itself', (tester) async {
    final container = ProviderContainer(overrides: appOverrides(FakeAuthRepository()));
    addTearDown(container.dispose);
    await pumpGate(tester, container);
    await tester.pump();
    expect(find.byType(SkorxIntro), findsOneWidget);
    expect(container.read(launchIntroDoneProvider), isFalse);
    final ms = await playOut(tester);
    expect(ms, greaterThan(3300));
    expect(find.text('app'), findsOneWidget);
    expect(container.read(launchIntroDoneProvider), isTrue, reason: 'screens underneath start their entrance');
  });

  testWidgets('a returning player gets the quick version', (tester) async {
    await markIntroSeen();
    final container = ProviderContainer(overrides: appOverrides(FakeAuthRepository()));
    addTearDown(container.dispose);
    await pumpGate(tester, container);
    await tester.pump();
    expect(find.byType(SkorxIntro), findsOneWidget);
    expect(await playOut(tester), lessThan(3100), reason: '2.6 s plus the hold for the first frames');
  });

  testWidgets('reduced motion skips the intro', (tester) async {
    useReducedMotion(tester);
    final container = ProviderContainer(overrides: appOverrides(FakeAuthRepository()));
    addTearDown(container.dispose);
    await pumpGate(tester, container);
    expect(find.byType(SkorxIntro), findsNothing);
  });
}
