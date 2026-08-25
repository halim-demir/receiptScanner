import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// iOS-style status bar (time + signal/wifi/battery) used at the top of
/// every screen in the design.
class StatusBarRow extends StatelessWidget {
  const StatusBarRow({super.key});

//Silinecek
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        height: 44,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('09:41', style: AppText.time),
            Row(
              children: const [
                Icon(Icons.signal_cellular_alt, size: 18, color: Colors.white),
                SizedBox(width: 8),
                Icon(Icons.wifi, size: 18, color: Colors.white),
                SizedBox(width: 8),
                Icon(Icons.battery_full, size: 20, color: Colors.white),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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
  });

  final IconData leftIcon;
  final VoidCallback? onLeftTap;
  final IconData rightIcon;
  final VoidCallback? onRightTap;

  /// Used for the small uppercase logo+label header (Kamera / Galeri).
  final String? title;
  final IconData? titleIcon;

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
              Row(
                children: [

                ],
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
