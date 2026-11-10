import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/core/config/app_config.dart';
import 'package:exalted/core/config/config_provider.dart';
import 'package:exalted/features/devices/device_hub_provider.dart';

void main() {
  test('default config gives the hub the values it always had', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final hub = c.read(deviceHubProvider);
    expect(hub.connectTimeout, const Duration(seconds: 10));
    expect(hub.acquisitionTimeout, const Duration(seconds: 5));
    expect(hub.operationTimeout, const Duration(seconds: 5));
    expect(hub.discoveryTimeout, const Duration(seconds: 10));
    expect(hub.reconnectPolicy.enabled, isTrue);
    expect(hub.reconnectPolicy.initialDelay, const Duration(seconds: 1));
    expect(hub.reconnectPolicy.maxDelay, const Duration(seconds: 16));
    expect(hub.reconnectPolicy.maxAttempts, isNull);
  });

  test('config values reach the hub', () {
    final c = ProviderContainer(
      overrides: [
        configProvider.overrideWithValue(
          const AppConfig(
            scanner: ScannerConfig(
              connectTimeoutMs: 1234,
              acquisitionTimeoutMs: 2345,
              operationTimeoutMs: 3456,
              discoveryTimeoutMs: 4567,
              reconnectInitialDelayMs: 500,
              reconnectMaxDelayMs: 8000,
              reconnectMaxAttempts: 3,
            ),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    final hub = c.read(deviceHubProvider);
    expect(hub.connectTimeout, const Duration(milliseconds: 1234));
    expect(hub.acquisitionTimeout, const Duration(milliseconds: 2345));
    expect(hub.operationTimeout, const Duration(milliseconds: 3456));
    expect(hub.discoveryTimeout, const Duration(milliseconds: 4567));
    expect(hub.reconnectPolicy.initialDelay, const Duration(milliseconds: 500));
    expect(hub.reconnectPolicy.maxDelay, const Duration(seconds: 8));
    expect(hub.reconnectPolicy.maxAttempts, 3);
  });
}
