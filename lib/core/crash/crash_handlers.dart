import 'dart:async';

import 'package:flutter/foundation.dart';

import 'crash_log.dart';

/// Writes uncaught errors to the crash log and then lets them behave exactly
/// as before (console output, previous handlers). onFatal runs after an
/// uncaught async (platform) error has been written to the log. Widget errors
/// never call it.
void installCrashHandlers(CrashLog log, {void Function()? onFatal}) {
  final previousFlutter = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    unawaited(log.record(details.exception, details.stack, source: 'flutter'));
    if (previousFlutter != null) {
      previousFlutter(details);
    } else {
      FlutterError.presentError(details);
    }
  };
  final previousPlatform = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    unawaited(
      log
          .record(error, stack, source: 'platform')
          .then((_) => onFatal?.call()),
    );
    return previousPlatform?.call(error, stack) ?? false;
  };
}
