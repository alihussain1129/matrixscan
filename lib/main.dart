import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app.dart';
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
  runApp(
    ProviderScope(
      overrides: [scannerCameraPortOverride],
      child: const ExaltedApp(),
    ),
  );
}
