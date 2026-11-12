import 'dart:ffi';
import 'dart:io';

/// One location the loader tried, and what happened there.
class NativeLibraryAttempt {
  const NativeLibraryAttempt(this.target, this.outcome);

  final String target;
  final String outcome;

  @override
  String toString() => '$target -> $outcome';
}

/// The native library could not be loaded from any known location.
///
/// [toString] lists every location that was tried so a missing or misplaced
/// library can be diagnosed without a debugger.
class NativeLibraryException implements Exception {
  NativeLibraryException(this.libraryName, this.attempts);

  final String libraryName;
  final List<NativeLibraryAttempt> attempts;

  /// One-line form for repeated log output.
  String get summary =>
      'could not load $libraryName from any of ${attempts.length} locations';

  @override
  String toString() {
    final buffer = StringBuffer('Failed to load native library "$libraryName".')
      ..write(' Locations tried:');
    for (final attempt in attempts) {
      buffer.write('\n  - $attempt');
    }
    buffer.write(
      '\nSet ${NativeLibraryLoader.overrideVariable} to the full path of '
      '$libraryName (or its directory), or rebuild the native core.',
    );
    return buffer.toString();
  }
}

/// A successfully opened native library and where it came from.
class LoadedNativeLibrary {
  const LoadedNativeLibrary(this.library, this.path);

  final DynamicLibrary library;

  /// The path that was opened, or the bare library name when the operating
  /// system's own loader resolved it.
  final String path;
}

typedef NativeLibraryOpener = DynamicLibrary Function(String path);
typedef NativeFileProbe = bool Function(String path);

/// Finds and opens `libexalted_ffi.so` / `exalted_ffi.dll`.
///
/// A bare-name `DynamicLibrary.open` depends on loader search rules (RPATH,
/// RUNPATH, `LD_LIBRARY_PATH`, the working directory) that differ between a
/// packaged bundle, `flutter run` and `flutter test`. This loader tries
/// explicit absolute locations first and only then falls back to the bare
/// name, and it reports every location it tried when nothing works.
abstract final class NativeLibraryLoader {
  /// Environment variable naming the library file, or the directory holding
  /// it. Intended for tests and unusual deployments.
  static const String overrideVariable = 'EXALTED_FFI_PATH';

  static String platformLibraryName({bool? isWindows}) {
    return (isWindows ?? Platform.isWindows)
        ? 'exalted_ffi.dll'
        : 'libexalted_ffi.so';
  }

  /// Locations to try, in priority order. The last entry is always the bare
  /// library name, left to the operating system's loader.
  ///
  /// Development fallbacks (a `build/` bundle under [workingDirectory]) are
  /// only added when [allowDevelopmentPaths] is true. Release and profile
  /// builds must not load a library relative to the working directory.
  static List<String> candidates({
    required String libraryName,
    required String separator,
    String? override,
    String? executablePath,
    String? workingDirectory,
    bool isAndroid = false,
    bool isWindows = false,
    bool allowDevelopmentPaths = false,
  }) {
    final result = <String>[];

    void add(String path) {
      if (path.isNotEmpty && !result.contains(path)) result.add(path);
    }

    if (override != null && override.isNotEmpty) {
      final looksLikeFile =
          override.endsWith('.so') ||
          override.endsWith('.dll') ||
          override.endsWith('.dylib');
      add(
        looksLikeFile ? override : _joinAll([override, libraryName], separator),
      );
    }

    // Android resolves the library from the APK's native library directory by
    // bare name; there is no executable-relative layout to search.
    if (!isAndroid && executablePath != null && executablePath.isNotEmpty) {
      final dir = _dirname(executablePath, separator);
      if (dir.isNotEmpty) {
        if (isWindows) {
          add(_joinAll([dir, libraryName], separator));
        } else {
          add(_joinAll([dir, 'lib', libraryName], separator));
          add(_joinAll([dir, libraryName], separator));
        }
      }
    }

    if (!isAndroid &&
        allowDevelopmentPaths &&
        workingDirectory != null &&
        workingDirectory.isNotEmpty) {
      const modes = ['release', 'debug', 'profile'];
      const arches = ['x64', 'arm64'];
      for (final mode in modes) {
        for (final arch in arches) {
          if (isWindows) {
            final windowsMode = '${mode[0].toUpperCase()}${mode.substring(1)}';
            add(
              _joinAll([
                workingDirectory,
                'build',
                'windows',
                arch,
                'runner',
                windowsMode,
                libraryName,
              ], separator),
            );
          } else {
            add(
              _joinAll([
                workingDirectory,
                'build',
                'linux',
                arch,
                mode,
                'bundle',
                'lib',
                libraryName,
              ], separator),
            );
          }
        }
      }
    }

    // Always last: let the operating system's loader try the bare name.
    add(libraryName);
    return result;
  }

  /// Opens the native library from the first location that works.
  ///
  /// Every parameter exists so the search can be tested without touching the
  /// real file system or loader; production callers pass none of them.
  static LoadedNativeLibrary open({
    String? libraryName,
    NativeLibraryOpener? opener,
    NativeFileProbe? fileExists,
    Map<String, String>? environment,
    String? executablePath,
    String? workingDirectory,
    String? separator,
    bool? isAndroid,
    bool? isWindows,
    bool? allowDevelopmentPaths,
  }) {
    final windows = isWindows ?? Platform.isWindows;
    final name = libraryName ?? platformLibraryName(isWindows: windows);
    final openLibrary = opener ?? DynamicLibrary.open;
    final exists = fileExists ?? (String path) => File(path).existsSync();
    final env = environment ?? Platform.environment;

    final locations = candidates(
      libraryName: name,
      separator: separator ?? Platform.pathSeparator,
      override: env[overrideVariable],
      executablePath: executablePath ?? Platform.resolvedExecutable,
      workingDirectory: workingDirectory ?? Directory.current.path,
      isAndroid: isAndroid ?? Platform.isAndroid,
      isWindows: windows,
      allowDevelopmentPaths:
          allowDevelopmentPaths ??
          !const bool.fromEnvironment('dart.vm.product'),
    );

    final attempts = <NativeLibraryAttempt>[];
    for (final target in locations) {
      final isBareName = target == name;
      if (!isBareName && !exists(target)) {
        attempts.add(NativeLibraryAttempt(target, 'not found'));
        continue;
      }
      try {
        return LoadedNativeLibrary(openLibrary(target), target);
      } catch (e) {
        attempts.add(NativeLibraryAttempt(target, 'load error: $e'));
      }
    }
    throw NativeLibraryException(name, attempts);
  }

  static String _joinAll(List<String> parts, String separator) {
    final buffer = StringBuffer();
    for (final part in parts) {
      if (part.isEmpty) continue;
      if (buffer.isNotEmpty && !buffer.toString().endsWith(separator)) {
        buffer.write(separator);
      }
      buffer.write(part);
    }
    return buffer.toString();
  }

  static String _dirname(String path, String separator) {
    final index = path.lastIndexOf(separator);
    if (index <= 0) return '';
    return path.substring(0, index);
  }
}
