import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/core/theme/app_colors.dart';
import 'package:exalted/core/widgets/page_transitions.dart';
import 'package:exalted/design/exalted_motion.dart';
import 'package:exalted/design/exalted_page_route.dart';
import 'package:exalted/design/exalted_page_transitions.dart';
import 'package:exalted/design/exalted_scan_overlay.dart';
import 'package:exalted/design/exalted_state_view.dart';
import 'package:exalted/design/exalted_stat_counter.dart';
import 'package:exalted/design/exalted_tokens.dart';
import 'package:exalted/features/scanner/scan_frame_painter.dart';

ThemeData _theme({bool dark = false}) => ThemeData(
  useMaterial3: true,
  colorScheme: dark ? AppColors.darkScheme : AppColors.lightScheme,
  extensions: <ThemeExtension<dynamic>>[
    dark ? AppColors.darkExtra : AppColors.lightExtra,
  ],
  pageTransitionsTheme: kExaltedPageTransitions,
);

Widget _app(Widget child, {bool reduced = false, bool dark = false}) =>
    MaterialApp(
      theme: _theme(dark: dark),
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: c!,
      ),
      home: Scaffold(body: child),
    );

Widget _pushButton(Route<void> Function() route) => Builder(
  builder: (context) => TextButton(
    onPressed: () => Navigator.of(context).push(route()),
    child: const Text('go'),
  ),
);

void main() {
  testWidgets('scan overlay animates and disposes cleanly', (tester) async {
    await tester.pumpWidget(_app(const ExaltedScanOverlay()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(_app(const SizedBox()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('scan overlay does not loop when reduced motion is on', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const ExaltedScanOverlay(), reduced: true));
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scan overlay switches state without errors', (tester) async {
    for (final s in ExaltedScanState.values) {
      await tester.pumpWidget(_app(ExaltedScanOverlay(state: s)));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('state view shows title, message and action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _app(
        ExaltedStateView(
          kind: ExaltedStateKind.permissionDenied,
          message: 'Allow the camera in system settings.',
          actionLabel: 'Open settings',
          onAction: () => tapped = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Camera access is off'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    expect(tapped, isTrue);
  });

  testWidgets('stat counter reaches final value', (tester) async {
    await tester.pumpWidget(
      _app(const ExaltedStatCounter(value: 128, label: 'Scans today')),
    );
    await tester.pumpAndSettle();
    expect(find.text('128'), findsOneWidget);
  });

  testWidgets('ExaltedPageRoute pushes', (tester) async {
    await tester.pumpWidget(
      _app(
        _pushButton(
          () => ExaltedPageRoute<void>(builder: (_) => const Text('second')),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('reduced motion gives zero duration', (tester) async {
    Duration? got;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            got = ExaltedMotion.d(context, ExaltedMotion.base);
            return const SizedBox();
          },
        ),
        reduced: true,
      ),
    );
    expect(got, Duration.zero);
  });

  test('tokens come from the existing ExaltedColors', () {
    final light = ExaltedTokens.fromTheme(_theme());
    final dark = ExaltedTokens.fromTheme(_theme(dark: true));
    expect(light.brand, const Color(0xFF125352));
    expect(light.success, AppColors.lightExtra.valid);
    expect(dark.accent, AppColors.darkExtra.aqua);
    expect(light.accent, isNot(dark.accent));
  });

  for (final reduced in [false, true]) {
    testWidgets('theme page transition push and pop (reduced=$reduced)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          _pushButton(
            () => MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('second')),
            ),
          ),
          reduced: reduced,
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('second'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.text('second'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('FadeRoute respects reduced motion (reduced=$reduced)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          _pushButton(
            () => FadeRoute<void>(builder: (_) => const Text('second')),
          ),
          reduced: reduced,
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.descendant(
          of: find.byType(FadePageTransition),
          matching: find.byType(FadeTransition),
        ),
        reduced ? findsNothing : findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(find.text('second'), findsOneWidget);
    });
  }

  testWidgets('ScanFramePainter paints at several positions', (tester) async {
    for (final p in [0.0, 0.5, 1.0]) {
      await tester.pumpWidget(
        Center(
          child: CustomPaint(
            size: const Size(200, 200),
            painter: ScanFramePainter(progress: p, color: Colors.teal),
          ),
        ),
      );
    }
    expect(tester.takeException(), isNull);
  });

  test('ScanFramePainter repaints only when inputs change', () {
    final a = ScanFramePainter(progress: 0.2, color: Colors.teal);
    expect(
      a.shouldRepaint(ScanFramePainter(progress: 0.2, color: Colors.teal)),
      isFalse,
    );
    expect(
      a.shouldRepaint(ScanFramePainter(progress: 0.3, color: Colors.teal)),
      isTrue,
    );
  });
}
