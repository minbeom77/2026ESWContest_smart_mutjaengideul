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
