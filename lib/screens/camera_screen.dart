import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../services/camera_service/camera_service.dart';
import '../services/permission_service.dart';
import '../theme/app_theme.dart';
import '../widgets/dashed_border_box.dart';
import '../widgets/screen_header.dart';
import 'processing_screen.dart';
import 'settings_screen.dart';

/// Matches Figma node `screen-camera` (56623:7498) with a real camera
/// preview wired in via [CameraService]. Captured photos are collected as
/// [XFile]s and handed off to [ProcessingScreen] on "Bitir".
class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.onSwitchTab,
  });

  /// Called with `1` when the user taps the "Galeri" tab in the bottom nav.
  final ValueChanged<int> onSwitchTab;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  final _cameraService = CameraService();
  final _capturedPhotos = <XFile>[];

  bool _initializing = true;
  String? _initError;
  bool _permissionPermanentlyDenied = false;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    setState(() {
      _initializing = true;
      _initError = null;
      _permissionPermanentlyDenied = false;
    });

    final permission = await PermissionService.ensureCameraPermission();
    if (permission != PermissionState.granted) {
      setState(() {
        _initializing = false;
        _permissionPermanentlyDenied = permission == PermissionState.permanentlyDenied;
        _initError = permission == PermissionState.permanentlyDenied
            ? 'Kamera izni reddedildi. Devam etmek için ayarlardan izin verin.'
            : 'Fiş taramak için kamera iznine ihtiyaç var.';
      });
      return;
    }

    try {
      await _cameraService.initialize();
    } catch (e) {
      _initError = 'Kameraya erişilemedi. Lütfen tekrar deneyin.';
    }
    if (mounted) setState(() => _initializing = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Free the camera when backgrounded, re-init on resume — avoids
    // holding an exclusive camera lock while the app isn't visible.
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _cameraService.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _onShutterPressed() async {
    if (_capturing || !_cameraService.isInitialized) return;
    setState(() => _capturing = true);
    try {
      final file = await _cameraService.capture();
      setState(() => _capturedPhotos.add(file));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fotoğraf çekilemedi, tekrar deneyin.')),
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _onDeletePressed() {
    if (_capturedPhotos.isEmpty) return;
    setState(() => _capturedPhotos.removeLast());
  }

  void _onFinishPressed() {
    if (_capturedPhotos.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProcessingScreen(images: List.of(_capturedPhotos)),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCamera,
      endDrawer: const SettingsDrawer(),
      body: Builder(
        builder: (context) => Stack(
          fit: StackFit.expand,
          children: [
            _CameraPreviewBackground(
              controller: _cameraService.controller,
              initializing: _initializing,
              error: _initError,
              permanentlyDenied: _permissionPermanentlyDenied,
              onRetry: _initCamera,
              onOpenSettings: PermissionService.openSettings,
            ),
            SafeArea(
              child: Column(
                children: [
                  ScreenHeader(
                    leftIcon: Icons.settings_outlined,
                    onLeftTap: () => Scaffold.of(context).openEndDrawer(),
                    title: 'Kamera',
                    titleIcon: Icons.receipt_long,
                    onTitleTap: () => widget.onSwitchTab(1),
                    rightIcon: Icons.history,
                    onRightTap: () {},
                  ),
                  const Spacer(),
                  Center(
                    child: DashedBorderBox(
                      width: 280,
                      height: 380,
                      color: AppColors.primary,
                      borderRadius: 16,
                    ),
                  ),
                  const Spacer(),
                  _ControlsContainer(
                    capturedPhotos: _capturedPhotos,
                    capturing: _capturing,
                    onShutter: _onShutterPressed,
                    onDelete: _onDeletePressed,
                    onFinish: _onFinishPressed,
                    onSwitchTab: widget.onSwitchTab,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraPreviewBackground extends StatelessWidget {
  const _CameraPreviewBackground({
    required this.controller,
    required this.initializing,
    required this.error,
    required this.permanentlyDenied,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final CameraController? controller;
  final bool initializing;
  final String? error;
  final bool permanentlyDenied;
  final VoidCallback onRetry;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Container(
        color: AppColors.bgCamera,
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_alt_outlined, size: 32, color: AppColors.textMuted),
              const SizedBox(height: 12),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () {
                  if (permanentlyDenied) {
                    onOpenSettings();
                  } else {
                    onRetry();
                  }
                },
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary),
                child: Text(permanentlyDenied ? 'Ayarları Aç' : 'Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }
    if (initializing || controller == null || !controller!.value.isInitialized) {
      return Container(
        color: AppColors.bgCamera,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(color: AppColors.primary),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller!.value.previewSize?.height ?? 1,
        height: controller!.value.previewSize?.width ?? 1,
        child: CameraPreview(controller!),
      ),
    );
  }
}

class _ControlsContainer extends StatelessWidget {
  const _ControlsContainer({
    required this.capturedPhotos,
    required this.capturing,
    required this.onShutter,
    required this.onDelete,
    required this.onFinish,
    required this.onSwitchTab,
  });

  final List<XFile> capturedPhotos;
  final bool capturing;
  final VoidCallback onShutter;
  final VoidCallback onDelete;
  final VoidCallback onFinish;
  final ValueChanged<int> onSwitchTab;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          _ThumbnailsRow(photos: capturedPhotos),
          const SizedBox(height: 20),
          _ShutterPanel(
            hasPhotos: capturedPhotos.isNotEmpty,
            capturing: capturing,
            onShutter: onShutter,
            onDelete: onDelete,
            onFinish: onFinish,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _ThumbnailsRow extends StatelessWidget {
  const _ThumbnailsRow({required this.photos});

  final List<XFile> photos;

  @override
  Widget build(BuildContext context) {
    // Show at most the 3 most-recent captures, the last one "active".
    final shown = photos.length.clamp(0, 3).toInt();
    if (shown == 0) return const SizedBox(height: 60);
    final visible = photos.sublist(photos.length - shown);

    return SizedBox(
      height: 60,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(visible.length, (i) {
          final isActive = i == visible.length - 1;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: isActive
                ? _ActiveThumbnail(file: visible[i])
                : _PlainThumbnail(file: visible[i]),
          );
        }),
      ),
    );
  }
}

class _PlainThumbnail extends StatelessWidget {
  const _PlainThumbnail({required this.file});
  final XFile file;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.5)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Image.file(File(file.path), fit: BoxFit.cover),
      ),
    );
  }
}

class _ActiveThumbnail extends StatelessWidget {
  const _ActiveThumbnail({required this.file});
  final XFile file;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        children: [
          Container(
            width: 60,
            height: 60,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary, width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(File(file.path), fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, size: 10, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShutterPanel extends StatelessWidget {
  const _ShutterPanel({
    required this.hasPhotos,
    required this.capturing,
    required this.onShutter,
    required this.onDelete,
    required this.onFinish,
  });

  final bool hasPhotos;
  final bool capturing;
  final VoidCallback onShutter;
  final VoidCallback onDelete;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _PillButton(
            icon: Icons.delete_outline,
            label: 'Sil',
            iconColor: AppColors.danger,
            textStyle: AppText.pillDanger,
            backgroundColor: AppColors.dangerSoft,
            borderColor: AppColors.dangerBorder,
            onTap: hasPhotos ? onDelete : null,
          ),
          _ShutterButton(onTap: capturing ? null : onShutter, busy: capturing),
          _PillButton(
            icon: Icons.check,
            iconTrailing: true,
            label: 'Bitir',
            iconColor: AppColors.primary,
            textStyle: AppText.pillPrimary,
            backgroundColor: AppColors.primarySofter,
            borderColor: AppColors.primary,
            onTap: hasPhotos ? onFinish : null,
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.textStyle,
    required this.backgroundColor,
    required this.borderColor,
    this.iconTrailing = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color iconColor;
  final TextStyle textStyle;
  final Color backgroundColor;
  final Color borderColor;
  final bool iconTrailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final children = [
      Icon(icon, size: 16, color: iconColor),
      const SizedBox(width: 6),
      Text(label, style: textStyle),
    ];
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: iconTrailing ? children.reversed.toList() : children,
            ),
          ),
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.onTap, this.busy = false});
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 76,
          height: 76,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
                )
              : Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
        ),
      ),
    );
  }
}
