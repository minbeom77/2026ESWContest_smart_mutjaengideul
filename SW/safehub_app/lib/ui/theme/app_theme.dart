import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFFF6F8FC);
  static const surface = Colors.white;

  static const primary = Color(0xFF2563EB);
  static const primaryLight = Color(0xFFEFF6FF);

  static const textPrimary = Color(0xFF182033);
  static const textSecondary = Color(0xFF697386);
  static const textMuted = Color(0xFF98A2B3);

  static const border = Color(0xFFE7EBF2);

  static const success = Color(0xFF16A34A);
  static const successLight = Color(0xFFF0FDF4);

  static const danger = Color(0xFFDC2626);
  static const dangerLight = Color(0xFFFEF2F2);
}

class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ),
    );
  }
}