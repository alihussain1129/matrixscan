import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'wifi_utils.dart';

/// Method channel implemented in MainActivity.kt.
const String wifiChannelName = 'com.exaltedcoding.exalted/wifi';

enum WifiConnectOutcome { saved, connecting, openedSettings, cancelled, failed }

class WifiConnectResult {
  const WifiConnectResult(this.outcome, this.message);

  final WifiConnectOutcome outcome;

  /// Text for the user.
  final String message;
}

/// Joins a Wi-Fi network through Android. The password goes only to the
/// Android system call.
class WifiConnector {
  WifiConnector({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(wifiChannelName);

  final MethodChannel _channel;

  Future<WifiConnectResult> connect(WifiNetworkInfo wifi) async {
    final failed = WifiConnectResult(
      WifiConnectOutcome.failed,
      "Couldn't connect to ${wifi.ssid}",
    );
    if (!wifi.canConnect) return failed;

    try {
      final status = await _channel.invokeMethod<String>(
        'connect',
        <String, Object?>{
          'ssid': wifi.ssid,
          'password': wifi.password,
          'security': wifi.security.name,
          'hidden': wifi.hidden,
        },
      );
      switch (status) {
        case 'saved':
          return const WifiConnectResult(
            WifiConnectOutcome.saved,
            'Network saved. Android will join it when it is in range.',
          );
        case 'connecting':
          return WifiConnectResult(
            WifiConnectOutcome.connecting,
            'Connecting to ${wifi.ssid}...',
          );
        case 'cancelled':
          return const WifiConnectResult(
            WifiConnectOutcome.cancelled,
            'Wi-Fi was not changed',
          );
        case 'manual':
          return await _manual(wifi, failed);
        default:
          return failed;
      }
    } on PlatformException catch (e) {
      if (e.code == 'bad_password') {
        return const WifiConnectResult(
          WifiConnectOutcome.failed,
          "That password isn't valid for this network type",
        );
      }
      return failed;
    } on MissingPluginException {
      return const WifiConnectResult(
        WifiConnectOutcome.failed,
        'Joining Wi-Fi is only available on Android',
      );
    }
  }

  /// Android has no one-tap way here: copy the password, open Wi-Fi settings.
  Future<WifiConnectResult> _manual(
    WifiNetworkInfo wifi,
    WifiConnectResult failed,
  ) async {
    final hasPassword = wifi.password.isNotEmpty;
    if (hasPassword) {
      await Clipboard.setData(ClipboardData(text: wifi.password));
    }
    try {
      await _channel.invokeMethod<void>('openWifiSettings');
    } on PlatformException {
      return failed;
    } on MissingPluginException {
      return failed;
    }
    return WifiConnectResult(
      WifiConnectOutcome.openedSettings,
      hasPassword
          ? 'Password copied. Choose "${wifi.ssid}" in Wi-Fi settings and paste it.'
          : 'Choose "${wifi.ssid}" in Wi-Fi settings.',
    );
  }
}

final wifiConnectorProvider = Provider<WifiConnector>((ref) => WifiConnector());
