import 'package:exalted/features/link/companion_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'desktop notifications default off while event categories default on',
    () async {
      SharedPreferences.setMockInitialValues({});

      expect(await CompanionNotifications.enabled(), isFalse);
      expect(
        await CompanionNotifications.preference(
          'companion.notifications.enabled',
        ),
        isFalse,
      );
      expect(
        await CompanionNotifications.preference(
          'companion.notifications.inspections',
        ),
        isTrue,
      );
    },
  );
}
