import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:exalted/features/devices/core/device_models.dart';
import 'package:exalted/features/devices/core/device_registry_store.dart';

import 'support/fake_device_adapter.dart';

Future<DeviceRegistryStore> storeWith([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  return DeviceRegistryStore(await SharedPreferences.getInstance());
}

Future<String?> rawValue() async =>
    (await SharedPreferences.getInstance()).getString(DeviceRegistryStore.key);

void main() {
  test('empty store loads no devices', () async {
    final store = await storeWith();
    final result = store.load();
    expect(result.devices, isEmpty);
    expect(result.warning, isNull);
    expect(result.preserved, isFalse);
  });

  test('identity, backend and configuration round-trip', () async {
    final store = await storeWith();
    final reader = testReader();
    final result = await store.save([
      SavedDevice(
        identity: reader,
        backendId: 'keyence',
        configuration: DeviceConfiguration({'delimiter': 'CR', 'port': 9004}),
      ),
    ]);
    expect(result.written, isTrue);
    expect(result.droppedSecretKeys, isEmpty);
    expect(result.droppedUnsupported, isEmpty);
    final loaded = store.load().devices.single;
    expect(loaded.identity, reader);
    expect(loaded.backendId, 'keyence');
    expect(loaded.configuration!.values['delimiter'], 'CR');
    expect(loaded.configuration!.values['port'], 9004);
  });

  test('secret keys, including nested ones, are never written', () async {
    final store = await storeWith();
    final reader = testReader();
    final result = await store.save([
      SavedDevice(
        identity: reader,
        configuration: DeviceConfiguration({
          'ftpPassword': 'hunter2',
          'apiKey': 'hunter3',
          'host': 'h',
          'ftp': {'password': 'hunter4', 'user': 'u'},
        }),
      ),
    ]);
    expect(result.written, isTrue);
    expect(
      result.droppedSecretKeys,
      containsAll([
        '${reader.id}/ftpPassword',
        '${reader.id}/apiKey',
        '${reader.id}/ftp/password',
      ]),
    );
    final raw = (await rawValue())!;
    expect(raw.contains('hunter'), isFalse);
    expect(raw.contains('ftpPassword'), isFalse);
    final values = store.load().devices.single.configuration!.values;
    expect(values['host'], 'h');
    expect(values['ftp'], {'user': 'u'});
    expect(values.containsKey('apiKey'), isFalse);
  });

  test('a newer schema is preserved and saving is refused', () async {
    const newer = '{"schemaVersion":99,"devices":[]}';
    final store = await storeWith({DeviceRegistryStore.key: newer});
    expect(store.load().preserved, isTrue);
    final result = await store.save([SavedDevice(identity: testCamera())]);
    expect(result.written, isFalse);
    expect(result.refusal, isNotNull);
    expect(await rawValue(), newer);
  });

  test('corrupt data is preserved, not overwritten', () async {
    const corrupt = '{not json';
    final store = await storeWith({DeviceRegistryStore.key: corrupt});
    expect(store.load().preserved, isTrue);
    final result = await store.save([]);
    expect(result.written, isFalse);
    expect(await rawValue(), corrupt);
  });

  test('one unreadable entry is skipped, the others load', () async {
    final store = await storeWith({
      DeviceRegistryStore.key:
          '{"schemaVersion":1,"devices":[{"id":"bad"},'
          '{"id":"a","manufacturer":"M","model":"X",'
          '"interfaceType":"usb","transport":"uvc","serialNumber":"S"}]}',
    });
    final result = store.load();
    expect(result.devices, hasLength(1));
    expect(result.devices.single.identity.id, 'a');
    expect(result.warning, contains('1 saved device'));
    expect(result.preserved, isFalse);
  });

  test('an entry with a wrongly typed field is skipped', () async {
    final store = await storeWith({
      DeviceRegistryStore.key:
          '{"schemaVersion":1,"devices":[{"id":"a","manufacturer":"M",'
          '"model":"X","interfaceType":"usb","transport":"uvc","port":"x"}]}',
    });
    final result = store.load();
    expect(result.devices, isEmpty);
    expect(result.warning, contains('1 saved device'));
  });

  test('secrets stored by an older file are stripped on load', () async {
    final store = await storeWith({
      DeviceRegistryStore.key:
          '{"schemaVersion":1,"devices":[{"id":"a","manufacturer":"M",'
          '"model":"X","interfaceType":"usb","transport":"uvc",'
          '"serialNumber":"S",'
          '"configuration":{"password":"p","host":"h"}}]}',
    });
    final values = store.load().devices.single.configuration!.values;
    expect(values.keys, ['host']);
  });

  test('values that cannot be stored are dropped and reported', () async {
    final store = await storeWith();
    final reader = testReader();
    final result = await store.save([
      SavedDevice(
        identity: reader,
        configuration: DeviceConfiguration({
          'bad': double.nan,
          'object': Object(),
          'good': 1,
        }),
      ),
    ]);
    expect(result.written, isTrue);
    expect(
      result.droppedUnsupported,
      containsAll(['${reader.id}/bad', '${reader.id}/object']),
    );
    final values = store.load().devices.single.configuration!.values;
    expect(values, {'good': 1});
  });

  test('duplicate ids collapse to one device on save', () async {
    final store = await storeWith();
    final reader = testReader();
    await store.save([
      SavedDevice(identity: reader, backendId: 'first'),
      SavedDevice(identity: reader, backendId: 'second'),
    ]);
    final devices = store.load().devices;
    expect(devices, hasLength(1));
    expect(devices.single.backendId, 'second');
  });
}
