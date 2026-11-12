import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:exalted/core/config/app_config.dart';
import 'package:exalted/core/config/config_controller.dart';
import 'package:exalted/core/config/platform_secret_store.dart';
import 'package:exalted/features/settings/ftp_settings_card.dart';

import 'support/in_memory_secret_store.dart';

Future<ProviderContainer> pump(
  WidgetTester t,
  InMemorySecretStore store,
) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [secretStoreProvider.overrideWithValue(store)],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: FtpSettingsCard())),
      ),
    ),
  );
  await t.pumpAndSettle();
  return ProviderScope.containerOf(t.element(find.byType(FtpSettingsCard)));
}

void main() {
  testWidgets('enabling without credentials is refused', (t) async {
    final store = InMemorySecretStore();
    final c = await pump(t, store);
    await t.tap(find.byKey(const Key('ftp-enable')));
    await t.tap(find.byKey(const Key('ftp-save')));
    await t.pumpAndSettle();
    expect(find.text('Enter a username to enable FTP.'), findsOneWidget);
    expect(
      c.read(configControllerProvider).scanner.ftpReceiverEnabled,
      isFalse,
    );
    expect(store.values, isEmpty);
  });

  testWidgets('username without a password is refused', (t) async {
    final store = InMemorySecretStore();
    final c = await pump(t, store);
    await t.tap(find.byKey(const Key('ftp-enable')));
    await t.enterText(find.byKey(const Key('ftp-user')), 'scanner');
    await t.tap(find.byKey(const Key('ftp-save')));
    await t.pumpAndSettle();
    expect(find.text('Enter a password to enable FTP.'), findsOneWidget);
    expect(
      c.read(configControllerProvider).scanner.ftpReceiverEnabled,
      isFalse,
    );
  });

  testWidgets('password goes to the vault, never into config', (t) async {
    final store = InMemorySecretStore();
    final c = await pump(t, store);
    await t.tap(find.byKey(const Key('ftp-enable')));
    await t.enterText(find.byKey(const Key('ftp-user')), 'scanner');
    await t.enterText(find.byKey(const Key('ftp-pass')), 'secret-pw');
    await t.tap(find.byKey(const Key('ftp-save')));
    await t.pumpAndSettle();
    final sc = c.read(configControllerProvider).scanner;
    expect(sc.ftpReceiverEnabled, isTrue);
    expect(sc.ftpUsername, 'scanner');
    expect(store.values[ScannerConfig.ftpPasswordSecretKey], 'secret-pw');
    expect(
      jsonEncode(c.read(configControllerProvider).toJson()),
      isNot(contains('secret-pw')),
    );
  });
}
