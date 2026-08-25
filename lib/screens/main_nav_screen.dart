import 'package:flutter/material.dart';
import 'camera_screen.dart';
import 'gallery_screen.dart';

/// Hosts the Kamera / Galeri tabs. Each tab keeps its own state alive
/// via [IndexedStack] so switching tabs doesn't reset capture/selection.
///
/// Note: CameraScreen/GalleryScreen each provide their own [Scaffold]
/// (they need independent `endDrawer`s for the settings menu), so this
/// widget intentionally stays a plain container rather than nesting a
/// second Scaffold around them.
class MainNavScreen extends StatefulWidget {
  const MainNavScreen({super.key});

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen> {
  int _index = 0;

  void _switchTab(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: _index,
      children: [
        CameraScreen(onSwitchTab: _switchTab),
        GalleryScreen(onSwitchTab: _switchTab),
      ],
    );
  }
}
