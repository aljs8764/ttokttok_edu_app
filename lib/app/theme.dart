import 'package:flutter/material.dart';

/// 앱 UI/UX 디자인 토큰 (프로젝트 문서 claude/design/app_uiux_design.md, 2026-10-13)
/// Ink #17233A · Ground #F4F2EC · Surface #FFFFFF · Accent #FFCE3D, 서체 IBM Plex Sans KR.
/// 상태는 색 + 텍스트 라벨을 함께 쓴다 (색만으로 구분하지 않음). 글자색은 배경 대비 4.5:1 이상.
class AppColors {
  // 기본
  static const ink = Color(0xFF17233A);
  static const ground = Color(0xFFF4F2EC);
  static const card = Colors.white;
  static const line = Color(0xFFE7E4DC);
  static const inputBorder = Color(0xFFD9D5CA);

  /// 브랜드 강조 — 채움(로고·주요 CTA·선택 표시) 전용. 흰 배경 위 글자색으로 쓰지 않는다 (대비 부족)
  static const accent = Color(0xFFFFCE3D);

  /// 흰 배경 위에서 눈에 띄어야 하는 글자·아이콘 (미처리 수 배지, 고정·안읽음 표시 등)
  static const highlight = Color(0xFFD9480F);

  // 등원 / 하원 / 예정 / 경고
  static const checkInBg = Color(0xFFE3EAFD);
  static const checkInFg = Color(0xFF1F47B8);
  static const checkOutBg = Color(0xFFFCE9DA);
  static const checkOutFg = Color(0xFF9A400A);
  static const checkOutButton = Color(0xFFC2560F);
  static const plannedBg = Color(0xFFEFEDE7);
  static const plannedFg = Color(0xFF4A5366);
  static const dangerBg = Color(0xFFFDECEC);
  static const dangerFg = Color(0xFFA01818);
  static const noticeBg = Color(0xFFFFF3CC);
  static const noticeFg = Color(0xFF7A5A00);

  // 교사 앱 다크 화면 (로그인·튜토리얼)
  static const inkField = Color(0xFF22314F);
  static const inkFieldBorder = Color(0xFF3A4A68);
  static const inkTextSecondary = Color(0xFFC9D2E3);

  // 기존 화면에서 쓰던 의미 이름 — 새 토큰에 맞춰 둔다
  static const primary = ink;
  static const surface = ground;
  static const textSecondary = Color(0xFF5B6577);
  static const success = checkInFg;
  static const error = dangerFg;
  static const warning = Color(0xFFB45309);
  static const info = checkInFg;
  static const muted = Color(0xFF8A92A3);
}

/// 모서리 (카드 16–22, 버튼 12–16)
class AppRadius {
  static const card = 20.0;
  static const cardSmall = 16.0;
  static const button = 16.0;
  static const field = 14.0;
  static const chip = 999.0;
}

const kFontFamily = 'IBMPlexSansKR';

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.ink,
    primary: AppColors.ink,
    onPrimary: Colors.white,
    secondary: AppColors.accent,
    onSecondary: AppColors.ink,
    surface: Colors.white,
    onSurface: AppColors.ink,
    error: AppColors.error,
  );
  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button));
  final fieldRadius = BorderRadius.circular(AppRadius.field);
  const buttonText = TextStyle(fontFamily: kFontFamily, fontSize: 16, fontWeight: FontWeight.w700);
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: kFontFamily);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.ground,
    textTheme: base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.ground,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: kFontFamily, fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink, letterSpacing: -0.4),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cardSmall)),
    ),
    listTileTheme: const ListTileThemeData(iconColor: AppColors.ink, minVerticalPadding: 10),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: const TextStyle(color: AppColors.plannedFg),
      border: OutlineInputBorder(borderRadius: fieldRadius, borderSide: const BorderSide(color: AppColors.inputBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: fieldRadius, borderSide: const BorderSide(color: AppColors.inputBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: fieldRadius, borderSide: const BorderSide(color: AppColors.ink, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 52),
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        backgroundColor: Colors.white,
        minimumSize: const Size(64, 52),
        side: const BorderSide(color: AppColors.inputBorder),
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.checkInFg, minimumSize: const Size(44, 44)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.ink,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: AppColors.ink,
      secondarySelectedColor: AppColors.ink,
      checkmarkColor: Colors.white,
      side: const BorderSide(color: AppColors.inputBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.chip)),
      // 선택된 칩은 Ink 바탕 + 흰 글자
      labelStyle: TextStyle(
        fontFamily: kFontFamily,
        fontWeight: FontWeight.w600,
        color: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.ink),
      ),
      secondaryLabelStyle: const TextStyle(fontFamily: kFontFamily, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.accent.withValues(alpha: 0.35),
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: kFontFamily,
          fontSize: 11,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? AppColors.ink : const Color(0xFF6B7487),
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.ink : const Color(0xFF6B7487)),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.ink,
      unselectedLabelColor: AppColors.textSecondary,
      indicatorColor: AppColors.ink,
      dividerColor: AppColors.line,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: AppColors.inputBorder,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
    ),
    badgeTheme: const BadgeThemeData(backgroundColor: AppColors.highlight, textColor: Colors.white),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: const TextStyle(fontFamily: kFontFamily, color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.ink),
  );
}
