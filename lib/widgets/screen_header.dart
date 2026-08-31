import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Circular translucent icon button used for header actions
/// (settings, history, back, more...).
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.iconChipBg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}

/// The "Kamera" / "Galeri" style centered logo+title header row, or a
/// back-arrow + centered title + more-menu row (used on Processing).
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.leftIcon,
    required this.onLeftTap,
    required this.rightIcon,
    this.onRightTap,
    this.title,
    this.titleIcon,
    this.centeredTitle,
    this.onTitleTap,
  });

  final IconData leftIcon;
  final VoidCallback? onLeftTap;
  final IconData rightIcon;
  final VoidCallback? onRightTap;

  /// Used for the small uppercase logo+label header (Kamera / Galeri).
  final String? title;
  final IconData? titleIcon;
  final VoidCallback? onTitleTap;

  /// Used for the plain centered title (Processing screen: "İşlem").
  final String? centeredTitle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            HeaderIconButton(icon: leftIcon, onTap: onLeftTap),
            if (title != null)
              InkWell(
                onTap: onTitleTap,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      if (titleIcon != null)
                        Icon(titleIcon, size: 18, color: AppColors.primary),
                      if (titleIcon != null) const SizedBox(width: 6),
                      Text(title!.toUpperCase(), style: AppText.headerTitle),
                      if (onTitleTap != null) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down, size: 16, color: AppColors.textMuted),
                      ],
                    ],
                  ),
                ),
              )
            else if (centeredTitle != null)
              Text(centeredTitle!, style: AppText.processingTitle),
            HeaderIconButton(icon: rightIcon, onTap: onRightTap),
          ],
        ),
      ),
    );
  }
}
