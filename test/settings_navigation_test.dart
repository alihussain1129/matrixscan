import 'package:exalted/core/router/app_router.dart';
import 'package:exalted/core/config/config_controller.dart';
import 'package:exalted/core/theme/app_theme.dart';
import 'package:exalted/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('system information rows fit a phone-width viewport', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(411, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Platform Architecture'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings separates decoder, OCR, verification, and About', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: const Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ChoiceChip), findsNWidgets(11));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Decoder'));
    await tester.pump();
    expect(find.text('ENABLED SYMBOLOGIES'), findsOneWidget);
    expect(find.text('rMQR'), findsOneWidget);
    final qrToggle = find.ancestor(
      of: find.text('QR Code'),
      matching: find.byType(CheckboxListTile),
    );
    await tester.ensureVisible(qrToggle);
    await tester.tap(qrToggle);
    await tester.pumpAndSettle();
    expect(
      container.read(configControllerProvider).decoder.symbologies,
      isNot(contains('qrCode')),
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'OCR'));
    await tester.pump();
    expect(find.text('Live text reading'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Verification'));
    await tester.pump();
    await tester.tap(find.text('Open verification settings'));
    expect(container.read(navIndexProvider), kVerificationTab);

    final aboutCategory = find.widgetWithText(ChoiceChip, 'About');
    await tester.ensureVisible(aboutCategory);
    await tester.pump();
    await tester.tap(aboutCategory);
    await tester.pump();
    expect(find.text('View product information'), findsOneWidget);
  });
}
