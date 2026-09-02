import 'package:permission_handler/permission_handler.dart';

enum PermissionState { granted, denied, permanentlyDenied }

/// Centralizes runtime permission requests so screens don't call
/// `permission_handler` directly. Kept intentionally small: only the
/// camera needs an explicit pre-flight check in this app.
///
/// Gallery access deliberately does NOT go through here — on Android 13+,
/// `image_picker`'s multi-image picker uses the system Photo Picker, which
/// requires no runtime permission at all, and requesting one anyway would
/// be a needless over-broad prompt. On older Android/iOS, `image_picker`
/// requests what it needs internally and surfaces a `PlatformException`
/// if denied, which the gallery screen already handles.
class PermissionService {
  PermissionService._();

  static Future<PermissionState> ensureCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) return PermissionState.granted;

    if (status.isPermanentlyDenied) return PermissionState.permanentlyDenied;

    final result = await Permission.camera.request();
    if (result.isGranted) return PermissionState.granted;
    if (result.isPermanentlyDenied) return PermissionState.permanentlyDenied;
    return PermissionState.denied;
  }

  static Future<PermissionState> ensureStoragePermission() async {
    // For Android 11+ (API 30+), standard `Permission.storage` is not enough 
    // to write back to external folders like Downloads. We need All Files Access.
    if (await Permission.manageExternalStorage.isRestricted) {
      // Legacy Android or restricted platform
      var status = await Permission.storage.status;
      if (status.isGranted) return PermissionState.granted;
      final result = await Permission.storage.request();
      return result.isGranted ? PermissionState.granted : PermissionState.denied;
    }

    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return PermissionState.granted;

    // This will open the "All Files Access" system settings page on Android 11+
    final result = await Permission.manageExternalStorage.request();
    if (result.isGranted) return PermissionState.granted;

    if (result.isPermanentlyDenied) return PermissionState.permanentlyDenied;
    return PermissionState.denied;
  }

  static Future<void> openSettings() => openAppSettings();
}
