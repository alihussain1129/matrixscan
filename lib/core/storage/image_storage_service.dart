import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../config/data_directory_provider.dart';

/// Provides immutable local-first storage for scanned frames, OCR documents,
/// and camera CMOS images.
///
/// Images are permanently stored in the application's local media repository
/// until explicitly removed by the user.
class ImageStorageService {
  ImageStorageService({Future<Directory> Function()? directoryProvider})
    : _directoryProvider =
          directoryProvider ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directoryProvider;

  Directory? _mediaDir;

  /// Returns the base directory for permanently stored images.
  Future<Directory> getMediaDirectory() async {
    if (_mediaDir != null) return _mediaDir!;
    final base = await _directoryProvider();
    final dir = Directory('${base.path}${Platform.pathSeparator}exalted_media');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _mediaDir = dir;
    return dir;
  }

  /// Copies an external image file (e.g. from gallery, camera cache, or network download)
  /// into immutable storage, returning the permanent destination path.
  Future<String> persistSourceImage(
    String sourcePath, {
    String prefix = 'img',
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw FileSystemException('Source image does not exist', sourcePath);
    }

    final mediaDir = await getMediaDirectory();
    final ext = _getExtension(sourcePath);
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final destFileName = '${prefix}_$timestamp.$ext';
    final destFile = File(
      '${mediaDir.path}${Platform.pathSeparator}$destFileName',
    );

    await sourceFile.copy(destFile.path);
    return destFile.path;
  }

  /// Saves raw image bytes (e.g. from camera frame or Keyence CMOS buffer)
  /// to a permanent image file on disk.
  Future<String> saveImageBytes(
    Uint8List bytes, {
    String prefix = 'frame',
    String ext = 'jpg',
  }) async {
    final mediaDir = await getMediaDirectory();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final cleanExt = ext.startsWith('.') ? ext.substring(1) : ext;
    final destFileName = '${prefix}_$timestamp.$cleanExt';
    final destFile = File(
      '${mediaDir.path}${Platform.pathSeparator}$destFileName',
    );

    await destFile.writeAsBytes(bytes, flush: true);
    return destFile.path;
  }

  /// Safely deletes a stored image file from the media repository.
  Future<bool> deleteImage(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Calculates the total byte size of stored images.
  Future<int> calculateStorageSizeBytes() async {
    try {
      final dir = await getMediaDirectory();
      int total = 0;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  String _getExtension(String path) {
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex != -1 && dotIndex < path.length - 1) {
      final ext = path.substring(dotIndex + 1).toLowerCase();
      if (ext.length <= 5) return ext;
    }
    return 'jpg';
  }
}

final imageStorageServiceProvider = Provider<ImageStorageService>((ref) {
  return ImageStorageService(directoryProvider: ref.watch(dataDirectoryProvider));
});
