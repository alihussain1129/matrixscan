import 'package:exalted/core/widgets/exalted_empty_state.dart';
import 'package:exalted/core/widgets/exalted_error_state.dart';
import 'package:exalted/core/widgets/exalted_status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF125352),
        brightness: brightness,
      ),
    ),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('status chip shows label and icon for every kind', (t) async {
    for (final kind in ExaltedStatusKind.values) {
      await t.pumpWidget(
        _wrap(ExaltedStatusChip(label: 'L-$kind', kind: kind)),
      );
      expect(find.text('L-$kind'), findsOneWidget);
      expect(find.byIcon(ExaltedStatusChip.defaultIcon(kind)), findsOneWidget);
    }
  });

  testWidgets('status chip renders in dark theme', (t) async {
    await t.pumpWidget(
      _wrap(
        const ExaltedStatusChip(
          label: 'Linked',
          kind: ExaltedStatusKind.success,
        ),
        brightness: Brightness.dark,
      ),
    );
    expect(find.text('Linked'), findsOneWidget);
  });

  testWidgets('empty state hides the button without an action', (t) async {
    await t.pumpWidget(
      _wrap(
        const ExaltedEmptyState(
          icon: Icons.history,
          title: 'No scans yet',
          actionLabel: 'Scan now',
        ),
      ),
    );
    expect(find.text('No scans yet'), findsOneWidget);
    expect(find.text('Scan now'), findsNothing);
  });

  testWidgets('empty state action calls back', (t) async {
    var taps = 0;
    await t.pumpWidget(
      _wrap(
        ExaltedEmptyState(
          icon: Icons.history,
          title: 'No scans yet',
          actionLabel: 'Scan now',
          onAction: () => taps++,
        ),
      ),
    );
    await t.tap(find.text('Scan now'));
    expect(taps, 1);
  });

  testWidgets('error state shows retry only when supplied', (t) async {
    await t.pumpWidget(
      _wrap(const ExaltedErrorState(title: 'Sync failed', message: 'timeout')),
    );
    expect(find.text('Sync failed'), findsOneWidget);
    expect(find.text('timeout'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);

    var retries = 0;
    await t.pumpWidget(
      _wrap(ExaltedErrorState(title: 'Sync failed', onRetry: () => retries++)),
    );
    await t.tap(find.text('Try again'));
    expect(retries, 1);
  });
}
