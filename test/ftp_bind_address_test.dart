import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/core/config/config_controller.dart';
import 'package:exalted/core/config/platform_secret_store.dart';
import 'package:exalted/features/settings/ftp_settings_card.dart';

import 'support/in_memory_secret_store.dart';

Future<ProviderContainer> pumpCard(
  WidgetTester t, {
  String? savedBind,
  List<String> detected = const ['192.168.100.5'],
}) async {
  final c = ProviderContainer(
    overrides: [
      secretStoreProvider.overrideWithValue(InMemorySecretStore()),
      localIpv4AddressesProvider.overrideWith((ref) async => detected),
    ],
  );
  addTearDown(c.dispose);
  if (savedBind != null) {
    await c.read(configControllerProvider.notifier).patch({
      'scanner': {'ftpBindAddress': savedBind},
    });
  }
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: FtpSettingsCard())),
      ),
    ),
  );
  await t.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('defaults to all interfaces and says so', (t) async {
    final c = await pumpCard(t);
    expect(c.read(configControllerProvider).scanner.ftpBindAddress, '0.0.0.0');
    expect(find.textContaining('Every network can reach'), findsOneWidget);
  });

  testWidgets('choosing a detected address saves it', (t) async {
    final c = await pumpCard(t);
    await t.tap(find.byKey(const Key('ftp-bind')));
    await t.pumpAndSettle();
    await t.tap(find.text('192.168.100.5').last);
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('ftp-save')));
    await t.tap(find.byKey(const Key('ftp-save')));
    await t.pumpAndSettle();
    expect(
      c.read(configControllerProvider).scanner.ftpBindAddress,
      '192.168.100.5',
    );
  });

  testWidgets('a saved address that vanished stays visible', (t) async {
    await pumpCard(t, savedBind: '10.9.9.9');
    expect(find.text('10.9.9.9 (not currently available)'), findsOneWidget);
  });
}
