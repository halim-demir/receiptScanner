import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/gallery_service/gallery_service.dart';
import '../theme/app_theme.dart';
import '../widgets/screen_header.dart';
import 'processing_screen.dart';
import 'settings_screen.dart';

/// Matches Figma node `screen-gallery` (56623:7545). Images are picked
/// from the device photo library via [GalleryService] and selection state
/// tracks which ones will be sent to [ProcessingScreen].
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({
    super.key,
    required this.onSwitchTab,
  });

  final ValueChanged<int> onSwitchTab;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final _galleryService = GalleryService();
  final _images = <XFile>[];
  final _selected = <bool>[];

  int get _selectedCount => _selected.where((s) => s).length;

  void _toggle(int index) {
    setState(() => _selected[index] = !_selected[index]);
  }

  Future<void> _addFromGallery() async {
    final picked = await _galleryService.pickImages();
    if (picked.isEmpty) return;
    setState(() {
      _images.addAll(picked);
      _selected.addAll(List.filled(picked.length, true));
    });
  }

  void _continue() {
    if (_selectedCount == 0) return;
    final chosen = <XFile>[
      for (var i = 0; i < _images.length; i++)
        if (_selected[i]) _images[i],
    ];
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProcessingScreen(images: chosen)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      endDrawer: const SettingsDrawer(),
      body: Builder(
        builder: (context) => SafeArea(
          child: Column(
            children: [
              ScreenHeader(
                leftIcon: Icons.settings_outlined,
                onLeftTap: () => Scaffold.of(context).openEndDrawer(),
                title: 'Galeri',
                titleIcon: Icons.receipt_long,
                onTitleTap: () => widget.onSwitchTab(0),
                rightIcon: Icons.history,
                onRightTap: () {},
              ),
              Expanded(
                child: _images.isEmpty
                    ? _EmptyState(onAdd: _addFromGallery)
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: GridView.builder(
                          itemCount: _images.length,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 115.33 / 130,
                          ),
                          itemBuilder: (context, index) {
                            return _GalleryCard(
                              file: _images[index],
                              selected: _selected[index],
                              onTap: () => _toggle(index),
                            );
                          },
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _QuickAddButton(onTap: _addFromGallery),
                    _ContinueButton(
                      enabled: _selectedCount > 0,
                      onTap: _continue,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_outlined, size: 40, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text('Henüz fotoğraf seçilmedi', style: AppText.navLabelInactive),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, color: AppColors.primary),
            label: const Text('Galeriden Ekle', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}

class _GalleryCard extends StatelessWidget {
  const _GalleryCard({
    required this.file,
    required this.selected,
    required this.onTap,
  });

  final XFile file;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderSubtle,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(File(file.path), fit: BoxFit.cover),
            Positioned(
              top: 7,
              right: 7,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppColors.primary : Colors.black.withOpacity(0.5),
                  border: selected
                      ? null
                      : Border.all(color: Colors.white.withOpacity(0.25)),
                ),
                child: selected
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAddButton extends StatelessWidget {
  const _QuickAddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.borderSofter),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.add, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Devam Et', style: AppText.buttonBold),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward, size: 18, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
