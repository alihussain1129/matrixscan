import 'package:flutter/material.dart';

import 'core/navigation/exalted_shell.dart';

/// App shell. All layout logic lives in [ExaltedShell].
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) => const ExaltedShell();
}
