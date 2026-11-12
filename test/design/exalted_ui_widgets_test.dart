import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/core/theme/app_theme.dart';
import 'package:exalted/core/widgets/exalted_card.dart';
import 'package:exalted/design/exalted_hero_card.dart';
import 'package:exalted/design/exalted_press_scale.dart';
import 'package:exalted/design/exalted_stagger.dart';
import 'package:exalted/design/exalted_success_burst.dart';

Widget _app(Widget c) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(body: Center(child: c)),
);

void main() {
  testWidgets('press scale forwards taps', (tester) async {
    var n = 0;
    await tester.pumpWidget(
      _app(ExaltedPressScale(onTap: () => n++, child: const Text('x'))),
    );
    await tester.tap(find.text('x'));
    await tester.pumpAndSettle();
    expect(n, 1);
  });

  testWidgets('stagger ends with the child visible', (tester) async {
    await tester.pumpWidget(
      _app(const ExaltedStagger(index: 3, child: Text('hi'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('hi'), findsOneWidget);
  });

  testWidgets('hero card counts up to the value', (tester) async {
    await tester.pumpWidget(
      _app(const ExaltedHeroCard(title: 'Total scans', value: 1280)),
    );
    await tester.pumpAndSettle();
    expect(find.text('1,280'), findsOneWidget);
  });

  testWidgets('hero card shows a dash while loading', (tester) async {
    await tester.pumpWidget(
      _app(
        const ExaltedHeroCard(title: 'Total scans', value: 0, loading: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('\u2014'), findsOneWidget);
  });

  testWidgets('tappable card works', (tester) async {
    var n = 0;
    await tester.pumpWidget(
      _app(ExaltedCard(onTap: () => n++, child: const Text('card'))),
    );
    await tester.tap(find.text('card'));
    await tester.pumpAndSettle();
    expect(n, 1);
  });

  testWidgets('success burst plays on trigger and ends', (tester) async {
    Widget w(int t) =>
        _app(ExaltedSuccessBurst(trigger: t, color: Colors.teal));
    await tester.pumpWidget(w(0));
    await tester.pumpWidget(w(1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
