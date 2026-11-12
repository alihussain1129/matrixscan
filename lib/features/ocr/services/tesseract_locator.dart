import 'dart:io';

/// A discovered Tesseract installation and the language data it can use.
class TesseractInstallation {
  const TesseractInstallation({
    required this.executable,
    required this.languages,
    this.environment,
  });

  final String executable;
  final Set<String> languages;
  final Map<String, String>? environment;

  bool supportsLanguage(String language) => languages.contains(language);

  List<String> get displayLanguages {
    final result = languages.where((language) => language != 'osd').toList()
      ..sort();
    return result;
  }
}

/// One discovery path shared by still-image OCR, live OCR and desktop status.
class TesseractLocator {
  TesseractLocator._();

  static Set<String> parseLanguages(String output) {
    final result = <String>{};
    for (final rawLine in output.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.toLowerCase().startsWith('list of')) continue;
      final language = line.split(RegExp(r'\s+')).first.trim();
      if (RegExp(r'^[A-Za-z0-9_]+$').hasMatch(language)) {
        result.add(language);
      }
    }
    return result;
  }

  static String _join(String base, List<String> parts, String separator) {
    final prefix = base.endsWith(separator) ? base : '$base$separator';
    return '$prefix${parts.join(separator)}';
  }

  /// Builds search paths independently of the host OS.
  ///
  /// This lets Windows path selection be unit-tested on Linux/macOS without
  /// attempting to execute a Windows binary on the test host.
  static List<String> buildCandidates({
    String? customExecutablePath,
    String? appDirectory,
    required bool isWindows,
    required bool isLinux,
    required bool isMacOS,
    required String pathSeparator,
    Map<String, String> environment = const {},
  }) {
    final candidates = <String>[];
    final seen = <String>{};

    void add(String? candidate) {
      if (candidate == null || candidate.trim().isEmpty) return;
      final value = candidate.trim().replaceAll('"', '');
      final key = isWindows ? value.toLowerCase() : value;
      if (seen.add(key)) candidates.add(value);
    }

    add(customExecutablePath);

    if (appDirectory != null && appDirectory.isNotEmpty) {
      if (isWindows) {
        add(_join(appDirectory, ['tesseract', 'tesseract.exe'], pathSeparator));
        add(_join(appDirectory, ['tesseract.exe'], pathSeparator));
      } else if (isLinux || isMacOS) {
        add(_join(appDirectory, ['tesseract', 'tesseract'], pathSeparator));
        add(_join(appDirectory, ['tesseract'], pathSeparator));
      }
    }

    if (isWindows) {
      add(r'C:\Program Files\Tesseract-OCR\tesseract.exe');
      add(r'C:\Program Files (x86)\Tesseract-OCR\tesseract.exe');
      final programFiles = environment['ProgramFiles'];
      final programFilesX86 = environment['ProgramFiles(x86)'];
      if (programFiles != null) {
        add(
          _join(programFiles, [
            'Tesseract-OCR',
            'tesseract.exe',
          ], pathSeparator),
        );
      }
      if (programFilesX86 != null) {
        add(
          _join(programFilesX86, [
            'Tesseract-OCR',
            'tesseract.exe',
          ], pathSeparator),
        );
      }
    } else if (isLinux) {
      add('/usr/bin/tesseract');
      add('/usr/local/bin/tesseract');
      add('/snap/bin/tesseract');
    } else if (isMacOS) {
      add('/opt/homebrew/bin/tesseract');
      add('/usr/local/bin/tesseract');
    }

    return candidates;
  }

  static String _parentDirectory(String executable, String separator) {
    final slash = executable.lastIndexOf('/');
    final backslash = executable.lastIndexOf('\\');
    final index = slash > backslash ? slash : backslash;
    if (index < 0) return '.';
    if (index == 0) return separator;
    return executable.substring(0, index);
  }

  /// Uses a sibling tessdata directory for portable/bundled installations.
  /// Tesseract 5 expects TESSDATA_PREFIX to be the tessdata folder itself.
  /// The separator and existence check are injectable for Windows path tests.
  static Map<String, String>? environmentForExecutable(
    String executable, {
    String? pathSeparator,
    bool Function(String path)? directoryExists,
  }) {
    final separator = pathSeparator ?? Platform.pathSeparator;
    final parent = _parentDirectory(executable, separator);
    final tessdata = parent.endsWith(separator)
        ? '${parent}tessdata'
        : '$parent${separator}tessdata';
    final exists = directoryExists != null
        ? directoryExists(tessdata)
        : Directory(tessdata).existsSync();
    if (!exists) return null;
    return {'TESSDATA_PREFIX': tessdata};
  }

  static Future<TesseractInstallation?> discover({
    String? customExecutablePath,
    String? appDirectory,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final isWindows = Platform.isWindows;
    final separator = Platform.pathSeparator;
    final appDir =
        appDirectory ?? File(Platform.resolvedExecutable).parent.path;
    final candidates = buildCandidates(
      customExecutablePath: customExecutablePath,
      appDirectory: appDir,
      isWindows: isWindows,
      isLinux: Platform.isLinux,
      isMacOS: Platform.isMacOS,
      pathSeparator: separator,
      environment: Platform.environment,
    );
    final seen = candidates
        .map((path) => isWindows ? path.toLowerCase() : path)
        .toSet();

    // PATH is checked last, after portable and standard installation paths.
    try {
      final result = await Process.run(isWindows ? 'where' : 'which', [
        'tesseract',
      ]).timeout(timeout);
      if (result.exitCode == 0) {
        for (final line in result.stdout.toString().split(RegExp(r'\r?\n'))) {
          final path = line.trim().replaceAll('"', '');
          final key = isWindows ? path.toLowerCase() : path;
          if (path.isNotEmpty && seen.add(key)) candidates.add(path);
        }
      }
    } catch (_) {
      // A missing `where`/`which` command is not fatal; explicit paths remain.
    }

    for (final executable in candidates) {
      if (!await File(executable).exists()) continue;
      final environment = environmentForExecutable(
        executable,
        pathSeparator: separator,
      );
      try {
        final result = await Process.run(executable, [
          '--list-langs',
        ], environment: environment).timeout(timeout);
        if (result.exitCode != 0) continue;
        return TesseractInstallation(
          executable: executable,
          languages: parseLanguages(result.stdout.toString()),
          environment: environment,
        );
      } catch (_) {
        // Skip stale, non-executable or incompatible candidates.
      }
    }
    return null;
  }
}
