import 'dart:async';
import 'dart:io' show Directory, Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/config/config_controller.dart';
import 'core/config/config_provider.dart';
import 'core/config/config_store.dart';
import 'core/crash/crash_handlers.dart';
import 'core/crash/crash_log.dart';
import 'features/devices/camera/controller_camera_port.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fonts ship in assets/google_fonts so every platform looks the same offline.
  GoogleFonts.config.allowRuntimeFetching = false;
  if (Platform.isAndroid) {
    // Warm CameraX up now so the scanner does not wait for it after the first
    // frame (about 1.7 s on the A12). The result is not needed here.
    unawaited(availableCameras().then<void>((_) {}, onError: (Object _) {}));
  }
  // The mobile scanner is portrait-only for now; desktop is free to resize.
  if (Platform.isAndroid || Platform.isIOS) {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
  }
  ConfigStore? configStore;
  Directory? supportDir;
  try {
    supportDir = await getApplicationSupportDirectory();
    configStore = ConfigStore(supportDir);
  } catch (_) {}
  if (supportDir != null) {
    final crashDir = supportDir;
    installCrashHandlers(CrashLog(() async => crashDir));
  }
  final startup = await loadStartupConfig(
    dir: configStore?.dir,
    store: configStore,
  );
  for (final n in startup.notes) {
    debugPrint('[CONFIG] $n');
  }
  runApp(
    ProviderScope(
      overrides: [
        scannerCameraPortOverride,
        configProvider.overrideWithValue(startup.config),
        configStoreProvider.overrideWithValue(configStore),
      ],
      child: const ExaltedApp(),
    ),
  );
}
