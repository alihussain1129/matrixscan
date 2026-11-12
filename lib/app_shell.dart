import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'core/navigation/exalted_shell.dart';
import 'core/navigation/mobile_shell.dart';

/// Chooses the shell by platform, not by window width: phones get the mobile
/// shell, Windows and Linux get the workstation shell.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  static bool get isPhonePlatform => Platform.isAndroid || Platform.isIOS;

  @override
  Widget build(BuildContext context) =>
      isPhonePlatform ? const MobileShell() : const ExaltedShell();
}
