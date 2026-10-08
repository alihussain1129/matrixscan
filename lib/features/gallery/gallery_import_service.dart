import 'package:image_picker/image_picker.dart';

/// Outcome of opening the photo picker.
/// Both fields null means the user cancelled.
class PickedImage {
  const PickedImage({this.path, this.error});

  final String? path;
  final String? error;
}

/// Opens the Android system photo picker. No storage permission is needed.
class GalleryImportService {
  GalleryImportService({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<PickedImage> pickImage() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return const PickedImage();
      return PickedImage(path: file.path);
    } catch (_) {
      return const PickedImage(error: "Couldn't open your photos. Try again.");
    }
  }
}
