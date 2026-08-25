import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens extracted from the Figma "Android UI Kit" receipt-scanner
/// screens (screen-camera, screen-gallery, screen-processing).
class AppColors {
  AppColors._();

  // Dark surfaces
  static const Color bgCamera = Color(0xFF0D0F12);
  static const Color bgDark = Color(0xFF0F1115);
  static const Color card = Color(0xFF1C1F26);

  // Brand / accent
  static const Color primary = Color(0xFF008B7A);
  static const Color primarySoft = Color(0x1F008B7A); // ~0.12 alpha
  static const Color primarySofter = Color(0x33008B7A); // ~0.2 alpha

  // Text on dark
  static const Color textOnDark = Colors.white;
  static const Color textMuted = Color(0xFF94A3B8);

  // Danger
  static const Color danger = Color(0xFFFF4B4B);
  static const Color dangerSoft = Color(0x21FF4B4B); // ~0.13 alpha
  static const Color dangerBorder = Color(0x40FF4B4B); // ~0.25 alpha
  static const Color dangerBg = Color(0xFFFEF2F2);
  static const Color dangerBgBorder = Color(0xFFFEE2E2);

  // Light form panel (processing screen)
  static const Color panelWhite = Colors.white;
  static const Color panelTextDark = Color(0xFF1E293B);
  static const Color panelLabel = Color(0xFF64748B);
  static const Color rowBg = Color(0xFFF4F6F8);
  static const Color rowBorder = Color(0xFFE2E8F0);

  // Misc borders / glass
  static const Color borderSubtle = Color(0x1AFFFFFF); // ~0.1 alpha
  static const Color borderSofter = Color(0x21FFFFFF); // ~0.13 alpha
  static const Color glassNavBg = Color(0xE61C1F26); // ~0.9 alpha
  static const Color iconChipBg = Color(0x14FFFFFF); // ~0.08 alpha
}

class AppText {
  AppText._();

  static TextStyle get _base => GoogleFonts.inter();

  static TextStyle time = _base.copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textOnDark,
  );

  static TextStyle headerTitle = _base.copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.textOnDark,
    letterSpacing: 0.5,
  );

  static TextStyle processingTitle = _base.copyWith(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textOnDark,
  );

  static TextStyle navLabelActive = _base.copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.primary,
  );

  static TextStyle navLabelInactive = _base.copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textMuted,
  );

  static TextStyle pillDanger = _base.copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.danger,
  );

  static TextStyle pillPrimary = _base.copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.primary,
  );

  static TextStyle buttonBold = _base.copyWith(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.textOnDark,
  );

  static TextStyle formPanelTitle = _base.copyWith(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.panelTextDark,
  );

  static TextStyle accuracyPill = _base.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.primary,
  );

  static TextStyle fieldLabel = _base.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.panelLabel,
  );

  static TextStyle fieldValue = _base.copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.panelTextDark,
  );

  static TextStyle exportButton = _base.copyWith(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.textOnDark,
  );
}
