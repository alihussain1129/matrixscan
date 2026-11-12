import 'dart:ffi';

import 'package:exalted/ffi/native_library_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('candidates', () {
    test('Linux bundle: lib/ beside the executable is tried first', () {
      final list = NativeLibraryLoader.candidates(
        libraryName: 'libexalted_ffi.so',
        separator: '/',
        executablePath: '/opt/exalted/exalted',
      );
      expect(list, [
        '/opt/exalted/lib/libexalted_ffi.so',
        '/opt/exalted/libexalted_ffi.so',
        'libexalted_ffi.so',
      ]);
    });

    test('Windows bundle: DLL sits beside the executable', () {
      final list = NativeLibraryLoader.candidates(
        libraryName: 'exalted_ffi.dll',
        separator: r'\',
        executablePath: r'C:\Program Files\Exalted\exalted.exe',
        isWindows: true,
      );
      expect(list, [
        r'C:\Program Files\Exalted\exalted_ffi.dll',
        'exalted_ffi.dll',
      ]);
    });

    test('Android relies on the APK loader: bare name only', () {
      final list = NativeLibraryLoader.candidates(
        libraryName: 'libexalted_ffi.so',
        separator: '/',
        executablePath: '/system/bin/app_process64',
        workingDirectory: '/',
        isAndroid: true,
        allowDevelopmentPaths: true,
      );
      expect(list, ['libexalted_ffi.so']);
    });

    test('override may be a file or a directory and wins over everything', () {
      final file = NativeLibraryLoader.candidates(
        libraryName: 'libexalted_ffi.so',
        separator: '/',
        override: '/custom/libexalted_ffi.so',
        executablePath: '/opt/exalted/exalted',
      );
      expect(file.first, '/custom/libexalted_ffi.so');

      final dir = NativeLibraryLoader.candidates(
        libraryName: 'libexalted_ffi.so',
        separator: '/',
        override: '/custom/native/',
        executablePath: '/opt/exalted/exalted',
      );
      expect(dir.first, '/custom/native/libexalted_ffi.so');
    });

    test('development paths are only added when explicitly allowed', () {
      final off = NativeLibraryLoader.candidates(
        libraryName: 'libexalted_ffi.so',
        separator: '/',
        workingDirectory: '/work/exalted',
      );
      expect(off, ['libexalted_ffi.so']);

      final on = NativeLibraryLoader.candidates(
        libraryName: 'libexalted_ffi.so',
        separator: '/',
        workingDirectory: '/work/exalted',
        allowDevelopmentPaths: true,
      );
      expect(
        on,
        contains(
          '/work/exalted/build/linux/x64/release/bundle/lib/libexalted_ffi.so',
        ),
      );
      expect(
        on,
        contains(
          '/work/exalted/build/linux/x64/debug/bundle/lib/libexalted_ffi.so',
        ),
      );
      expect(on.last, 'libexalted_ffi.so');
    });

    test('never contains duplicates', () {
      final list = NativeLibraryLoader.candidates(
        libraryName: 'libexalted_ffi.so',
        separator: '/',
        override: '/opt/exalted/lib/libexalted_ffi.so',
        executablePath: '/opt/exalted/exalted',
      );
      expect(list.toSet().length, list.length);
    });
  });

  group('open', () {
    // DynamicLibrary cannot be faked; the current process is a valid stand-in
    // for "a library that opened successfully".
    final stand = DynamicLibrary.process();

    test('uses the first location that exists and opens', () {
      final opened = <String>[];
      final loaded = NativeLibraryLoader.open(
        libraryName: 'libexalted_ffi.so',
        separator: '/',
        isAndroid: false,
        isWindows: false,
        executablePath: '/opt/exalted/exalted',
        workingDirectory: '/elsewhere',
        environment: const {},
        allowDevelopmentPaths: false,
        fileExists: (path) => path == '/opt/exalted/lib/libexalted_ffi.so',
        opener: (path) {
          opened.add(path);
          return stand;
        },
      );
      expect(loaded.path, '/opt/exalted/lib/libexalted_ffi.so');
      expect(opened, ['/opt/exalted/lib/libexalted_ffi.so']);
    });

    test('does not call the opener for absolute paths that do not exist', () {
      final opened = <String>[];
      final loaded = NativeLibraryLoader.open(
        libraryName: 'libexalted_ffi.so',
        separator: '/',
        isAndroid: false,
        isWindows: false,
        executablePath: '/opt/exalted/exalted',
        workingDirectory: '/elsewhere',
        environment: const {},
        allowDevelopmentPaths: false,
        fileExists: (_) => false,
        opener: (path) {
          opened.add(path);
          return stand;
        },
      );
      // Only the bare name reaches the opener.
      expect(opened, ['libexalted_ffi.so']);
      expect(loaded.path, 'libexalted_ffi.so');
    });

    test('EXALTED_FFI_PATH is honoured first', () {
      final loaded = NativeLibraryLoader.open(
        libraryName: 'libexalted_ffi.so',
        separator: '/',
        isAndroid: false,
        isWindows: false,
        executablePath: '/opt/exalted/exalted',
        workingDirectory: '/elsewhere',
        environment: const {
          NativeLibraryLoader.overrideVariable: '/test/build',
        },
        allowDevelopmentPaths: false,
        fileExists: (_) => true,
        opener: (_) => stand,
      );
      expect(loaded.path, '/test/build/libexalted_ffi.so');
    });

    test('falls through to later locations when an earlier one fails', () {
      final opened = <String>[];
      final loaded = NativeLibraryLoader.open(
        libraryName: 'libexalted_ffi.so',
        separator: '/',
        isAndroid: false,
        isWindows: false,
        executablePath: '/opt/exalted/exalted',
        workingDirectory: '/elsewhere',
        environment: const {},
        allowDevelopmentPaths: false,
        fileExists: (_) => true,
        opener: (path) {
          opened.add(path);
          if (path.contains('/lib/')) {
            throw ArgumentError('wrong ELF class');
          }
          return stand;
        },
      );
      expect(loaded.path, '/opt/exalted/libexalted_ffi.so');
      expect(opened.length, 2);
    });

    test('failure lists every location tried and the override hint', () {
      try {
        NativeLibraryLoader.open(
          libraryName: 'libexalted_ffi.so',
          separator: '/',
          isAndroid: false,
          isWindows: false,
          executablePath: '/opt/exalted/exalted',
          workingDirectory: '/elsewhere',
          environment: const {},
          allowDevelopmentPaths: false,
          fileExists: (_) => false,
          opener: (_) => throw ArgumentError('cannot open shared object'),
        );
        fail('expected a NativeLibraryException');
      } on NativeLibraryException catch (e) {
        expect(e.libraryName, 'libexalted_ffi.so');
        expect(e.attempts.length, 3);
        final text = e.toString();
        expect(text, contains('/opt/exalted/lib/libexalted_ffi.so'));
        expect(text, contains('not found'));
        expect(text, contains('cannot open shared object'));
        expect(text, contains(NativeLibraryLoader.overrideVariable));
        expect(e.summary, contains('3 locations'));
      }
    });
  });
}
