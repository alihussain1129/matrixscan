import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/core/config/config_controller.dart';
import 'package:exalted/features/settings/auto_restart_card.dart';

Future<ProviderContainer> pump(WidgetTester t) async {
  await t.pumpWidget(
    const ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: AutoRestartCard())),
      ),
    ),
  );
  await t.pumpAndSettle();
  return ProviderScope.containerOf(t.element(find.byType(AutoRestartCard)));
}

void main() {
  testWidgets('starts off with a limit of 3', (t) async {
    final c = await pump(t);
    final sc = c.read(configControllerProvider).startup;
    expect(sc.autoRestart, isFalse);
    expect(sc.maxRestartsPerHour, 3);
    expect(find.byKey(const Key('restart-limit')), findsOneWidget);
  });

  testWidgets('the switch turns auto-restart on and off', (t) async {
    final c = await pump(t);
    await t.tap(find.byKey(const Key('restart-enable')));
    await t.pumpAndSettle();
    expect(c.read(configControllerProvider).startup.autoRestart, isTrue);
    await t.tap(find.byKey(const Key('restart-enable')));
    await t.pumpAndSettle();
    expect(c.read(configControllerProvider).startup.autoRestart, isFalse);
  });

  testWidgets('the dropdown changes the limit', (t) async {
    final c = await pump(t);
    await t.tap(find.byKey(const Key('restart-limit')));
    await t.pumpAndSettle();
    await t.tap(find.text('10').last);
    await t.pumpAndSettle();
    expect(c.read(configControllerProvider).startup.maxRestartsPerHour, 10);
  });
}
