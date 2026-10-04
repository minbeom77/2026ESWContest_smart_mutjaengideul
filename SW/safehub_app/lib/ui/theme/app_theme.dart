import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFFF5F7FA);
  static const surface = Colors.white;

  static const primary = Color(0xFF3F78B5);
  static const primaryStrong = Color(0xFF235B96);
  static const primaryLight = Color(0xFFEDF5FC);
  static const primarySoft = Color(0xFFD7E7F5);
  static const header = Color(0xFFF8FAFC);

  static const textPrimary = Color(0xFF172536);
  static const textSecondary = Color(0xFF536476);
  static const textMuted = Color(0xFF7B8997);
  static const border = Color(0xFFD3DAE2);

  static const success = Color(0xFF258765);
  static const successLight = Color(0xFFE9F7F1);
  static const warning = Color(0xFFC48218);
  static const warningLight = Color(0xFFFFF5DF);
  static const danger = Color(0xFFD64C4C);
  static const dangerLight = Color(0xFFFFEEEE);
}

class AppTheme {
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Pretendard',
    scaffoldBackgroundColor: const Color(0xFF29231F),
    dividerColor: const Color(0x33FFFFFF),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFFFFA49A),
      onPrimary: Color(0xFF3C211D),
      surface: Color(0xFF332923),
      onSurface: Color(0xFFFFF6F1),
      error: Color(0xFFFF8B7C),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF241D19),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0x55E0CEC5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFFA49A), width: 2),
      ),
      counterStyle: const TextStyle(color: Color(0xFFE0CEC5)),
    ),
  );

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'Pretendard',
      scaffoldBackgroundColor: AppColors.background,
      dividerColor: AppColors.border,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        fontFamily: 'Pretendard',
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
    );
  }
}
