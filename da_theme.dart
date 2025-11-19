import "package:flutter/material.dart";

class DATheme {
  static const Color black = Color(0xFF0A0E13), orange = Color(0xFFFF6A00);
  static ThemeData build() {
    final base = ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: black,
        colorScheme: ColorScheme.fromSeed(
            seedColor: orange, brightness: Brightness.dark));
    return base.copyWith(
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
        minimumSize: WidgetStateProperty.all(const Size.fromHeight(48)),
        shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        backgroundColor: WidgetStateProperty.all(const Color(0xFF1A1E24)),
        foregroundColor: WidgetStateProperty.all(Colors.white),
        side: WidgetStateProperty.all(
            BorderSide(color: orange.withValues(alpha: 0.45))),
        overlayColor:
            WidgetStateProperty.all(Colors.white.withValues(alpha: 0.06)),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
        minimumSize: WidgetStateProperty.all(const Size.fromHeight(48)),
        shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        side: WidgetStateProperty.all(
            BorderSide(color: orange.withValues(alpha: 0.6))),
        foregroundColor: WidgetStateProperty.all(Colors.white),
      )),
    );
  }
}
