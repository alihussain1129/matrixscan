import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    // Warm CameraX up now so the scanner does not wait for it after the first
    // frame (about 1.7 s on the A12). The result is not needed here.
    unawaited(availableCameras().then<void>((_) {}, onError: (Object _) {}));
  }
  // The scanner is portrait-only for now.
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
  runApp(const ProviderScope(child: ExaltedApp()));
}
