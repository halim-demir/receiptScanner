import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The frosted-glass pill navigation bar with "Kamera" / "Galeri" tabs,
/// as seen at the bottom of screen-camera and screen-gallery.
class GlassBottomNav extends StatelessWidget {
  const GlassBottomNav({
    super.key,
    required this.currentIndex,
    required this.onChanged,
  });

  final int currentIndex; // 0 = Kamera, 1 = Galeri
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: AppColors.glassNavBg,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _NavTab(
                  icon: Icons.camera_alt_outlined,
                  label: 'Kamera',
                  active: currentIndex == 0,
                  onTap: () => onChanged(0),
                ),
                _NavTab(
                  icon: Icons.image_outlined,
                  label: 'Galeri',
                  active: currentIndex == 1,
                  onTap: () => onChanged(1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: active ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: active ? AppText.navLabelActive : AppText.navLabelInactive,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The thin white/dark pill at the very bottom representing the iOS
/// home indicator.
class HomeIndicator extends StatelessWidget {
  const HomeIndicator({super.key, this.dark = false});

  /// When [dark] is true, the bar is rendered dark (used on the white
  /// bottom-action-bar of the Processing screen).
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 21, bottom: 8),
      child: Center(
        child: Container(
          width: 139,
          height: 5,
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(100),
          ),
        ),
      ),
    );
  }
}
