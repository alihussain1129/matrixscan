import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/design/exalted_segmented.dart';
import 'package:exalted/design/exalted_press_scale.dart';
import 'package:exalted/design/exalted_stagger.dart';
import 'package:exalted/design/exalted_shimmer.dart';
import 'package:exalted/design/exalted_success_burst.dart';

Widget _app(Widget child, {bool reduceMotion = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('empty segmented options render safely', (tester) async {
    await tester.pumpWidget(
      _app(
        ExaltedSegmented<String>(
          options: const [],
          value: 'missing',
          onChanged: (_) {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(ExaltedSegmented<String>), findsOneWidget);
    expect(find.byType(AnimatedPositioned), findsNothing);
  });

  testWidgets('unknown segmented value does not select the first option', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ExaltedSegmented<String>(
          options: const [
            ExaltedSegment(value: 'a', label: 'A'),
            ExaltedSegment(value: 'b', label: 'B'),
          ],
          value: 'missing',
          onChanged: (_) {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(AnimatedPositioned), findsNothing);
  });

  testWidgets('shimmer does not start its controller in reduced-motion mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const ExaltedShimmer(child: Text('loading')), reduceMotion: true),
    );

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('loading'), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stagger skips its entrance animation in reduced-motion mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const ExaltedStagger(index: 4, child: Text('ready')),
        reduceMotion: true,
      ),
    );

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('ready'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('bounce icon skips selection animation in reduced-motion mode', (
    tester,
  ) async {
    Widget icon(bool selected) => _app(
      ExaltedBounceIcon(
        icon: Icons.check,
        color: Colors.teal,
        size: 24,
        selected: selected,
      ),
      reduceMotion: true,
    );

    await tester.pumpWidget(icon(false));
    await tester.pumpWidget(icon(true));
    await tester.pump(const Duration(seconds: 1));

    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('success burst is suppressed in reduced-motion mode', (
    tester,
  ) async {
    Widget burst(int trigger) => _app(
      ExaltedSuccessBurst(trigger: trigger, color: Colors.teal),
      reduceMotion: true,
    );

    await tester.pumpWidget(burst(0));
    await tester.pumpWidget(burst(1));
    await tester.pump(const Duration(seconds: 1));

    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });
}
