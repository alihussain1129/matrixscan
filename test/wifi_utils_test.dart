import 'package:exalted/features/scanner/wifi_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the standard Wi-Fi QR text', () {
    final wifi = parseWifiQr('WIFI:S:Network;T:WPA;P:Password;;');
    expect(wifi, isNotNull);
    expect(wifi!.ssid, 'Network');
    expect(wifi.security, WifiSecurity.wpa);
    expect(wifi.password, 'Password');
    expect(wifi.hidden, isFalse);
    expect(wifi.canConnect, isTrue);
  });

  test('fields can be in any order; H:true is hidden; closing ;; optional', () {
    final wifi = parseWifiQr('WIFI:H:true;P:pw;S:Cafe;T:WPA');
    expect(wifi, isNotNull);
    expect(wifi!.ssid, 'Cafe');
    expect(wifi.password, 'pw');
    expect(wifi.hidden, isTrue);
    expect(wifi.security, WifiSecurity.wpa);
  });

  test('escaped separators and backslashes are decoded', () {
    final wifi = parseWifiQr(r'WIFI:S:My\;Net\:work;T:WPA;P:pa\\ss\,word;;');
    expect(wifi, isNotNull);
    expect(wifi!.ssid, 'My;Net:work');
    expect(wifi.password, r'pa\ss,word');
  });

  test('quoted values are taken literally without the quotes', () {
    final wifi = parseWifiQr('WIFI:S:"1234";T:WPA;P:"5678";;');
    expect(wifi, isNotNull);
    expect(wifi!.ssid, '1234');
    expect(wifi.password, '5678');
  });

  test('open networks have no password and can connect', () {
    for (final text in [
      'WIFI:S:Guest;T:nopass;;',
      'WIFI:S:Guest;;',
      'WIFI:S:Guest;T:nopass;P:ignored;;',
    ]) {
      final wifi = parseWifiQr(text);
      expect(wifi, isNotNull, reason: text);
      expect(wifi!.security, WifiSecurity.open, reason: text);
      expect(wifi.password, '', reason: text);
      expect(wifi.canConnect, isTrue, reason: text);
    }
  });

  test('security types map to WEP, WPA and WPA3', () {
    expect(parseWifiQr('WIFI:S:N;T:WEP;P:12345;;')!.security, WifiSecurity.wep);
    expect(parseWifiQr('WIFI:S:N;T:WPA2;P:pw;;')!.security, WifiSecurity.wpa);
    expect(parseWifiQr('WIFI:S:N;T:SAE;P:pw;;')!.security, WifiSecurity.wpa3);
    expect(parseWifiQr('WIFI:S:N;T:WPA3;P:pw;;')!.security, WifiSecurity.wpa3);
    expect(parseWifiQr('WIFI:S:N;P:pw;;')!.security, WifiSecurity.wpa);
  });

  test('enterprise and password-less secured networks cannot connect', () {
    final corp = parseWifiQr('WIFI:S:Corp;T:WPA2-EAP;I:user;P:pw;;');
    expect(corp, isNotNull);
    expect(corp!.ssid, 'Corp');
    expect(corp.security, WifiSecurity.unsupported);
    expect(corp.canConnect, isFalse);

    final noPassword = parseWifiQr('WIFI:S:N;T:WPA;;');
    expect(noPassword, isNotNull);
    expect(noPassword!.security, WifiSecurity.wpa);
    expect(noPassword.canConnect, isFalse);
  });

  test('text that is not a usable Wi-Fi code is rejected', () {
    const rejected = [
      '',
      'https://example.com',
      'LOT-4471-DM',
      'WIFI:',
      'WIFI:T:WPA;P:pw;;',
      'WIFI:S:;T:WPA;P:pw;;',
      'WIFI:S:;;',
    ];
    for (final text in rejected) {
      expect(parseWifiQr(text), isNull, reason: 'should reject: "$text"');
    }
  });

  test('prefix is case-insensitive, whitespace is trimmed, colons stay', () {
    final wifi = parseWifiQr('  wifi:S:Home;T:WPA;P:a:b;;\n');
    expect(wifi, isNotNull);
    expect(wifi!.ssid, 'Home');
    expect(wifi.password, 'a:b');
  });
}
