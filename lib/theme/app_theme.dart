import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF090B0D);
  static const bg2 = Color(0xFF0E1012);
  static const card = Color(0xFF151719);
  static const card2 = Color(0xFF1B1D20);
  static const gold = Color(0xFFE9BC67);
  static const goldBright = Color(0xFFFFD98A);
  static const goldDim = Color(0xFF8D6D33);
  static const line = Color(0xFF3C3529);
  static const text = Color(0xFFF3F1EB);
  static const text2 = Color(0xFFA5A8AD);
  static const green = Color(0xFF52D486);
  static const amber = Color(0xFFFFB955);
  static const red = Color(0xFFFF5C5C);
}

class AppTheme {
  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.gold,
      brightness: Brightness.dark,
      surface: AppColors.card,
    );
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: scheme.copyWith(
        primary: AppColors.gold,
        secondary: AppColors.goldBright,
        surface: AppColors.card,
      ),
      fontFamilyFallback: const ['SF Pro Display', 'PingFang SC', 'Microsoft YaHei'],
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: AppColors.text,
      ),
      dividerColor: AppColors.line,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card2,
        hintStyle: const TextStyle(color: AppColors.text2),
        labelStyle: const TextStyle(color: AppColors.text2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.2),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.card2,
        contentTextStyle: TextStyle(color: AppColors.text),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0C0E10),
        indicatorColor: AppColors.gold.withOpacity(.15),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            color: s.contains(WidgetState.selected) ? AppColors.gold : AppColors.text2,
            fontSize: 11,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? AppColors.gold : AppColors.text2,
          ),
        ),
      ),
    );
  }
}
