import '../features/scanner/wifi_utils.dart';
import 'interpreter.dart';
import 'scan_field.dart';

/// "WIFI:S:...;T:...;P:...;;" codes. The password is marked sensitive, and so
/// is the raw payload, because it contains the password.
class WifiInterpreter implements PayloadInterpreter {
  @override
  String get id => 'wifi';

  @override
  Interpretation? interpret(ScanPayload payload) {
    final wifi = parseWifiQr(payload.raw);
    if (wifi == null) return null;

    final warnings = <String>[
      if (wifi.security == WifiSecurity.wep)
        'WEP is an outdated security type.',
      if (wifi.security == WifiSecurity.unsupported)
        'The security type is not recognised, so the network cannot be '
            'joined automatically.',
    ];

    return Interpretation(
      interpreterId: id,
      formatName: 'Wi-Fi network',
      rawIsSensitive: wifi.password.isNotEmpty,
      warnings: warnings,
      sections: [
        ScanSection(
          id: 'wifi',
          title: 'Wi-Fi network',
          fields: [
            ScanField(
              id: 'ssid',
              label: 'Network name',
              value: wifi.ssid,
              standard: 'Wi-Fi QR',
            ),
            ScanField(
              id: 'security',
              label: 'Security',
              value: wifi.securityLabel,
              standard: 'Wi-Fi QR',
            ),
            ScanField(
              id: 'hidden',
              label: 'Hidden network',
              value: wifi.hidden ? 'Yes' : 'No (or not specified)',
              standard: 'Wi-Fi QR',
            ),
            if (wifi.password.isEmpty)
              const ScanField.notPresent('Password', id: 'password')
            else
              ScanField(
                id: 'password',
                label: 'Password',
                value: wifi.password,
                standard: 'Wi-Fi QR',
                sensitive: true,
                note: 'Hidden by default.',
              ),
          ],
        ),
      ],
    );
  }
}