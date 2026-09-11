import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFFF3F5F7);
  static const surface = Colors.white;

  static const primary = Color(0xFF17365D);
  static const primaryStrong = Color(0xFF102A48);
  static const primaryLight = Color(0xFFEAF0F6);

  static const textPrimary = Color(0xFF1B252F);
  static const textSecondary = Color(0xFF53616F);
  static const textMuted = Color(0xFF7B8793);

  static const border = Color(0xFFD5DBE1);
  static const borderStrong = Color(0xFFB8C1CA);

  static const success = Color(0xFF247A52);
  static const successLight = Color(0xFFEAF5EF);

  static const danger = Color(0xFFB3261E);
  static const dangerLight = Color(0xFFFBEDEC);

  static const warning = Color(0xFFA66300);
  static const cameraBackground = Color(0xFF111820);
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
