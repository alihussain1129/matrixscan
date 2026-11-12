import 'dart:async';
import 'dart:io' show Directory, Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show FrameTiming;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/config/config_controller.dart';
import 'core/config/config_provider.dart';
import 'core/config/config_store.dart';
import 'core/crash/auto_restart.dart';
import 'core/crash/crash_handlers.dart';
import 'core/crash/crash_log.dart';
import 'core/crash/restart_policy.dart';
import 'features/devices/camera/controller_camera_port.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final startupClock = Stopwatch()..start();
  // Fonts ship in assets/google_fonts so every platform looks the same offline.
  GoogleFonts.config.allowRuntimeFetching = false;
  if (Platform.isAndroid) {
    // Warm CameraX up now so the scanner does not wait for it after the first
    // frame (about 1.7 s on the A12). The result is not needed here.
    unawaited(availableCameras().then<void>((_) {}, onError: (Object _) {}));
  }
  // The mobile scanner is portrait-only for now; desktop is free to resize.
  if (Platform.isAndroid || Platform.isIOS) {
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]).catchError((Object _) {}),
    );
  }
  ConfigStore? configStore;
  Directory? supportDir;
  try {
    supportDir = await getApplicationSupportDirectory();
    configStore = ConfigStore(supportDir);
  } catch (_) {}
  debugPrint(
    '[EXALTED][STARTUP] support directory ready at '
    '${startupClock.elapsedMilliseconds}ms',
  );
  final startup = await loadStartupConfig(
    dir: configStore?.dir,
    store: configStore,
  );
  debugPrint(
    '[EXALTED][STARTUP] configuration loaded at '
    '${startupClock.elapsedMilliseconds}ms',
  );
  for (final n in startup.notes) {
    debugPrint('[CONFIG] $n');
  }
  if (supportDir != null) {
    final dir = supportDir;
    final sc = startup.config.startup;
    final restarter =
        (sc.autoRestart && (Platform.isLinux || Platform.isWindows))
        ? AutoRestarter(
            policy: RestartPolicy(
              enabled: true,
              maxPerHour: sc.maxRestartsPerHour,
            ),
            store: RestartHistoryStore(() async => dir),
            log: (m) => debugPrint('[RESTART] $m'),
          )
        : null;
    installCrashHandlers(
      CrashLog(() async => dir),
      onFatal: restarter == null
          ? null
          : () => unawaited(restarter.handleFatal()),
    );
  }
  void onFrameTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    WidgetsBinding.instance.removeTimingsCallback(onFrameTimings);
    final first = timings.first;
    debugPrint(
      '[EXALTED][STARTUP] first frame build '
      '${first.buildDuration.inMicroseconds}µs, raster '
      '${first.rasterDuration.inMicroseconds}µs',
    );
  }

  WidgetsBinding.instance.addTimingsCallback(onFrameTimings);
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
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final dartStartupMicros = startupClock.elapsedMicroseconds;
    debugPrint(
      '[EXALTED][STARTUP] first frame after Dart entry in '
      '$dartStartupMicrosµs (${dartStartupMicros / 1000}ms)',
    );
  });
}
