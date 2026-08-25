import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'camera_config.dart';

/// Wraps [CameraController] lifecycle (init/dispose) and exposes a simple
/// `capture()` call that returns an [XFile].
///
/// Concurrency safety (fixed after code review):
/// - `initialize()` is re-entrant safe: if called while a previous call is
///   still in flight, the second caller awaits the SAME in-flight future
///   instead of racing a second `CameraController` into existence.
/// - Any existing controller is disposed BEFORE a new one is created, so
///   two sequential `initialize()` calls (e.g. triggered by Flutter's
///   well-known "extra resumed event on cold start" lifecycle quirk) can
///   never leak a hardware camera handle / the plugin's internal
///   orientation `BroadcastReceiver` — which is the actual source of the
///   `IntentReceiverLeaked` Android log warning.
/// - `dispose()` only nulls out `_controller` if it's still the exact
///   instance it just disposed — never clobbers a controller that a
///   concurrent `initialize()` call assigned while this dispose was
///   awaiting.
class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  Future<void>? _inFlightInit;

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  /// Discovers available cameras and initializes the rear camera
  /// (falls back to the first available camera).
  Future<void> initialize() {
    // Re-entrancy guard: a caller that arrives while a previous
    // initialize() is still running joins that same future rather than
    // starting a second, racing CameraController.
    final inFlight = _inFlightInit;
    if (inFlight != null) return inFlight;

    final future = _doInitialize();
    _inFlightInit = future;
    return future.whenComplete(() => _inFlightInit = null);
  }

  Future<void> _doInitialize() async {
    // Dispose any previous controller FIRST — never overwrite a live
    // controller reference without releasing its hardware/OS resources.
    await _disposeCurrent();

    _cameras = await availableCameras();
    if (_cameras.isEmpty) {
      throw CameraException('no_camera', 'Cihazda kullanılabilir kamera bulunamadı.');
    }

    final rearCamera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    final newController = CameraController(
      rearCamera,
      CameraConfig.resolutionPreset,
      enableAudio: CameraConfig.enableAudio,
      imageFormatGroup: CameraConfig.imageFormatGroup,
    );

    await newController.initialize();
    _controller = newController;
  }

  /// Captures a still photo. Returns the resulting [XFile] (a lightweight
  /// path/bytes wrapper — the actual image lives in the OS temp directory
  /// until it is explicitly persisted or sent to the AI service).
  Future<XFile> capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('CameraService.capture() called before initialize()');
    }
    if (controller.value.isTakingPicture) {
      throw StateError('Capture already in progress');
    }
    return controller.takePicture();
  }

  Future<void> _disposeCurrent() async {
    final toDispose = _controller;
    if (toDispose == null) return;
    // Clear the field BEFORE awaiting so nothing else can hand out this
    // controller mid-disposal, then dispose it.
    _controller = null;
    await toDispose.dispose();
  }

  Future<void> dispose() async {
    // If an initialize() is in flight, let it finish first so we don't
    // dispose a controller that's mid-construction, then clean up
    // whatever it (or a prior call) left behind.
    if (_inFlightInit != null) {
      try {
        await _inFlightInit;
      } catch (_) {
        // Initialization failed on its own — nothing to dispose from it.
      }
    }
    await _disposeCurrent();
  }

  @visibleForTesting
  List<CameraDescription> get debugCameras => _cameras;
}
