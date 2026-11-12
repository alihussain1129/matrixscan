import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/core/widgets/page_transitions.dart';

void main() {
  testWidgets('SharedAxisPageTransition builds on both axes', (tester) async {
    for (final axis in Axis.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: SharedAxisPageTransition(axis: axis, child: const Text('x')),
        ),
      );
      expect(find.text('x'), findsOneWidget);
    }
  });

  testWidgets('AnimatedEntry follows its animation', (tester) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 100),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedEntry(animation: controller, child: const Text('x')),
      ),
    );
    double opacity() => tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.byType(AnimatedEntry),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;
    expect(opacity(), 0.0);
    controller.value = 1.0;
    await tester.pump();
    expect(opacity(), 1.0);
  });

  testWidgets('FadeRoute and SlideRoute show pages and keep settings', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    Navigator.of(ctx).push(
      FadeRoute<void>(
        builder: (_) => const Text('fade'),
        settings: const RouteSettings(name: '/fade'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('fade'), findsOneWidget);
    expect(
      ModalRoute.of(tester.element(find.text('fade')))!.settings.name,
      '/fade',
    );
    Navigator.of(ctx)
        .push(SlideRoute<void>(builder: (_) => const Text('slide')));
    await tester.pumpAndSettle();
    expect(find.text('slide'), findsOneWidget);
  });
}
