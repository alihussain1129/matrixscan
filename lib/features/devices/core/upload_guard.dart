/// Image extensions the FTP receiver accepts. Adjust to what the reader sends.
const Set<String> kAllowedUploadExtensions = {
  'jpg',
  'jpeg',
  'png',
  'bmp',
  'tif',
  'tiff',
};

/// Largest single upload the receiver will buffer.
const int kMaxUploadBytes = 20 * 1024 * 1024;

/// Returns a safe lowercase extension for an uploaded file name, or null if
/// the name has no extension or the extension is not on the allow list.
///
/// Only the part after the last path separator is considered, and the result
/// always comes from [allowed], so it can never contain path characters.
String? safeUploadExtension(
  String fileName, {
  Set<String> allowed = kAllowedUploadExtensions,
}) {
  final base = fileName.split(RegExp(r'[\\/]')).last;
  final dot = base.lastIndexOf('.');
  if (dot < 0 || dot == base.length - 1) return null;
  final ext = base.substring(dot + 1).toLowerCase();
  return allowed.contains(ext) ? ext : null;
}
