import 'package:camera/camera.dart';

/// Static configuration for the camera capture pipeline.
class CameraConfig {
  CameraConfig._();

  static const ResolutionPreset resolutionPreset = ResolutionPreset.high;
  static const ImageFormatGroup imageFormatGroup = ImageFormatGroup.jpeg;

  /// Keep audio off — this is a document scanner, not a video recorder.
  static const bool enableAudio = false;
}
