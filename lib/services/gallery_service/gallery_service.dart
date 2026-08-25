import 'package:image_picker/image_picker.dart';

/// Thin wrapper around [ImagePicker] for selecting one or more receipt
/// photos from the device's photo library.
class GalleryService {
  final _picker = ImagePicker();

  /// Opens the native multi-image picker. Returns an empty list if the
  /// user cancels.
  Future<List<XFile>> pickImages({int? limit}) async {
    final images = await _picker.pickMultiImage(
      imageQuality: 90,
      limit: limit,
    );
    return images;
  }

  /// Opens the native single-image picker (used for the "quick add" flow).
  Future<XFile?> pickSingleImage() {
    return _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
  }
}
