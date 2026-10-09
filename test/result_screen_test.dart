import 'package:exalted/core/theme/app_theme.dart';
import 'package:exalted/features/result/result_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _show(WidgetTester tester, String raw, String symbology) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: ResultScreen(raw: raw, symbology: symbology, decodeMicros: 3500),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the original content is shown exactly as decoded', (
    tester,
  ) async {
    const raw = 'ABC-123\nLINE-2';
    await _show(tester, raw, 'QR Code');

    final shown = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(shown.data, raw);
    expect(find.text('QR Code'), findsWidgets);
    expect(find.text('3.5 ms'), findsOneWidget);
  });

  testWidgets('unrecognised content says interpretation is unavailable', (
    tester,
  ) async {
    await _show(tester, 'just some plain words', 'QR Code');

    expect(find.textContaining('Interpretation unavailable'), findsOneWidget);
    expect(find.textContaining('not recognised'), findsOneWidget);
  });

  testWidgets('a Wi-Fi password stays hidden until Reveal is tapped', (
    tester,
  ) async {
    const raw = 'WIFI:S:HomeNet;T:WPA;P:secret123;;';
    await _show(tester, raw, 'QR Code');

    expect(find.byType(SelectableText), findsNothing);

    await tester.tap(find.text('Reveal'));
    await tester.pumpAndSettle();

    final shown = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(shown.data, raw);
  });
}